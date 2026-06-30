/**
 * GET-LEADERBOARD — Ranking de motoristas
 * Migrado de: functions/src/gamification/ (leaderboard)
 */

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);

    const body = await req.json().catch(() => ({}));
    const { period, limit: limitParam } = body.args ?? body;
    const maxLimit = Math.min(Number(limitParam) || 20, 50);

    const supa = getServiceClient();

    // Período: weekly, monthly, alltime
    let sinceDate: string | null = null;
    const now = new Date();

    if (period === 'weekly') {
      const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
      sinceDate = weekAgo.toISOString();
    } else if (period === 'monthly') {
      const monthAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
      sinceDate = monthAgo.toISOString();
    }

    // Buscar motoristas com mais corridas finalizadas
    // 1. Buscar contagem de corridas por motorista
    let query = supa
      .from('rides')
      .select('driver_id')
      .in('status', ['finished', 'waiting_for_review'])
      .not('driver_id', 'is', null);

    if (sinceDate) {
      query = query.gte('created_at', sinceDate);
    }

    const { data: rides } = await query;

    if (!rides || rides.length === 0) {
      return jsonResponse({ leaderboard: [], period: period || 'alltime' });
    }

    // Contar corridas por driver
    const rideCounts: Record<string, number> = {};
    for (const ride of rides) {
      if (ride.driver_id) {
        rideCounts[ride.driver_id] = (rideCounts[ride.driver_id] || 0) + 1;
      }
    }

    // Ordenar por número de corridas
    const sorted = Object.entries(rideCounts)
      .sort(([, a], [, b]) => b - a)
      .slice(0, maxLimit);

    // Buscar perfis dos top motoristas
    const topDriverIds = sorted.map(([id]) => id);
    const { data: profiles } = await supa
      .from('profiles')
      // BUG FIX #10: field is 'average_rating', not 'rating'
      .select('id, full_name, average_rating, review_count')
      .in('id', topDriverIds);

    const profileMap: Record<string, { full_name: string; rating: number; review_count: number }> = {};
    for (const p of profiles || []) {
      profileMap[p.id] = p;
    }

    // Buscar badges count
    const { data: badgeCounts } = await supa
      .from('user_badges')
      .select('user_id')
      .in('user_id', topDriverIds);

    const badgeMap: Record<string, number> = {};
    for (const b of badgeCounts || []) {
      badgeMap[b.user_id] = (badgeMap[b.user_id] || 0) + 1;
    }

    // Posição do user atual
    let myPosition: number | null = null;
    const myRides = rideCounts[user.id];

    if (myRides) {
      const allSorted = Object.entries(rideCounts).sort(([, a], [, b]) => b - a);
      myPosition = allSorted.findIndex(([id]) => id === user.id) + 1;
    }

    // Montar leaderboard
    const leaderboard = sorted.map(([driverId, count], index) => ({
      position: index + 1,
      driver_id: driverId,
      name: profileMap[driverId]?.full_name || 'Motorista',
      completed_rides: count,
      rating: profileMap[driverId]?.average_rating || 0,
      badges: badgeMap[driverId] || 0,
    }));

    return jsonResponse({
      leaderboard,
      period: period || 'alltime',
      my_position: myPosition,
      my_rides: myRides || 0,
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('get-leaderboard error:', msg);
    return errorResponse(msg);
  }
});
