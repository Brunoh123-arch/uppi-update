/**
 * ARRIVED-AT-DESTINATION — Motorista chegou ao destino (aguardando pagamento)
 * Atualiza o status da corrida para 'waiting_for_post_pay' no banco de dados.
 * Necessário para evitar que o stream do Supabase sobrescreva o estado local da UI.
 */

import { getServiceClient, getSupabaseUser, cleanFcmToken } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm-client.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse(req);

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401, req);
    const uid = user.id;

    const body = await req.json();
    const { orderId, ride_id } = body.args ?? body;
    const rideId = orderId || ride_id;

    if (!rideId) return errorResponse('orderId é obrigatório', 400, req);

    const supa = getServiceClient();

    // 1. Verificar corrida e propriedade
    const { data: ride } = await supa
      .from('rides')
      .select('rider_id, status')
      .eq('id', rideId)
      .eq('driver_id', uid)
      .single();

    if (!ride) return errorResponse('Corrida não encontrada ou não pertence a você', 403, req);

    // 🛡️ Validar transição: só aceita se estiver em 'in_progress' ou 'started'
    if (ride.status !== 'in_progress' && ride.status !== 'started') {
      // Se já estiver em waiting_for_post_pay, retornar sucesso (idempotente)
      if (ride.status === 'waiting_for_post_pay') {
        return jsonResponse({ success: true, status: 'waiting_for_post_pay' }, 200, req);
      }
      return errorResponse(
        `Não é possível registrar chegada ao destino para uma corrida no status '${ride.status}'.`,
        400,
        req
      );
    }

    // 2. Atualizar status para aguardando pagamento
    const { error: updateErr } = await supa
      .from('rides')
      .update({
        status: 'waiting_for_post_pay',
        destination_arrived_at: new Date().toISOString(),
      })
      .eq('id', rideId);

    if (updateErr) return errorResponse(updateErr.message, 500, req);

    // 3. Notificar passageiro
    const { data: riderProfile } = await supa
      .from('profiles')
      .select('fcm_token')
      .eq('id', ride.rider_id)
      .single();

    if (riderProfile?.fcm_token) {
      const pushResult = await sendPush({
        token: riderProfile.fcm_token,
        title: 'Chegamos! 🏁',
        body: 'Você chegou ao destino. Confirme o pagamento para finalizar.',
        data: { ride_id: rideId, type: 'arrived_at_destination' },
        channelId: 'tripEvents',
      });
      if (pushResult.invalidToken) {
        await cleanFcmToken(ride.rider_id, riderProfile.fcm_token);
      }
    }

    // 4. Registrar atividade
    try {
      await supa.from('ride_activities').insert({
        ride_id: rideId,
        type: 'arrived_at_destination',
        actor_id: uid,
      });
    } catch (_) {
      // Silencioso — não prejudica o fluxo principal
    }

    return jsonResponse({ success: true, status: 'waiting_for_post_pay' }, 200, req);

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('arrived-at-destination error:', msg);
    return errorResponse(msg, 500, req);
  }
});
