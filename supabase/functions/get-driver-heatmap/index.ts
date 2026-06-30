/**
 * GET-DRIVER-HEATMAP — Retorna zonas quentes (hotspots) baseado em corridas recentes
 * Calcula ratio pedidos/motoristas por zona geográfica (~1km²)
 */

import { getServiceClient, getSupabaseUser, verifyAdmin } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);

    const supa = getServiceClient();

    // 🛡️ Segurança (Crítico 6): Restringir acesso apenas a motoristas ou admins
    const { data: profile } = await supa
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .single();

    const isAdmin = await verifyAdmin(req).then(() => true).catch(() => false);
    if ((!profile || profile.role !== 'driver') && !isAdmin) {
      return errorResponse('Acesso negado — apenas motoristas ou administradores podem acessar o heatmap', 403);
    }

    const body = await req.json();
    const { lat, lng } = body.args ?? body;

    if (!lat || !lng) return errorResponse('lat e lng são obrigatórios', 400);

    // Buscar corridas ativas próximas (últimos 30 minutos)
    const thirtyMinAgo = new Date(Date.now() - 30 * 60 * 1000).toISOString();

    const { data: activeRides } = await supa
      .from('rides')
      .select('pickup_lat, pickup_lng, status')
      .in('status', ['requested', 'accepted'])
      .gte('created_at', thirtyMinAgo);

    // Buscar motoristas online na região
    const { data: onlineDrivers } = await supa
      .from('driver_locations')
      .select('lat, lng')
      .eq('status', 'online');

    // Agrupar pedidos por zona (~1.1km² corrigindo distorção de latitude - Item 15)
    const zoneMap = new Map<string, { lat: number; lng: number; orders: number; drivers: number }>();

    // Função para calcular chave de zona normalizada (Item 15)
    const getNormalizedZoneKey = (latitude: number, longitude: number): string => {
      const latIndex = Math.round(latitude / 0.01);
      const latRad = (latitude * Math.PI) / 180;
      const cosLat = Math.max(0.1, Math.cos(latRad));
      const lngStep = 0.01 / cosLat;
      const lngIndex = Math.round(longitude / lngStep);
      return `${latIndex}_${lngIndex}`;
    };

    for (const ride of activeRides || []) {
      if (!ride.pickup_lat || !ride.pickup_lng) continue;
      const zoneKey = getNormalizedZoneKey(ride.pickup_lat, ride.pickup_lng);
      if (!zoneMap.has(zoneKey)) {
        zoneMap.set(zoneKey, {
          lat: ride.pickup_lat,
          lng: ride.pickup_lng,
          orders: 0,
          drivers: 0,
        });
      }
      zoneMap.get(zoneKey)!.orders++;
    }

    // Contar motoristas por zona
    for (const driver of onlineDrivers || []) {
      if (!driver.lat || !driver.lng) continue;
      const zoneKey = getNormalizedZoneKey(driver.lat, driver.lng);
      if (zoneMap.has(zoneKey)) {
        zoneMap.get(zoneKey)!.drivers++;
      }
    }

    // Calcular intensidade e multiplicador
    const hotspots = Array.from(zoneMap.entries())
      .filter(([_, z]) => z.orders > 0)
      .map(([key, z]) => {
        const ratio = z.drivers > 0 ? z.orders / z.drivers : z.orders * 2;
        let intensity = 'low';
        let multiplier = 1.0;

        if (ratio >= 4) {
          intensity = 'extreme';
          multiplier = 2.5;
        } else if (ratio >= 2.5) {
          intensity = 'high';
          multiplier = 1.8;
        } else if (ratio >= 1.5) {
          intensity = 'medium';
          multiplier = 1.3;
        }

        return {
          zone: key,
          lat: z.lat,
          lng: z.lng,
          openOrders: z.orders,
          availableDrivers: z.drivers,
          multiplier,
          intensity,
        };
      })
      .filter((z) => z.multiplier > 1.0)
      .sort((a, b) => b.multiplier - a.multiplier)
      .slice(0, 10);

    return jsonResponse({ hotspots });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('get-driver-heatmap error:', msg);
    return errorResponse(msg);
  }
});
