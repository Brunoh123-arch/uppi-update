/**
 * GET-ORDER-HISTORY — Histórico de corridas do usuário
 * Migrado de: lógica distribuída em order.functions.ts
 */

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);
    const uid = user.id;

    const body = await req.json().catch(() => ({}));
    const { role, limit: limitParam, offset: offsetParam, status } = body.args ?? body;

    const maxLimit = Math.min(Number(limitParam) || 20, 50);
    const offset = Number(offsetParam) || 0;
    const userRole = role || 'rider';

    const supa = getServiceClient();

    const filterCol = userRole === 'driver' ? 'driver_id' : 'rider_id';

    let query = supa
      .from('rides')
      .select(`
        id, status, created_at, started_at, finished_at,
        pickup_address, dropoff_address,
        pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
        fare, distance, duration, tip_amount, payment_method,
        rider_id, driver_id, currency, platform_fee,
        cancel_reason_note, cancelled_by
      `)
      .eq(filterCol, uid)
      .order('created_at', { ascending: false })
      .range(offset, offset + maxLimit - 1);

    if (status) {
      query = query.eq('status', status);
    }

    const { data: rides, error: queryErr, count } = await query;
    if (queryErr) return errorResponse(queryErr.message, 500);

    // Enriquecer com nome do outro participante usando batch query para otimizar N+1
    const otherUserIds = (rides || [])
      .map(ride => userRole === 'driver' ? ride.rider_id : ride.driver_id)
      .filter((id): id is string => !!id);
    const uniqueOtherUserIds = [...new Set(otherUserIds)];

    const profilesMap = new Map<string, string>();
    if (uniqueOtherUserIds.length > 0) {
      const { data: profiles, error: profilesErr } = await supa
        .from('profiles')
        .select('id, full_name')
        .in('id', uniqueOtherUserIds);
      if (!profilesErr && profiles) {
        for (const p of profiles) {
          profilesMap.set(p.id, p.full_name || '');
        }
      }
    }

    const enrichedRides = (rides || []).map(ride => {
      const otherUserId = userRole === 'driver' ? ride.rider_id : ride.driver_id;
      const otherName = otherUserId ? (profilesMap.get(otherUserId) || '') : '';
      return {
        ...ride,
        other_user_name: otherName,
      };
    });

    return jsonResponse({
      rides: enrichedRides,
      total: count || enrichedRides.length,
      limit: maxLimit,
      offset,
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('get-order-history error:', msg);
    return errorResponse(msg);
  }
});
