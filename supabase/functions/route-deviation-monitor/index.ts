import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm-client.ts';

function haversineDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000; // raio da Terra em metros
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) *
      Math.cos(lat2 * Math.PI / 180) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function minDistanceToPolyline(
  lat: number,
  lng: number,
  polyline: Array<{ lat: number; lng: number }>
): number {
  let minDist = Infinity;
  for (const point of polyline) {
    const d = haversineDistance(lat, lng, point.lat, point.lng);
    if (d < minDist) minDist = d;
  }
  return minDist;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);

    const body = await req.json().catch(() => ({}));
    const { ride_id, current_lat, current_lng } = body.args ?? body;

    if (!ride_id || current_lat === undefined || current_lng === undefined) {
      return errorResponse('ride_id, current_lat e current_lng são obrigatórios', 400);
    }

    const supa = getServiceClient();

    // 1. Buscar a corrida e polilinha
    const { data: ride, error: rideError } = await supa
      .from('rides')
      .select('id, rider_id, driver_id, status, route_polyline, deviation_alert_sent')
      .eq('id', ride_id)
      .single();

    if (rideError || !ride) {
      return errorResponse('Corrida não encontrada', 404);
    }

    if (!['started', 'in_progress'].includes(ride.status)) {
      return jsonResponse({ deviation: false, message: 'Corrida não está em andamento.' });
    }

    // Se não há polilinha na corrida, não há como verificar desvio
    if (!ride.route_polyline || !Array.isArray(ride.route_polyline) || ride.route_polyline.length === 0) {
      return jsonResponse({ deviation: false, message: 'Nenhuma polilinha de rota disponível.' });
    }

    // 2. Calcular distância
    const deviationMeters = minDistanceToPolyline(
      Number(current_lat),
      Number(current_lng),
      ride.route_polyline as Array<{ lat: number; lng: number }>
    );

    const THRESHOLD_METERS = 300; // 300 metros de tolerância para alertas
    const isDeviated = deviationMeters > THRESHOLD_METERS;

    if (isDeviated && !ride.deviation_alert_sent) {
      // Marcar alerta como enviado para evitar múltiplos alertas em loop
      await supa
        .from('rides')
        .update({ deviation_alert_sent: true })
        .eq('id', ride_id);

      // Enviar push para o passageiro
      if (ride.rider_id) {
        const { data: riderProfile } = await supa
          .from('profiles')
          .select('fcm_token')
          .eq('id', ride.rider_id)
          .single();

        if (riderProfile?.fcm_token) {
          await sendPush({
            token: riderProfile.fcm_token,
            title: '⚠️ Verificação de Segurança (RideCheck)',
            body: 'Notamos que o veículo se desviou da rota planejada. Está tudo bem?',
            data: { type: 'route_deviation', ride_id: ride_id },
            channelId: 'safety',
          }).catch((err) => console.warn('Falha ao enviar push de desvio:', err));
        }
      }
    }

    return jsonResponse({
      deviation: isDeviated,
      deviation_meters: Math.round(deviationMeters),
      threshold_meters: THRESHOLD_METERS,
      alert_sent: isDeviated && !ride.deviation_alert_sent,
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('route-deviation-monitor error:', msg);
    return errorResponse(msg);
  }
});
