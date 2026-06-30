/**
 * UPDATE-DRIVER-LOCATION Handler — Atualiza a localização do motorista
 * Migrado de: index.ts
 */

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { locationLimiter } from '../_shared/rate-limiter.ts';

export async function handleUpdateDriverLocation(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return optionsResponse(req);

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401, req);
    const uid = user.id;

    // --- 🛡️ RATE LIMITING ---
    if (locationLimiter.isRateLimited(uid)) {
      return errorResponse('Limite de frequência de atualização de GPS excedido.', 429, req);
    }

    const body = await req.json();
    const { lat, lng, heading, speed, vehicle_type, marker_url } = body.args ?? body;

    if (!lat || !lng) return errorResponse('lat e lng são obrigatórios', 400, req);

    const supa = getServiceClient();

    // Upsert na tabela driver_locations
    const payload: any = {
      driver_id: uid,
      lat: Number(lat),
      lng: Number(lng),
      heading: heading ? Number(heading) : 0,
      speed: speed ? Number(speed) : 0,
      location: `POINT(${Number(lng)} ${Number(lat)})`,
      updated_at: new Date().toISOString(),
    };

    if (vehicle_type) payload.vehicle_type = vehicle_type;
    if (marker_url) payload.marker_url = marker_url;

    const { error } = await supa
      .from('driver_locations')
      .upsert(payload, { onConflict: 'driver_id' });

    if (error) return errorResponse(error.message, 500, req);

    return jsonResponse({ success: true }, 200, req);

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('update-driver-location error:', msg);
    return errorResponse(msg, 500, req);
  }
}
