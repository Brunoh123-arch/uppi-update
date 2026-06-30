import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

const surgeCache = new Map<string, { multiplier: number; ts: number }>();
const CACHE_TTL_MS = 30_000; // 30 segundos de TTL cache

function getCacheKey(lat: number, lng: number): string {
  // Arredonda para ~100m de precisão
  return `${Math.round(lat * 1000) / 1000},${Math.round(lng * 1000) / 1000}`;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse(req);

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401, req);

    const body = await req.json().catch(() => ({}));
    const { lat, lng } = body.args ?? body;

    // 1. Verificar Cache
    if (lat !== undefined && lng !== undefined) {
      const cacheKey = getCacheKey(Number(lat), Number(lng));
      const cached = surgeCache.get(cacheKey);
      if (cached && Date.now() - cached.ts < CACHE_TTL_MS) {
        return jsonResponse({
          multiplier: cached.multiplier,
          surge_active: cached.multiplier > 1.0,
          from_cache: true,
        }, 200, req);
      }
    }

    const supa = getServiceClient();

    // 2. Verificar configurações globais de surge
    const { data: surgeRows } = await supa
      .from('app_settings')
      .select('key, value')
      .in('key', ['surge_enabled', 'surge_max_multiplier', 'global_surge_multiplier']);

    const surgeSettings: Record<string, string> = {};
    surgeRows?.forEach((row: any) => {
      surgeSettings[row.key] = row.value;
    });

    if (surgeSettings['surge_enabled'] === 'false') {
      return jsonResponse({ multiplier: 1.0, surge_active: false, reason: 'surge desabilitado' }, 200, req);
    }

    const globalMultiplier = Number(surgeSettings['global_surge_multiplier']);
    if (globalMultiplier && globalMultiplier > 1.0) {
      return jsonResponse({ multiplier: globalMultiplier, surge_active: true, reason: 'surge global ativo' }, 200, req);
    }

    let zoneMultiplier = 1.0;

    // 3. Verificar se a localização está dentro de alguma cerca virtual (surge_zones) usando PostGIS
    if (lat !== undefined && lng !== undefined) {
      const { data: matchedZones, error: zoneError } = await supa.rpc('get_matching_surge_zone', {
        p_lat: Number(lat),
        p_lng: Number(lng),
      });

      if (!zoneError && matchedZones && matchedZones.length > 0) {
        zoneMultiplier = Number(matchedZones[0].multiplier) || 1.0;
      }
    }

    // 4. Calcular ratio demanda/oferta global
    const { count: activeRides } = await supa
      .from('rides')
      .select('id', { count: 'exact', head: true })
      .in('status', ['requested', 'driver_accepted', 'arrived', 'started', 'in_progress']);

    const { count: onlineDrivers } = await supa
      .from('driver_locations')
      .select('driver_id', { count: 'exact', head: true })
      .eq('status', 'online');

    const rides = activeRides || 0;
    const drivers = onlineDrivers || 1; // Evita divisão por zero
    const ratio = rides / drivers;

    // 5. Verificar horário de pico (horário de Brasília)
    const formatter = new Intl.DateTimeFormat('pt-BR', {
      timeZone: 'America/Sao_Paulo',
      hour: 'numeric',
      hour12: false
    });
    const hour = Number(formatter.format(new Date()));
    const isPeakHour =
      (hour >= 7 && hour <= 9) ||   // Manhã
      (hour >= 17 && hour <= 19) ||  // Tarde
      (hour >= 22 && hour <= 23);    // Noite

    // 6. Calcular multiplicador baseado em demanda
    let demandMultiplier = 1.0;
    if (ratio > 3) demandMultiplier = 2.0;
    else if (ratio > 2) demandMultiplier = 1.7;
    else if (ratio > 1.5) demandMultiplier = 1.5;
    else if (ratio > 1) demandMultiplier = 1.3;

    // Bônus hora pico (+10%)
    if (isPeakHour && demandMultiplier > 1.0) {
      demandMultiplier = Math.round((demandMultiplier * 1.1) * 10) / 10;
    }

    // Escolhe o maior multiplicador entre cerca virtual e cálculo de demanda
    let multiplier = Math.max(zoneMultiplier, demandMultiplier);

    // Limitar pelo máximo configurado
    const maxMultiplier = Number(surgeSettings['surge_max_multiplier']) || 2.5;
    multiplier = Math.min(multiplier, maxMultiplier);
    multiplier = Math.round(multiplier * 100) / 100;

    // Salvar no Cache
    if (lat !== undefined && lng !== undefined) {
      const cacheKey = getCacheKey(Number(lat), Number(lng));
      surgeCache.set(cacheKey, { multiplier, ts: Date.now() });
    }

    return jsonResponse({
      multiplier,
      surge_active: multiplier > 1.0,
      demand_ratio: Math.round(ratio * 100) / 100,
      is_peak_hour: isPeakHour,
      zone_multiplier: zoneMultiplier,
      demand_multiplier: demandMultiplier,
    }, 200, req);

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('calculate-surge error:', msg);
    return errorResponse(msg, 500, req);
  }
});
