/**
 * WEBHOOK: Nova Corrida (Direcionada por Oferta) — HARDENED
 * Disparado via Database Trigger quando uma nova oferta é inserida na tabela `ride_offers`
 * com status = 'offered'.
 * 
 * Pipeline de notificação em 3 camadas:
 *   1. FCM Push HIGH priority direcionado → acorda o app do motorista específico em background
 *   2. Supabase Broadcast → atualização instantânea in-app
 *   3. Limpeza automática de token FCM se inválido
 */

import { getServiceClient, cleanFcmToken } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm-client.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse(req);

  const startTime = Date.now();

  try {
    // 1. Validar autenticação via WEBHOOK_SECRET
    const webhookSecret = Deno.env.get('WEBHOOK_SECRET');
    const incomingSecret = req.headers.get('x-webhook-secret') || req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '').trim();

    if (!webhookSecret || incomingSecret !== webhookSecret) {
      console.error('[webhook-new-ride] Tentativa de acesso não autorizado');
      return errorResponse('Não autorizado', 401, req);
    }

    const payload = await req.json();
    console.log('[webhook-new-ride] payload recebido:', JSON.stringify(payload).substring(0, 500));

    // 2. Validação robusta do payload do trigger
    if (payload.type !== 'INSERT' || payload.table !== 'ride_offers') {
      return jsonResponse({ ignored: true, reason: 'Não é um INSERT em ride_offers' }, 200, req);
    }

    const newOffer = payload.record;
    if (!newOffer || newOffer.status !== 'offered') {
      return jsonResponse({ ignored: true, reason: 'Status da oferta não é offered' }, 200, req);
    }

    const { ride_id, driver_id } = newOffer;
    if (!ride_id || !driver_id) {
      return jsonResponse({ ignored: true, reason: 'Dados da oferta incompletos' }, 200, req);
    }

    const supa = getServiceClient();

    // 3. Buscar os dados do motorista específico para obter o FCM Token
    const { data: profile, error: profileErr } = await supa
      .from('profiles')
      .select('id, fcm_token')
      .eq('id', driver_id)
      .single();

    if (profileErr) throw profileErr;
    if (!profile || !profile.fcm_token) {
      console.log('[webhook-new-ride] Motorista não possui token FCM:', driver_id);
      return jsonResponse({ ignored: true, reason: 'Motorista sem token FCM' }, 200, req);
    }

    // 4. Buscar informações da corrida para montar a notificação
    const { data: ride, error: rideErr } = await supa
      .from('rides')
      .select('id, fare, pickup_address, pickup_lat, pickup_lng')
      .eq('id', ride_id)
      .single();

    if (rideErr) throw rideErr;
    if (!ride) {
      console.log('[webhook-new-ride] Corrida não encontrada:', ride_id);
      return jsonResponse({ ignored: true, reason: 'Corrida não encontrada' }, 200, req);
    }

    // 🛡️ [Item D6] Filtrar se o motorista já rejeitou a corrida
    const { data: isRejected } = await supa
      .from('ride_rejected_drivers')
      .select('driver_id')
      .eq('ride_id', ride_id)
      .eq('driver_id', driver_id)
      .maybeSingle();

    if (isRejected) {
      console.log('[webhook-new-ride] Motorista já rejeitou esta corrida:', driver_id);
      return jsonResponse({ ignored: true, reason: 'Motorista já rejeitou a corrida' }, 200, req);
    }

    // 🛡️ [Item D7] Filtrar se o motorista está em uma corrida ativa
    const { data: activeRide } = await supa
      .from('rides')
      .select('id')
      .eq('driver_id', driver_id)
      .in('status', ['accepted', 'driver_accepted', 'arrived', 'in_progress', 'started'])
      .maybeSingle();

    if (activeRide) {
      console.log('[webhook-new-ride] Motorista em corrida ativa:', driver_id);
      return jsonResponse({ ignored: true, reason: 'Motorista em corrida ativa' }, 200, req);
    }

    // 5. Enviar FCM Push Notification direcionada apenas para o motorista da oferta
    const title = '🚕 Nova corrida disponível!';
    const fareStr = ride.fare ? `R$ ${Number(ride.fare).toFixed(2).replace('.', ',')}` : '';
    const bodyText = `Embarque: ${ride.pickup_address || 'Visualizar endereço de partida no aplicativo'}${fareStr ? `\nGanho estimado: ${fareStr}` : ''}`;
    
    const data = {
      type: 'new_ride_request',
      ride_id: ride.id.toString(),
      pickup_lat: (ride.pickup_lat ?? '').toString(),
      pickup_lng: (ride.pickup_lng ?? '').toString(),
      fare: (ride.fare ?? '0').toString(),
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
    };

    console.log(`[webhook-new-ride] Enviando push direcionado para o driver: ${driver_id}`);
    const pushResult = await sendPush({
      token: profile.fcm_token,
      title,
      body: bodyText,
      data,
      channelId: 'orders',
    });

    console.log(`[webhook-new-ride] FCM resultado para ${driver_id}:`, JSON.stringify(pushResult));

    // 6. Limpeza automática de token FCM se inválido
    if (pushResult.invalidToken) {
      await cleanFcmToken(driver_id, profile.fcm_token);
    }

    // 7. Broadcast via Supabase Realtime (garante UI atualizada caso app já esteja aberto)
    try {
      const channel = supa.channel('ride_notifications');
      await channel.send({
        type: 'broadcast',
        event: 'new_ride',
        payload: {
          ride_id: ride.id.toString(),
          pickup_lat: ride.pickup_lat,
          pickup_lng: ride.pickup_lng,
          fare: ride.fare,
          pickup_address: ride.pickup_address,
          created_at: newOffer.created_at,
        },
      });
      supa.removeChannel(channel);
    } catch (e) {
      console.warn('[webhook-new-ride] Broadcast falhou (não-crítico):', e);
    }

    const elapsed = Date.now() - startTime;
    console.log(`[webhook-new-ride] Concluído em ${elapsed}ms`);

    return jsonResponse({ 
      success: true, 
      result: pushResult,
      elapsed_ms: elapsed,
    }, 200, req);

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('[webhook-new-ride] ERRO:', msg);
    return errorResponse(msg, 500, req);
  }
});
