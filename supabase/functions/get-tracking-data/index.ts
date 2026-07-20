/**
 * GET-TRACKING-DATA — Rastreamento de viagens em tempo real para a Web (Fase 17)
 */

import { getServiceClient } from '../_shared/supabase-client.ts';
import { jsonResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  // Trata requisições OPTIONS de CORS
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    if (req.method !== 'POST') {
      return jsonResponse({ error: 'method-not-allowed' }, { status: 405 });
    }

    const { trackingToken } = await req.json();

    if (!trackingToken) {
      return jsonResponse({ error: 'missing-token' }, { status: 400 });
    }

    const supa = getServiceClient();

    // 1. Busca o compartilhamento correspondente ao token
    const { data: share, error: shareError } = await supa
      .from('ride_tracking_shares')
      .select('ride_id, expires_at')
      .eq('share_token', trackingToken)
      .maybeSingle();

    if (shareError || !share) {
      return jsonResponse({ error: 'not-found', message: 'Token de rastreamento inválido' }, { status: 404 });
    }

    // 2. Verifica se o token expirou
    const expiresAt = new Date(share.expires_at).getTime();
    const now = Date.now();
    if (expiresAt < now) {
      return jsonResponse({ error: 'deadline-exceeded', message: 'Este link de rastreamento expirou' }, { status: 410 });
    }

    // 3. Busca a corrida
    const { data: ride, error: rideError } = await supa
      .from('rides')
      .select('id, pickup_address, dropoff_address, status, driver_id')
      .eq('id', share.ride_id)
      .maybeSingle();

    if (rideError || !ride) {
      return jsonResponse({ error: 'ride-not-found', message: 'Corrida não encontrada' }, { status: 404 });
    }

    const status = ride.status;
    const isActive = status !== 'completed' && status !== 'canceled';

    // Monta o payload inicial
    const responsePayload: any = {
      pickupAddress: ride.pickup_address,
      destinationAddress: ride.dropoff_address,
      status: status,
      isActive: isActive,
    };

    // 4. Se tiver motorista vinculado, busca dados do perfil e localização live
    if (ride.driver_id) {
      const { data: driverProfile } = await supa
        .from('profiles')
        .select('full_name, vehicle_details')
        .eq('id', ride.driver_id)
        .maybeSingle();

      if (driverProfile) {
        // Nome do motorista (primeiro nome)
        const firstName = driverProfile.full_name.split(' ')[0] || 'Motorista';
        responsePayload.driverFirstName = firstName;

        // Info do veículo
        const vDetails = driverProfile.vehicle_details;
        if (vDetails) {
          responsePayload.driverCarInfo = {
            color: vDetails.color || vDetails.vehicle_color || '',
            model: vDetails.model || vDetails.vehicle_model || '',
            plate: vDetails.plate || vDetails.vehicle_plate || vDetails.vehicle_plate_number || '',
          };
        }
      }

      // Busca localização tempo real do motorista
      const { data: driverLoc } = await supa
        .from('driver_locations')
        .select('lat, lng')
        .eq('driver_id', ride.driver_id)
        .maybeSingle();

      if (driverLoc) {
        responsePayload.driverLocation = {
          lat: driverLoc.lat,
          lng: driverLoc.lng,
        };
      }
    }

    return jsonResponse(responsePayload);

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('get-tracking-data error:', msg);
    return jsonResponse({ error: 'internal-server-error', message: msg }, { status: 500 });
  }
});
