-- Ignora distâncias corrompidas (> 200 km por corrida, ex.: corrida de teste
-- de 29/05 com 8.333 km) no acumulador de totais do perfil do motorista.

CREATE OR REPLACE FUNCTION public.update_driver_ride_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_distance numeric;
BEGIN
  SELECT COALESCE(actual_distance, distance_meters, distance, 0)
  INTO v_distance
  FROM public.rides
  WHERE id = NEW.ride_id;

  -- Distância acima de 200 km numa corrida urbana é dado corrompido/teste.
  IF v_distance IS NULL OR v_distance > 200000 THEN
    v_distance := 0;
  END IF;

  UPDATE public.profiles_raw
  SET total_rides    = COALESCE(total_rides, 0) + 1,
      total_distance = COALESCE(total_distance, 0) + v_distance::integer
  WHERE id = NEW.driver_id;

  RETURN NEW;
END;
$$;

-- Re-executa o backfill com o mesmo filtro de sanidade
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
