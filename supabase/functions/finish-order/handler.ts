/**
 * FINISH-ORDER Handler — Finalizar corrida e processar pagamento/comissão
 * Migrado de: index.ts
 */

import { getServiceClient, verifyDriver, cleanFcmToken } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm-client.ts';

export async function handleFinishOrder(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return optionsResponse(req);

  try {
    // 🛡️ Segurança: Validar token JWT e garantir que o chamador é um motorista
    let uid: string;
    try {
      uid = await verifyDriver(req);
    } catch (err: any) {
      const isNotDriver = err.message.includes('requer conta de motorista');
      const msg = isNotDriver ? 'Acesso negado - conta de passageiro' : err.message;
      return errorResponse(msg, err.message.includes('Não autenticado') ? 401 : 403, req);
    }

    const body = await req.json();
    const { orderId, ride_id, cashAmount, tollAmount, actualDistance } = body.args ?? body;
    const rideId = orderId || ride_id;
    const cash = Number(cashAmount) || 0;
    const toll = tollAmount !== undefined && tollAmount !== null ? Number(tollAmount) : 0;
    const dist = actualDistance !== undefined && actualDistance !== null ? Number(actualDistance) : null;

    if (!rideId) return errorResponse('orderId é obrigatório', 400, req);

    const supa = getServiceClient();

    // Executa toda a transação financeira de forma ACID no banco de dados
    const { data: dbResult, error: rpcError } = await supa.rpc('finish_ride', {
      p_ride_id: rideId,
      p_driver_id: uid,
      p_cash_amount: cash,
      p_toll_amount: toll,
      p_actual_distance: dist,
    });

    if (rpcError) {
      console.error('[FinishOrder] Erro ao executar RPC finish_ride:', rpcError);
      return errorResponse(rpcError.message, 500, req);
    }

    if (!dbResult || !dbResult.success) {
      return errorResponse(dbResult?.message || 'Erro ao processar finalização de corrida.', 400, req);
    }

    // 🏆 Gamificação: Disparar verificação de badges para o motorista e o passageiro em background (Item C19)
    const badgePromises = [];
    if (dbResult.rider_id) {
      badgePromises.push(triggerCheckBadge(dbResult.rider_id));
    }
    badgePromises.push(triggerCheckBadge(uid));
    await Promise.all(badgePromises).catch(err => {
      console.error('[FinishOrder] Erro na verificação de conquistas:', err);
    });

    // Enviar push notification para o passageiro via FCM em background
    if (dbResult.rider_fcm_token) {
      try {
        const pushResult = await sendPush({
          token: dbResult.rider_fcm_token,
          title: 'Corrida finalizada! ✅',
          body: `Valor: R$ ${Number(dbResult.fare).toFixed(2).replace('.', ',')}. Avalie seu motorista!`,
          data: { ride_id: rideId, type: 'ride_finished' },
          channelId: 'tripEvents',
        });
        if (pushResult.invalidToken) {
          await cleanFcmToken(dbResult.rider_id, dbResult.rider_fcm_token);
        }
      } catch (pushErr) {
        console.error('[FinishOrder] Falha no envio de push para o passageiro:', pushErr);
      }
    }

    return jsonResponse(dbResult, 200, req);

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('finish-order error:', msg);
    return errorResponse(msg, 500, req);
  }
}

// Helper para disparar a verificação de badges de forma assíncrona
async function triggerCheckBadge(userId: string) {
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceKey) return;

    const functionUrl = `${supabaseUrl}/functions/v1/check-badge`;
    const response = await fetch(functionUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${serviceKey}`
      },
      body: JSON.stringify({ userId })
    });
    if (!response.ok) {
      console.error(`[triggerCheckBadge] Erro ao verificar conquistas do usuário ${userId}:`, await response.text());
    } else {
      console.log(`[triggerCheckBadge] Verificação de conquistas disparada para o usuário ${userId}`);
    }
  } catch (err) {
    console.error(`[triggerCheckBadge] Falha de rede ao disparar conquistas para o usuário ${userId}:`, err);
  }
}
