-- Função PostgreSQL para buscar motoristas próximos com score ponderado
-- Score = (1/distância * 40%) + (rating * 40%) + (disponibilidade * 20%)
CREATE OR REPLACE FUNCTION public.get_nearby_drivers_scored(
  p_lat FLOAT,
  p_lng FLOAT,
  p_radius_km FLOAT DEFAULT 5.0
)
RETURNS TABLE(
  driver_id UUID,
  distance_km FLOAT,
  lat FLOAT,
  lng FLOAT,
  rating FLOAT,
  score FLOAT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    dl.driver_id,
    ROUND(
      (ST_Distance(
        ST_SetSRID(ST_MakePoint(dl.lng, dl.lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
      ) / 1000.0)::NUMERIC, 2
    )::FLOAT AS distance_km,
    dl.lat::FLOAT,
    dl.lng::FLOAT,
    COALESCE(p.rating, 4.5)::FLOAT AS rating,
    -- Score ponderado: proximidade (40%) + rating (40%) + (bônus online contínuo 20%)
    (
      (1.0 / GREATEST(ST_Distance(
        ST_SetSRID(ST_MakePoint(dl.lng, dl.lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
      ) / 1000.0, 0.1)) * 0.4
      + COALESCE(p.rating, 4.5) / 5.0 * 0.4
      + 0.2
    )::FLOAT AS score
  FROM public.driver_locations dl
  LEFT JOIN public.profiles p ON p.id = dl.driver_id
  WHERE
    dl.status = 'online'
    AND ST_Distance(
      ST_SetSRID(ST_MakePoint(dl.lng, dl.lat), 4326)::geography,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    ) <= (p_radius_km * 1000)
  ORDER BY score DESC
  LIMIT 20;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION public.get_nearby_drivers_scored IS
  'Retorna motoristas online próximos ordenados por score ponderado (distância + rating)';
