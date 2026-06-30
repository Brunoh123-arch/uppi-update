/**
 * SEARCH-NEXT-RIDE
 * Busca uma próxima corrida (ride chaining) próxima ao local atual do motorista
 * ou próximo ao destino da corrida atual.
 */

import { getServiceClient, verifyDriver } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    // 🛡️ Segurança: Validar token JWT e garantir que o chamador é um motorista
    let driverUid: string;
    try {
      driverUid = await verifyDriver(req);
    } catch (err: any) {
      const isNotDriver = err.message.includes('requer conta de motorista');
      const msg = isNotDriver ? 'Acesso negado - conta de passageiro' : err.message;
      return errorResponse(msg, err.message.includes('Não autenticado') ? 401 : 403);
    }

    const body = await req.json();
    const data = body.data ?? body;
    const { currentOrderId, currentLat, currentLng } = data;

    if (!currentLat || !currentLng) {
      return jsonResponse({ result: { found: false } });
    }

    const supa = getServiceClient();

    let searchRadius = 3000;
    const { data: radiusRow } = await supa
      .from('app_settings')
      .select('value')
      .eq('key', 'driver_search_radius')
      .maybeSingle();
      
    if (radiusRow?.value) {
      searchRadius = Number(radiusRow.value) * 1000;
    }

    // Busca corridas 'requested' no raio definido
    const { data: rides, error } = await supa.rpc('find_nearby_requested_rides', {
      lat: currentLat,
      lng: currentLng,
      radius_meters: searchRadius
    });

    if (error) {
      console.error('Erro na busca de próxima corrida:', error);
      return jsonResponse({ result: { found: false } });
    }

    // Filtra pra não retornar a corrida atual (caso aconteça algum bug)
    const validRides = (rides || []).filter((r: any) => r.id !== currentOrderId);

    if (validRides.length > 0) {
      const bestRide = validRides[0]; // pega a mais próxima

      // 🛡️ [Item D13] Registrar oferta para a corrida encadeada para que ela passe pelo fluxo seguro de aceite
      const expiresAt = new Date(Date.now() + 15 * 1000).toISOString();
      const { error: offerError } = await supa
        .from('ride_offers')
        .insert({
          ride_id: bestRide.id,
          driver_id: driverUid,
          status: 'offered',
          expires_at: expiresAt,
        });

      if (offerError) {
        console.error('Erro ao criar oferta para corrida encadeada:', offerError);
        return jsonResponse({ result: { found: false } });
      }

      return jsonResponse({
        result: {
          found: true,
          nextOrderId: bestRide.id,
          pickupAddress: bestRide.pickup_address,
          destinationAddress: bestRide.dropoff_address,
          distanceToPickup: Math.round(bestRide.dist_meters || 0),
          estimatedFare: Number(bestRide.fare || 0),
        }
      });
    }

    return jsonResponse({ result: { found: false } });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('search-next-ride error:', msg);
    return jsonResponse({ result: { found: false } });
  }
});
