/**
 * UPDATE-RIDE-DESTINATION — Alterar destino de corrida em andamento
 * Permite que o passageiro mude o destino durante corrida 'in_progress' ou 'arrived'.
 * Recalcula tarifa baseada na nova distância e notifica o motorista via FCM.
 */

import { getServiceClient, getSupabaseUser, cleanFcmToken } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm-client.ts';

/** Calcula distância entre dois pontos em metros (Haversine) */
function haversineDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371000.0;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);
    const uid = user.id;

    const body = await req.json();
    const args = body.args ?? body;

    const { ride_id, new_dropoff_address, new_dropoff_lat, new_dropoff_lng } = args;

    if (!ride_id || !new_dropoff_address || new_dropoff_lat == null || new_dropoff_lng == null) {
      return errorResponse('ride_id, new_dropoff_address, new_dropoff_lat e new_dropoff_lng são obrigatórios', 400);
    }

    const supa = getServiceClient();

    // 1. Buscar corrida e validar ownership + status
    const { data: ride, error: rideErr } = await supa
      .from('rides')
      .select('id, rider_id, driver_id, status, service_type, pickup_lat, pickup_lng, fare, distance, duration')
      .eq('id', ride_id)
      .single();

    if (rideErr || !ride) {
      return errorResponse('Corrida não encontrada', 404);
    }

    if (ride.rider_id !== uid) {
      return errorResponse('Você não é o passageiro desta corrida', 403);
    }

    if (!['in_progress', 'arrived', 'started'].includes(ride.status)) {
      return errorResponse(`Não é possível alterar o destino com status '${ride.status}'. Apenas corridas em andamento.`, 400);
    }

    // 2. Buscar tarifa do serviço
    const { data: service, error: svcErr } = await supa
      .from('services')
      .select('base_fare, per_km_fare, per_minute_fare, minimum_fare')
      .eq('id', ride.service_type)
      .single();

    if (svcErr || !service) {
      return errorResponse('Serviço não encontrado para recálculo de tarifa', 500);
    }

    // 3. Calcular nova distância e duração
    const newDistanceMeters = haversineDistance(
      ride.pickup_lat, ride.pickup_lng,
      Number(new_dropoff_lat), Number(new_dropoff_lng)
    );
    const newDistanceKm = newDistanceMeters / 1000;
    // Estimativa: velocidade média urbana ~30km/h → 8.33 m/s
    const newDurationSeconds = Math.round(newDistanceMeters / 8.33);
    const newDurationMinutes = newDurationSeconds / 60;

    // 4. Recalcular tarifa
    const baseFare = Number(service.base_fare) || 0;
    const perKmFare = Number(service.per_km_fare) || 0;
    const perMinFare = Number(service.per_minute_fare) || 0;
    const minimumFare = Number(service.minimum_fare) || 0;

    let newFare = baseFare + (perKmFare * newDistanceKm) + (perMinFare * newDurationMinutes);
    newFare = Math.max(newFare, minimumFare);
    newFare = Math.round(newFare * 100) / 100; // arredondar centavos

    const originalFare = Number(ride.fare);

    // 5. Atualizar corrida
    const { error: updateErr } = await supa
      .from('rides')
      .update({
        dropoff_address: new_dropoff_address,
        dropoff_lat: Number(new_dropoff_lat),
        dropoff_lng: Number(new_dropoff_lng),
        distance: Math.round(newDistanceMeters),
        duration: newDurationSeconds,
        fare: newFare,
        original_fare: originalFare,
      })
      .eq('id', ride_id);

    if (updateErr) {
      console.error('[update-ride-destination] Erro ao atualizar corrida:', updateErr);
      return errorResponse('Erro ao atualizar destino da corrida', 500);
    }

    // 6. Notificar motorista via FCM
    if (ride.driver_id) {
      const { data: driverProfile } = await supa
        .from('profiles')
        .select('fcm_token')
        .eq('id', ride.driver_id)
        .single();

      if (driverProfile?.fcm_token) {
        const fareChange = newFare > originalFare ? '📈' : newFare < originalFare ? '📉' : '';
        const pushResult = await sendPush({
          token: driverProfile.fcm_token,
          title: '📍 Destino alterado pelo passageiro',
          body: `Novo destino: ${new_dropoff_address}. ${fareChange} Novo valor: R$ ${newFare.toFixed(2).replace('.', ',')}`,
          data: {
            ride_id,
            type: 'destination_changed',
            new_dropoff_lat: String(new_dropoff_lat),
            new_dropoff_lng: String(new_dropoff_lng),
            new_fare: String(newFare),
          },
          channelId: 'tripEvents',
        });

        if (pushResult.invalidToken) {
          await cleanFcmToken(ride.driver_id, driverProfile.fcm_token);
        }
      }
    }

    console.log(`[update-ride-destination] Corrida ${ride_id}: destino alterado. Fare: R$${originalFare} → R$${newFare}`);

    return jsonResponse({
      success: true,
      ride_id,
      new_dropoff_address,
      new_dropoff_lat: Number(new_dropoff_lat),
      new_dropoff_lng: Number(new_dropoff_lng),
      original_fare: originalFare,
      new_fare: newFare,
      new_distance_meters: Math.round(newDistanceMeters),
      new_duration_seconds: newDurationSeconds,
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('update-ride-destination error:', msg);
    return errorResponse(msg);
  }
});
