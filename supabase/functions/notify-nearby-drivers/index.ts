/**
 * NOTIFY-NEARBY-DRIVERS — Notificar motoristas próximos de nova corrida
 * Migrado de: functions/src/orders/order.functions.ts (onOrderCreated trigger)
 * 
 * No Firebase era um Firestore trigger. No Supabase chamamos essa função
 * explicitamente ao criar uma corrida (ou via Database Webhook).
 */

import { getServiceClient, getSupabaseUser, cleanFcmToken } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm-client.ts';

function haversineDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371000; // metros
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
    Math.cos((lat2 * Math.PI) / 180) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse(req);

  try {
    // --- 🔐 AUTENTICAÇÃO E SEGURANÇA ---
    const user = await getSupabaseUser(req);
    const webhookSecret = Deno.env.get('WEBHOOK_SECRET');
    const incomingSecret = req.headers.get('x-webhook-secret') || req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '').trim();

    const isWebhookAuthorized = !!(webhookSecret && incomingSecret === webhookSecret);
    const isUserAuthorized = !!user;

    if (!isWebhookAuthorized && !isUserAuthorized) {
      console.error('Tentativa de acesso não autorizado a notify-nearby-drivers');
      return errorResponse('Não autorizado', 401, req);
    }
    // --- 🏁 FIM AUTENTICAÇÃO ---

    const body = await req.json();
    const { ride_id, rideId } = body.args ?? body;
    const id = ride_id || rideId;

    if (!id) return errorResponse('ride_id é obrigatório', 400, req);

    const supa = getServiceClient();

    // 1. Buscar corrida
    const { data: ride } = await supa
      .from('rides')
      .select('*')
      .eq('id', id)
      .single();

    if (!ride) return errorResponse('Corrida não encontrada', 404, req);
    if (ride.status !== 'requested') {
      return jsonResponse({ success: true, skipped: true, reason: 'status não é requested' }, 200, req);
    }

    // 1b. Buscar categoria do veículo para o serviço solicitado
    const { data: service } = await supa
      .from('services')
      .select('vehicle_category')
      .eq('name', ride.service_type)
      .maybeSingle();

    const targetVehicleCategory = service?.vehicle_category || 'carro';

    // 2. Buscar raio do painel administrativo (default 5km)
    let searchRadius = 5000; // metros
    const { data: radiusRow } = await supa
      .from('app_settings')
      .select('value')
      .eq('key', 'driver_search_radius')
      .maybeSingle();
    
    if (radiusRow?.value) {
      // Painel salva em Km, convertendo para metros
      searchRadius = Number(radiusRow.value) * 1000;
    }

    // 3. Buscar motoristas próximos usando PostGIS RPC (ultra rápido e de alta escala)
    const { data: drivers, error: rpcError } = await supa.rpc('nearby_drivers', {
      p_lat: ride.pickup_lat,
      p_lng: ride.pickup_lng,
      p_radius_meters: searchRadius,
    });

    if (rpcError) {
      console.error('Erro no RPC nearby_drivers:', rpcError);
      return errorResponse('Erro ao buscar motoristas próximos', 500, req);
    }

    if (!drivers || drivers.length === 0) {
      console.log('Sem motoristas próximos no raio de busca');
      return jsonResponse({ success: true, notified: 0 }, 200, req);
    }

    // 4. Filtrar motoristas que pertencem à mesma categoria de veículo solicitada
    const nearbyDrivers = drivers.filter((d: any) => {
      const driverVehicleType = d.vehicle_type || 'carro';
      return driverVehicleType === targetVehicleCategory;
    });

    if (nearbyDrivers.length === 0) {
      console.log('Sem motoristas correspondentes à categoria no raio de busca');
      return jsonResponse({ success: true, notified: 0 }, 200, req);
    }

    // 4. Buscar FCM tokens
    const driverIds = nearbyDrivers.map((d) => d.driver_id);
    const { data: profiles } = await supa
      .from('profiles')
      .select('id, fcm_token')
      .in('id', driverIds)
      .not('fcm_token', 'is', null);

    // 5. Enviar push
    let sentCount = 0;
    const fareStr = ride.fare ? `R$ ${Number(ride.fare).toFixed(2).replace('.', ',')}` : '';
    const bodyText = `${fareStr ? `Ganho: ${fareStr}` : 'Nova corrida disponível!'}\nDestino: ${ride.dropoff_address || 'Destino informado no app'}`;

    for (const profile of profiles || []) {
      if (profile.fcm_token) {
        try {
          const pushResult = await sendPush({
            token: profile.fcm_token,
            title: '🚀 Nova Viagem Uppi',
            body: bodyText,
            data: {
              type: 'new_ride_request',
              ride_id: id,
            },
            channelId: 'orders',
          });
          if (pushResult.success) {
            sentCount++;
          }
          if (pushResult.invalidToken) {
            await cleanFcmToken(profile.id, profile.fcm_token);
          }
        } catch (pushErr) {
          console.error(`Falha push para ${profile.id}:`, pushErr);
        }
      }
    }

    console.log(`Notificou ${sentCount}/${nearbyDrivers.length} motoristas para corrida ${id}`);

    return jsonResponse({
      success: true,
      nearbyDrivers: nearbyDrivers.length,
      notified: sentCount,
    }, 200, req);

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('notify-nearby-drivers error:', msg);
    return errorResponse(msg, 500, req);
  }
});
