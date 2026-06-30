-- Função PostgreSQL para buscar zonas de tarifas dinâmicas (surge_zones) que cobrem um determinado ponto
CREATE OR REPLACE FUNCTION public.get_matching_surge_zone(
  p_lat FLOAT,
  p_lng FLOAT
)
RETURNS TABLE(
  id UUID,
  name TEXT,
  multiplier NUMERIC(3,2)
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    sz.id,
    sz.name,
    sz.multiplier
  FROM public.surge_zones sz
  WHERE
    sz.is_active = true
    AND (sz.expires_at IS NULL OR sz.expires_at > NOW())
    -- ST_Contains requer geometry, convertendo de geography
    AND ST_Contains(
      sz.boundary::geometry,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geometry
    )
  ORDER BY sz.multiplier DESC
  LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_matching_surge_zone(FLOAT, FLOAT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_matching_surge_zone(FLOAT, FLOAT) TO service_role;
