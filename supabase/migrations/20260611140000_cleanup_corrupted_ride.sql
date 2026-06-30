-- Clean up/Zero out the corrupted test ride from 29/05 (8,333 km distance, R$ 25,005.35 fare)
-- and update the corresponding driver stats.

-- 1. Zero out the ride values
UPDATE public.rides
SET distance = 0,
    distance_meters = 0,
    actual_distance = 0,
    fare = 0,
    driver_share = 0,
    fee = 0
WHERE (distance > 8000000 OR distance_meters > 8000000 OR actual_distance > 8000000 OR fare > 25000)
  AND created_at >= '2026-05-29 00:00:00+00'::timestamptz
  AND created_at < '2026-05-30 00:00:00+00'::timestamptz;

-- 2. Zero out the driver earnings associated with the corrupted ride
UPDATE public.driver_earnings
SET amount = 0,
    gross_amount = 0,
    commission_pct = 0,
    commission_amt = 0,
    platform_commission = 0,
    net_amount = 0,
    tip_amount = 0,
    driver_amount = 0
WHERE ride_id IN (
    SELECT id FROM public.rides
    WHERE (distance = 0 AND fare = 0)
      AND created_at >= '2026-05-29 00:00:00+00'::timestamptz
      AND created_at < '2026-05-30 00:00:00+00'::timestamptz
);

-- 3. Zero out the wallet transactions associated with the corrupted ride
UPDATE public.wallet_transactions
SET amount = 0
WHERE ride_id IN (
    SELECT id FROM public.rides
    WHERE (distance = 0 AND fare = 0)
      AND created_at >= '2026-05-29 00:00:00+00'::timestamptz
      AND created_at < '2026-05-30 00:00:00+00'::timestamptz
);

-- 4. Re-calculate driver stats for all drivers to normalize totals
UPDATE public.profiles_raw p
SET total_rides    = agg.cnt,
    total_distance = agg.dist
FROM (
  SELECT driver_id,
         COUNT(*) AS cnt,
         COALESCE(SUM(
           CASE
             WHEN COALESCE(actual_distance, distance_meters, distance, 0) > 200000 THEN 0
             ELSE COALESCE(actual_distance, distance_meters, distance, 0)
           END
         ), 0)::integer AS dist
  FROM public.rides
  WHERE status IN ('completed', 'finished', 'waiting_for_review')
    AND driver_id IS NOT NULL
  GROUP BY driver_id
) agg
WHERE p.id = agg.driver_id;
