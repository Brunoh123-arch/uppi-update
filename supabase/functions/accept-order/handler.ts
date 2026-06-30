/**
 * ACCEPT-ORDER Handler — Motorista aceita uma corrida
 * Migrado de: index.ts
 */

import { getServiceClient, getSupabaseUser, cleanFcmToken } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm-client.ts';
import { defaultLimiter } from '../_shared/rate-limiter.ts';

export async function handleAcceptOrder(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return optionsResponse(req);

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401, req);
    const uid = user.id;

    // Rate limiting — máx 30 tentativas de aceitar por minuto por motorista
    if (defaultLimiter.isRateLimited(uid)) {
      return errorResponse('Muitas tentativas. Aguarde um momento.', 429, req);
    }

    const body = await req.json();
    const { orderId, ride_id } = body.args ?? body;
    const rideId = orderId || ride_id;

    if (!rideId) return errorResponse('orderId é obrigatório', 400, req);

    const supa = getServiceClient();

    // 1. Verificar se o motorista existe e está ativo
    const { data: driver } = await supa
      .from('profiles')
      .select('role, status')
      .eq('id', uid)
      .single();

    if (!driver || driver.role !== 'driver') {
      const msg = driver?.role === 'rider' ? 'Acesso negado - conta de passageiro' : 'Acesso negado - requer conta de motorista';
      return errorResponse(msg, 403, req);
    }

    // Verificar assinatura na tabela protegida driver_subscriptions (bloqueada contra edições do cliente)
    const { data: subscription } = await supa
      .from('driver_subscriptions')
      .select('valid_until')
      .eq('driver_id', uid)
      .maybeSingle();

    if (subscription && subscription.valid_until) {
      if (new Date(subscription.valid_until) < new Date()) {
        return errorResponse('Assinatura Uppi vencida. Regularize sua mensalidade.', 403, req);
      }
    }

    // 2. Buscar a corrida
    const { data: ride, error: rideErr } = await supa
      .from('rides')
      .select('*')
      .eq('id', rideId)
      .single();

    if (rideErr || !ride) return errorResponse('Corrida não encontrada', 404, req);

    // 3. Verificar se ainda está disponível
    const availableStatuses = ['requested', 'searching'];
    if (!availableStatuses.includes(ride.status)) {
      return errorResponse('Corrida já aceita ou cancelada', 409, req);
    }

    if (ride.driver_id && ride.driver_id !== uid) {
      return errorResponse('Corrida já aceita por outro motorista', 409, req);
    }

    // 🛡️ [Item D1] Usar a RPC segura assign_driver_to_ride para aceitar a corrida (eliminando caminhos divergentes)
    const { error: rpcErr } = await supa.rpc("assign_driver_to_ride", {
      p_ride_id: rideId,
      p_driver_id: uid,
    });

    if (rpcErr) {
      console.error("Erro ao chamar assign_driver_to_ride RPC:", rpcErr);
      // Mapear erros da RPC para mensagens mais amigáveis
      const msg = rpcErr.message;
      if (msg.includes('oferta ativa') || msg.includes('active offer') || msg.includes('no active offer')) {
        return errorResponse('O tempo para aceitar esta corrida expirou. Aguarde uma nova oferta.', 410, req);
      }
      if (msg.includes('não está mais disponível') || msg.includes('no longer available') || msg.includes('already accepted') || msg.includes('já aceita')) {
        return errorResponse('Esta corrida já foi aceita por outro motorista.', 409, req);
      }
      return errorResponse(msg, 422, req);
    }

    // 6. Atualizar status do motorista
    await supa
      .from('driver_locations')
      .update({ status: 'in_service' })
      .eq('driver_id', uid);

    await supa
      .from('profiles')
      .update({ status: 'in_progress' })
      .eq('id', uid);

    // 7. Buscar o perfil do passageiro para ver fcm_token, full_name e se deseja PIN de embarque
    const { data: riderProfile } = await supa
      .from('profiles')
      .select('fcm_token, full_name, boarding_pin_enabled')
      .eq('id', ride.rider_id)
      .single();

    // 🔐 GERAR PIN DE EMBARQUE: apenas se ativado pelo passageiro
    const requiresPin = riderProfile?.boarding_pin_enabled === true;
    let boardingPin = null;

    if (requiresPin) {
      boardingPin = String(Math.floor(1000 + Math.random() * 9000));
      await supa
        .from('rides')
        .update({ boarding_pin: boardingPin })
        .eq('id', rideId);
    }

    // Buscar o eta_pickup atualizado da corrida (calculado pela RPC no banco)
    const { data: updatedRide } = await supa
      .from('rides')
      .select('eta_pickup')
      .eq('id', rideId)
      .single();

    const etaPickup = updatedRide?.eta_pickup || null;
    let etaMinutes: number | null = null;
    if (etaPickup) {
      etaMinutes = Math.max(1, Math.ceil((new Date(etaPickup).getTime() - Date.now()) / 60000));
    }

    if (riderProfile?.fcm_token) {
      const pushResult = await sendPush({
        token: riderProfile.fcm_token,
        title: 'Motorista a caminho! 🚗',
        body: boardingPin 
          ? `Seu motorista está a caminho. ${etaMinutes ? `Chegada estimada: ${etaMinutes} min` : ''} | 🔐 PIN de embarque: ${boardingPin}`
          : `Seu motorista está a caminho. ${etaMinutes ? `Chegada estimada: ${etaMinutes} min` : ''}`,
        data: { 
          ride_id: rideId, 
          type: 'driver_accepted', 
          ...(boardingPin ? { boarding_pin: boardingPin } : {}) 
        },
        channelId: 'tripEvents',
      });
      if (pushResult.invalidToken) {
        await cleanFcmToken(ride.rider_id, riderProfile.fcm_token);
      }
    }

    // 8. Registrar atividade
    await supa.from('ride_activities').insert({
      ride_id: rideId,
      type: 'driver_accepted',
      actor_id: uid,
    });

    return jsonResponse({
      success: true,
      ride_id: rideId,
      driver_id: uid,
      eta_pickup: etaPickup,
      eta_minutes: etaMinutes,
      boarding_pin: boardingPin,
    }, 200, req);

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('accept-order error:', msg);
    return errorResponse(msg, 500, req);
  }
}
