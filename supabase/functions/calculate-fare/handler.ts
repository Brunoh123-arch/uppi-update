/**
 * CALCULATE-FARE Handler — Calcula o preço de uma corrida
 * Migrado de: index.ts
 */

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { haversineDistance } from '../_shared/types.ts';
import { computeFare } from '../_shared/pricing.ts';

export async function handleCalculateFare(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return optionsResponse(req);

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401, req);

    const body = await req.json();
    const { waypoints: rawWaypoints, serviceId, distance_meters, duration_seconds, optimizeRoute, tip_incentive = 0 } = body.args ?? body;

    if (!rawWaypoints || rawWaypoints.length < 2) {
      return errorResponse('Waypoints inválidos: necessário origem e destino', 400, req);
    }

    // ===== Otimização de rota (TSP) — PILAR 15 =====
    let waypoints = rawWaypoints;
    let routeOptimized = false;
    let preOptimizationDistanceMeters = 0;

    if (optimizeRoute === true && rawWaypoints.length >= 3) {
      // Calcular distância original antes de otimizar
      for (let i = 0; i < rawWaypoints.length - 1; i++) {
        preOptimizationDistanceMeters += haversineDistance(
          rawWaypoints[i].coordinates.lat, rawWaypoints[i].coordinates.lng,
          rawWaypoints[i + 1].coordinates.lat, rawWaypoints[i + 1].coordinates.lng,
        );
      }

      const origin = rawWaypoints[0];
      const destination = rawWaypoints[rawWaypoints.length - 1];
      const intermediaries = rawWaypoints.slice(1, -1);

      if (intermediaries.length > 1) {
        // Inline TSP: escolher algoritmo com base na quantidade de intermediários
        if (intermediaries.length <= 8) {
          // Brute-force exato (todas as permutações)
          let bestOrder = [...intermediaries];
          let bestDistance = Infinity;

          const calcRouteDist = (route: typeof rawWaypoints) => {
            let d = 0;
            for (let i = 0; i < route.length - 1; i++) {
              d += haversineDistance(
                route[i].coordinates.lat, route[i].coordinates.lng,
                route[i + 1].coordinates.lat, route[i + 1].coordinates.lng,
              );
            }
            return d;
          };

          const permute = (arr: typeof intermediaries, l: number) => {
            if (l === arr.length - 1) {
              const route = [origin, ...arr, destination];
              const dist = calcRouteDist(route);
              if (dist < bestDistance) {
                bestDistance = dist;
                bestOrder = [...arr];
              }
              return;
            }
            for (let i = l; i < arr.length; i++) {
              [arr[l], arr[i]] = [arr[i], arr[l]];
              permute(arr, l + 1);
              [arr[l], arr[i]] = [arr[i], arr[l]];
            }
          };

          permute([...intermediaries], 0);
          waypoints = [origin, ...bestOrder, destination];
        } else {
          // Nearest-neighbor heuristic (O(n²))
          const remaining = [...intermediaries];
          const ordered: typeof intermediaries = [];
          let current = origin;

          while (remaining.length > 0) {
            let bestIdx = 0;
            let bestDist = Infinity;
            for (let j = 0; j < remaining.length; j++) {
              const d = haversineDistance(
                current.coordinates.lat, current.coordinates.lng,
                remaining[j].coordinates.lat, remaining[j].coordinates.lng,
              );
              if (d < bestDist) {
                bestDist = d;
                bestIdx = j;
              }
            }
            current = remaining[bestIdx];
            ordered.push(current);
            remaining.splice(bestIdx, 1);
          }

          waypoints = [origin, ...ordered, destination];
        }

        routeOptimized = true;
      }
    }

    const supa = getServiceClient();

    // 2. Buscar configurações (moeda, multiplicador de surto global e chave do Google Maps)
    let baseFare = 5.0, perKmRate = 2.0, perMinuteRate = 0.5, minimumFare = 7.0;
    let surgeMultiplier = 1.0;
    let appCurrency = 'BRL';
    let googleApiKey = '';
    let cashEnabled = true;
    let walletEnabled = true;

    const { data: settingsRows } = await supa
      .from('app_settings')
      .select('key, value')
      .in('key', ['global_surge_multiplier', 'currency', 'google_map_api_key', 'cash_enabled', 'wallet_enabled']);

    settingsRows?.forEach((row: any) => {
      if (row.key === 'global_surge_multiplier' && row.value) surgeMultiplier = Number(row.value);
      if (row.key === 'currency' && row.value) appCurrency = row.value;
      if (row.key === 'google_map_api_key' && row.value) googleApiKey = row.value;
      if (row.key === 'cash_enabled') cashEnabled = row.value !== 'false';
      if (row.key === 'wallet_enabled') walletEnabled = row.value !== 'false';
    });

    if (!googleApiKey) {
      const { data: globalConfigRow } = await supa
        .from('app_settings')
        .select('google_map_api_key')
        .eq('key', 'global_config')
        .maybeSingle();

      if (globalConfigRow && globalConfigRow.google_map_api_key) {
        googleApiKey = globalConfigRow.google_map_api_key.toString();
      }
    }

    // 1. Calcular distância total (usando os valores enviados pelo app se disponíveis, senão Google Directions, senão Haversine de fallback)
    let totalDistanceMeters = Number(distance_meters || 0);
    let durationSeconds = Number(duration_seconds || 0);

    if (totalDistanceMeters === 0 && googleApiKey && waypoints.length >= 2) {
      try {
        const origin = `${waypoints[0].coordinates.lat},${waypoints[0].coordinates.lng}`;
        const destination = `${waypoints[waypoints.length - 1].coordinates.lat},${waypoints[waypoints.length - 1].coordinates.lng}`;
        let url = `https://maps.googleapis.com/maps/api/directions/json?origin=${origin}&destination=${destination}&key=${googleApiKey}`;
        
        if (waypoints.length > 2) {
          const intermediates = waypoints.slice(1, -1).map((w: any) => `via:${w.coordinates.lat},${w.coordinates.lng}`).join('|');
          url += `&waypoints=${encodeURIComponent(intermediates)}`;
        }

        console.log(`[calculate-fare] Requesting Google Directions: ${url.replace(googleApiKey, 'HIDDEN')}`);
        const response = await fetch(url);
        if (response.ok) {
          const directionsData = await response.json();
          if (directionsData.status === 'OK' && directionsData.routes && directionsData.routes.length > 0) {
            const route = directionsData.routes[0];
            let routeDistance = 0;
            let routeDuration = 0;
            for (const leg of route.legs) {
              routeDistance += leg.distance.value;
              routeDuration += leg.duration.value;
            }
            totalDistanceMeters = routeDistance;
            durationSeconds = routeDuration;
            console.log(`[calculate-fare] Google Directions success: dist=${totalDistanceMeters}m, dur=${durationSeconds}s`);
          } else {
            console.error(`[calculate-fare] Google Directions API error: status=${directionsData.status}, error_message=${directionsData.error_message}`);
          }
        } else {
          console.error(`[calculate-fare] Google Directions HTTP error: status=${response.status}`);
        }
      } catch (e) {
        console.error(`[calculate-fare] Exception during Google Directions call:`, e);
      }
    }

    if (totalDistanceMeters === 0) {
      console.log(`[calculate-fare] Using Haversine fallback`);
      for (let i = 0; i < waypoints.length - 1; i++) {
        totalDistanceMeters += haversineDistance(
          waypoints[i].coordinates.lat, waypoints[i].coordinates.lng,
          waypoints[i + 1].coordinates.lat, waypoints[i + 1].coordinates.lng,
        );
      }
      durationSeconds = Math.round((totalDistanceMeters / 1000 / 30) * 3600);
    }

    const distanceKm = totalDistanceMeters / 1000;
    const durationMinutes = durationSeconds / 60;

    let couponData: any = null;
    const code = body.args?.couponCode || body.couponCode;
    if (code) {
      const { data } = await supa.from('coupons')
        .select('*')
        .eq('code', code.toUpperCase())
        .eq('is_enabled', true)
        .limit(1);
      if (data && data.length > 0) {
         couponData = data[0];
      }
    }

    if (serviceId) {
      const { data: serviceRow } = await supa
        .from('services')
        .select('base_fare, per_km_fare, per_minute_fare, minimum_fare')
        .eq('id', serviceId)
        .maybeSingle();
      if (serviceRow) {
        baseFare = Number(serviceRow.base_fare ?? 5.0);
        perKmRate = Number(serviceRow.per_km_fare ?? 2.0);
        perMinuteRate = Number(serviceRow.per_minute_fare ?? 0.5);
        minimumFare = Number(serviceRow.minimum_fare ?? 7.0);
      }
      // ── Pilar 16: Desconto de assinatura do passageiro ──
      const { data: activeSub } = await supa
        .from('passenger_subscriptions')
        .select('discount_percent, is_active')
        .eq('user_id', user.id)
        .eq('is_active', true)
        .gt('expires_at', new Date().toISOString())
        .maybeSingle();

      const breakdown = computeFare({
        distanceKm,
        durationMinutes,
        rates: { baseFare, perKmRate, perMinuteRate, minimumFare },
        surgeMultiplier,
        coupon: couponData,
        subscriptionDiscountPercent: activeSub ? Number(activeSub.discount_percent ?? 0) : 0,
        tipIncentive: Number(tip_incentive),
      });

      return jsonResponse({
        fare: breakdown.fare,
        fareAfterCoupon: breakdown.fareAfterCoupon,
        subscriptionDiscount: breakdown.subscriptionDiscount,
        fareAfterSubscription: breakdown.fareAfterSubscription,
        tip_incentive: breakdown.tip_incentive,
        total_fare: breakdown.total_fare,
        distance_meters: Math.round(totalDistanceMeters),
        duration_seconds: durationSeconds,
        surge_multiplier: surgeMultiplier,
        currency: appCurrency,
        cash_enabled: cashEnabled,
        wallet_enabled: walletEnabled,
        ...(routeOptimized ? {
          routeOptimized: true,
          originalDistanceMeters: Math.round(preOptimizationDistanceMeters),
          optimizedWaypoints: waypoints,
        } : {}),
      }, 200, req);
    } else {
      // Calculate for ALL services
      const { data: services } = await supa.from('services').select('*');
      const calculatedServices = (services || []).map((srv: any) => {
        const b = computeFare({
          distanceKm,
          durationMinutes,
          rates: {
            baseFare: Number(srv.base_fare ?? 5.0),
            perKmRate: Number(srv.per_km_fare ?? 2.0),
            perMinuteRate: Number(srv.per_minute_fare ?? 0.5),
            minimumFare: Number(srv.minimum_fare ?? 7.0),
          },
          surgeMultiplier,
          coupon: couponData,
        });

        return {
          id: srv.id,
          name: srv.name ?? 'Regular',
          description: srv.description,
          image_url: srv.image_url,
          fare: b.fare,
          fareAfterCoupon: b.fareAfterCoupon,
        };
      });

      // ── Pilar 16: Desconto de assinatura do passageiro (multi-service) ──
      let subscriptionDiscount = 0;
      const { data: activeSub } = await supa
        .from('passenger_subscriptions')
        .select('discount_percent, is_active')
        .eq('user_id', user.id)
        .eq('is_active', true)
        .gt('expires_at', new Date().toISOString())
        .maybeSingle();

      if (activeSub) {
        subscriptionDiscount = Number(activeSub.discount_percent ?? 0);
      }

      const servicesWithSubscription = calculatedServices.map((srv: any) => {
        const fareAfterSubscription = subscriptionDiscount > 0
          ? parseFloat((srv.fareAfterCoupon * (1 - subscriptionDiscount / 100)).toFixed(2))
          : srv.fareAfterCoupon;
        const total_fare = parseFloat((fareAfterSubscription + Number(tip_incentive)).toFixed(2));
        return { ...srv, fareAfterSubscription, total_fare };
      });

      return jsonResponse({
        services: servicesWithSubscription,
        subscriptionDiscount,
        tip_incentive: Number(tip_incentive),
        distance_meters: Math.round(totalDistanceMeters),
        duration_seconds: durationSeconds,
        surge_multiplier: surgeMultiplier,
        currency: appCurrency,
        cash_enabled: cashEnabled,
        wallet_enabled: walletEnabled,
        ...(routeOptimized ? {
          routeOptimized: true,
          originalDistanceMeters: Math.round(preOptimizationDistanceMeters),
          optimizedWaypoints: waypoints,
        } : {}),
      }, 200, req);
    }

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('calculate-fare error:', msg);
    return errorResponse(msg, 500, req);
  }
}
