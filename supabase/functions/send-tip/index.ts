/**
 * SEND-TIP — Enviar gorjeta para o motorista (Hardened)
 * Migrado de: functions/src/tipping/tipping.functions.ts
 */

import { getServiceClient, getSupabaseUser, cleanFcmToken } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm-client.ts';
import { tipLimiter } from '../_shared/rate-limiter.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse(req);

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401, req);
    const uid = user.id;

    const body = await req.json();
    const payload = body.args ?? body;
    const { ride_id, orderId, amount, action } = payload;
    const rideId = ride_id || orderId;

    if (!rideId) {
      return errorResponse('ride_id é obrigatório', 400, req);
    }

    const supa = getServiceClient();

    // Estados em que a corrida já terminou e a gorjeta é permitida. O finish_ride
    // deixa a corrida como 'waiting_for_review' — exatamente o momento em que a
    // tela de avaliação/gorjeta aparece para o passageiro. Exigir só
    // 'completed'/'finished' fazia toda gorjeta ser rejeitada nesse fluxo.
    const TIP_ALLOWED_STATUSES = [
      'completed',
      'finished',
      'waiting_for_review',
      'waiting_for_post_pay',
    ];

    // ─── AÇÃO: SUGESTÕES ────────────────────────────────────────────────
    // Retorna 3 sugestões (10/15/20% da tarifa) e se a corrida já tem gorjeta.
    if (action === 'suggestions') {
      const { data: ride } = await supa
        .from('rides')
        .select('fare, original_fare, tip_amount, rider_id')
        .eq('id', rideId)
        .single();
      if (!ride) return errorResponse('Corrida não encontrada', 404, req);
      if (ride.rider_id !== uid) return errorResponse('Sem permissão', 403, req);

      const base = Number(ride.original_fare ?? ride.fare ?? 0);
      const nice = (v: number) =>
        v < 1 ? 1 : (v < 5 ? Math.ceil(v) : Math.ceil(v / 5) * 5);
      const suggestions = base > 0
        ? [nice(base * 0.10), nice(base * 0.15), nice(base * 0.20)]
        : [2, 5, 10];
      const alreadyTipped = Number(ride.tip_amount ?? 0) > 0;

      return jsonResponse({ suggestions, alreadyTipped }, 200, req);
    }

    // ─── AÇÃO: ENVIAR GORJETA ───────────────────────────────────────────
    if (tipLimiter.isRateLimited(uid)) {
      return errorResponse('Muitas solicitações. Aguarde um momento.', 429, req);
    }

    if (!amount || Number(amount) <= 0) {
      return errorResponse('amount é obrigatório', 400, req);
    }

    const tipAmount = Number(amount);

    // 🛡️ Limites mínimo e máximo de gorjeta para evitar fraudes ou digitação incorreta
    if (tipAmount < 1.00) {
      return errorResponse('O valor mínimo permitido para gorjeta é R$ 1,00', 400, req);
    }
    if (tipAmount > 200.00) {
      return errorResponse('O valor máximo permitido para gorjeta é R$ 200,00', 400, req);
    }

    // 1. Buscar corrida
    const { data: ride } = await supa
      .from('rides')
      .select('driver_id, rider_id, status, tip_amount')
      .eq('id', rideId)
      .single();

    if (!ride) return errorResponse('Corrida não encontrada', 404, req);
    if (ride.rider_id !== uid) return errorResponse('Sem permissão', 403, req);
    if (!ride.driver_id) return errorResponse('Corrida sem motorista', 400, req);

    // 🛡️ Impedir gorjetas em corridas não concluídas ou canceladas
    if (!TIP_ALLOWED_STATUSES.includes(ride.status)) {
      return errorResponse('Só é possível dar gorjeta em corridas concluídas', 400, req);
    }

    // 🛡️ Evitar gorjeta em duplicidade na mesma corrida
    if (Number(ride.tip_amount ?? 0) > 0) {
      return errorResponse('Esta corrida já recebeu uma gorjeta', 400, req);
    }

    // 2. Debitar do passageiro
    const { data: riderWallet } = await supa
      .from('wallets')
      .select('balance')
      .eq('user_id', uid)
      .single();

    const riderBalance = Number(riderWallet?.balance) || 0;
    if (riderBalance < tipAmount) {
      return errorResponse('Saldo insuficiente para gorjeta', 400, req);
    }

    const { error: debitError } = await supa.rpc('increment_wallet', {
      target_user_id: uid,
      amount_to_add: -tipAmount
    });
    
    if (debitError) {
      return errorResponse('Erro ao debitar saldo', 500, req);
    }

    // 3. Creditar no motorista
    const { error: creditError } = await supa.rpc('increment_wallet', {
      target_user_id: ride.driver_id,
      amount_to_add: tipAmount
    });

    if (creditError) {
      // BUG FIX #5: Rollback — rider was already debited. If driver credit fails,
      // refund the rider to prevent money disappearing from the system.
      console.error('Erro ao creditar gorjeta no motorista — fazendo rollback', creditError);
      await supa.rpc('increment_wallet', {
        target_user_id: uid,
        amount_to_add: tipAmount // refund
      });
      return errorResponse('Falha ao processar gorjeta. Saldo reembolsado.', 500, req);
    }

    const { data: driverProfile } = await supa
      .from('profiles')
      .select('fcm_token')
      .eq('id', ride.driver_id)
      .single();

    // 4. Registrar transações
    await supa.from('wallet_transactions').insert([
      {
        user_id: uid,
        amount: -tipAmount,
        type: 'tip',
        description: `Gorjeta - Corrida #${rideId.substring(0, 8)}`,
        ride_id: rideId,
        status: 'completed',
      },
      {
        user_id: ride.driver_id,
        amount: tipAmount,
        type: 'tip',
        description: `Gorjeta recebida - Corrida #${rideId.substring(0, 8)}`,
        ride_id: rideId,
        status: 'completed',
      },
    ]);

    // 5. Atualizar gorjeta na corrida
    await supa
      .from('rides')
      .update({ tip_amount: tipAmount })
      .eq('id', rideId);

    // 6. Notificar motorista
    if (driverProfile?.fcm_token) {
      const pushResult = await sendPush({
        token: driverProfile.fcm_token,
        title: 'Gorjeta recebida! 🎉',
        body: `Você recebeu R$ ${tipAmount.toFixed(2)} de gorjeta!`,
        data: { type: 'tip_received', ride_id: rideId },
        channelId: 'wallet',
      });
      if (pushResult.invalidToken) {
        await cleanFcmToken(ride.driver_id, driverProfile.fcm_token);
      }
    }

    return jsonResponse({
      success: true,
      tipAmount,
    }, 200, req);

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('send-tip error:', msg);
    return errorResponse(msg, 500, req);
  }
});
