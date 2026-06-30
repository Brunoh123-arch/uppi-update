import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

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
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401, req);

    const body = await req.json().catch(() => ({}));
    const { ride_id, pickup_lat, pickup_lng, radius_km = 5 } = body.args ?? body;

    if (!ride_id || pickup_lat === undefined || pickup_lng === undefined) {
      return errorResponse('ride_id, pickup_lat, pickup_lng são obrigatórios', 400, req);
    }

    const supa = getServiceClient();

    // 1. Chamar a RPC get_nearby_drivers_scored do PostGIS para achar motoristas ordenados por score
    const { data: nearbyDrivers, error: rpcError } = await supa.rpc('get_nearby_drivers_scored', {
      p_lat: Number(pickup_lat),
      p_lng: Number(pickup_lng),
      p_radius_km: Number(radius_km),
    });

    if (rpcError) {
      console.warn('Matching Engine: get_nearby_drivers_scored RPC failed, falling back.', rpcError.message);
      
      // Obter categoria da corrida
      let category = 'carro';
      try {
        const { data: ride } = await supa
          .from('rides')
          .select('service_type')
          .eq('id', ride_id)
          .maybeSingle();
        if (ride?.service_type) {
          category = ride.service_type;
        }
      } catch (e) {
        console.error('Failed to get ride service_type in fallback:', e);
      }

      // Fallback: Busca simples de motoristas online na mesma categoria com filtro de proximidade e ordenação
      const { data: fallbackDrivers } = await supa
        .from('driver_locations')
        .select('driver_id, lat, lng, status, updated_at')
        .eq('status', 'online')
        .eq('vehicle_type', category);

      let filteredDrivers = (fallbackDrivers || []).map(d => {
        const dist = haversineDistance(
          Number(pickup_lat),
          Number(pickup_lng),
          Number(d.lat),
          Number(d.lng)
        ) / 1000; // converter para km
        return {
          driver_id: d.driver_id,
          distance_km: dist,
          lat: d.lat,
          lng: d.lng,
          status: d.status,
          updated_at: d.updated_at
        };
      }).filter(d => d.distance_km <= Number(radius_km));

      // Ordenar por distância
      filteredDrivers.sort((a, b) => a.distance_km - b.distance_km);

      // Limitar a 10
      filteredDrivers = filteredDrivers.slice(0, 10);

      return jsonResponse({
        matched: filteredDrivers.length > 0,
        drivers: filteredDrivers,
        algorithm: 'fallback_proximity',
      }, 200, req);
    }

    const best = nearbyDrivers?.[0];

    if (!best) {
      return jsonResponse({
        matched: false,
        message: 'Nenhum motorista disponível na área informada.',
      }, 200, req);
    }

    return jsonResponse({
      matched: true,
      best_driver_id: best.driver_id,
      distance_km: best.distance_km,
      score: best.score,
      algorithm: 'scored_proximity',
      all_candidates: nearbyDrivers?.slice(0, 5) || [],
    }, 200, req);

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('matching-engine error:', msg);
    return errorResponse(msg, 500, req);
  }
});
