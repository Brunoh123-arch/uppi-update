/**
 * ADMIN-INSIGHTS — Dashboard de métricas e estatísticas
 * Migrado de: functions/src/admin/admin.functions.ts (getInsights + exportOrders)
 */

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);

    const supa = getServiceClient();

    // BUG FIX #14: admins ficam na tabela 'admins', não em profiles.role
    const { data: adminRecord } = await supa
      .from('admins')
      .select('role')
      .eq('id', user.id)
      .maybeSingle();

    if (!adminRecord) {
      return errorResponse('Acesso negado', 403);
    }

    const body = await req.json().catch(() => ({}));
    const { action, startDate, endDate, status: filterStatus } = body.args ?? body;

    // ── Export CSV ─────────────────────────────────────────────────────
    if (action === 'export') {
      const limit = Math.min(Number(body.limit) || 1000, 10000);
      const offset = Number(body.offset) || 0;

      let query = supa.from('rides')
        .select('id, status, created_at, rider_id, driver_id, distance_meters, fare, currency, cancel_reason_note, cancelled_by, canceled_at')
        .order('created_at', { ascending: false })
        .range(offset, offset + limit - 1);

      if (startDate) query = query.gte('created_at', startDate);
      if (endDate) query = query.lte('created_at', endDate);
      if (filterStatus) query = query.eq('status', filterStatus);

      const { data: rides } = await query;

      const header = 'ID,Status,Created At,Rider,Driver,Distance,Fare,Currency,Cancel Reason,Cancelled By,Canceled At\n';
      const rows = (rides || []).map((r) =>
        [
          r.id,
          r.status,
          r.created_at,
          r.rider_id,
          r.driver_id,
          r.distance_meters || 0,
          r.fare || 0,
          r.currency || 'BRL',
          r.cancel_reason_note || '',
          r.cancelled_by || '',
          r.canceled_at || ''
        ]
          .map((f) => `"${String(f).replace(/"/g, '""')}"`)
          .join(','),
      ).join('\n');

      return jsonResponse({ csv: header + rows, count: rides?.length || 0, limit, offset });
    }

    // ── Dashboard Insights ────────────────────────────────────────────
    const start = startDate ? new Date(startDate) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const end = endDate ? new Date(endDate) : new Date();

    // Corridas no período
    const { data: rides, count: totalOrders } = await supa
      .from('rides')
      .select('status, fare, platform_fee, coupon_discount', { count: 'exact' })
      .gte('created_at', start.toISOString())
      .lte('created_at', end.toISOString());

    const rideList = rides || [];
    const completedStatuses = ['finished', 'waiting_for_review', 'completed'];
    const completedRides = rideList.filter((r) => completedStatuses.includes(r.status));

    const completedOrders = completedRides.length;
    const canceledOrders = rideList.filter((r) => ['rider_canceled', 'driver_canceled', 'canceled'].includes(r.status)).length;

    // Gross Revenue = sum of base fares (before discount)
    const grossRevenue = completedRides.reduce((sum, r) => sum + (Number(r.fare) || 0), 0);

    // Total Discounts
    const totalDiscounts = completedRides.reduce((sum, r) => sum + (Number(r.coupon_discount) || 0), 0);

    // Net Fare Revenue (fares actually paid by riders)
    const netRevenue = grossRevenue - totalDiscounts;

    // Platform Commission (platform_fee)
    const totalCommission = completedRides.reduce((sum, r) => sum + (Number(r.platform_fee) || 0), 0);

    // Buscar taxas de cancelamento no período (Item 18)
    const { data: cancellations } = await supa
      .from('ride_cancellations')
      .select('cancellation_fee')
      .gte('created_at', start.toISOString())
      .lte('created_at', end.toISOString());

    const totalCancellationFees = (cancellations || []).reduce((sum, c) => sum + (Number(c.cancellation_fee) || 0), 0);

    // Contadores de usuários
    const { count: totalRiders } = await supa
      .from('profiles')
      .select('id', { count: 'exact', head: true })
      .eq('role', 'rider');

    const { count: totalDrivers } = await supa
      .from('profiles')
      .select('id', { count: 'exact', head: true })
      .eq('role', 'driver');

    // Motoristas online agora
    const { count: onlineDrivers } = await supa
      .from('driver_locations')
      .select('driver_id', { count: 'exact', head: true })
      .eq('status', 'online');

    // Corridas ativas agora
    const { count: activeRides } = await supa
      .from('rides')
      .select('id', { count: 'exact', head: true })
      .in('status', ['requested', 'driver_accepted', 'arrived', 'started', 'in_progress', 'accepted']);

    return jsonResponse({
      totalOrders: totalOrders || 0,
      completedOrders,
      canceledOrders,
      totalRevenue: Math.round(grossRevenue * 100) / 100, // gross transaction volume (totalRevenue for compatibility)
      grossRevenue: Math.round(grossRevenue * 100) / 100,
      totalDiscounts: Math.round(totalDiscounts * 100) / 100,
      netRevenue: Math.round(netRevenue * 100) / 100,
      totalCommission: Math.round(totalCommission * 100) / 100,
      totalCancellationFees: Math.round(totalCancellationFees * 100) / 100,
      totalRiders: totalRiders || 0,
      totalDrivers: totalDrivers || 0,
      onlineDrivers: onlineDrivers || 0,
      activeRides: activeRides || 0,
      completionRate: (totalOrders || 0) > 0
        ? Math.round((completedOrders / (totalOrders || 1)) * 100)
        : 0,
      period: { start: start.toISOString(), end: end.toISOString() },
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('admin-insights error:', msg);
    return errorResponse(msg);
  }
});
