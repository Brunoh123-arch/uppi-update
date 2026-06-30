/**
 * ARRIVED-AT-PICKUP Handler — Motorista chegou no ponto de coleta
 * Migrado de: index.ts
 */

import { getServiceClient, getSupabaseUser, cleanFcmToken } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm-client.ts';

export async function handleArrivedAtPickup(req: Request): Promise<Response> {
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

    // 🛡️ Validar transição de status (apenas aceita se o status atual for accepted ou driver_accepted)
    if (ride.status !== 'accepted' && ride.status !== 'driver_accepted') {
      return errorResponse(`Não é possível marcar como chegado para uma corrida no status '${ride.status}'.`, 400, req);
    }

    // 2. Atualizar status
    const { error: updateErr } = await supa
      .from('rides')
      .update({
        status: 'arrived',
        arrived_at: new Date().toISOString(),
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
        title: 'Motorista chegou! 📍',
        body: 'Seu motorista já está no local de embarque.',
        data: { ride_id: rideId, type: 'driver_arrived' },
        channelId: 'tripEvents',
      });
      if (pushResult.invalidToken) {
        await cleanFcmToken(ride.rider_id, riderProfile.fcm_token);
      }
    }

    // 4. Registrar atividade
    await supa.from('ride_activities').insert({
      ride_id: rideId,
      type: 'arrived',
      actor_id: uid,
    });

    return jsonResponse({ success: true, status: 'arrived' }, 200, req);

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('arrived-at-pickup error:', msg);
    return errorResponse(msg, 500, req);
  }
}
