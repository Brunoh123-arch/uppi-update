-- ==============================================================================
-- BLINDAGEM DE USABILIDADE DO MOTORISTA — ECOSSISTEMA UPPI
-- Tabela e RPC para evitar loop infinito de ofertas rejeitadas ou canceladas
-- ==============================================================================

-- 1. Criar tabela de controle de corridas rejeitadas por motorista
CREATE TABLE IF NOT EXISTS public.ride_rejected_drivers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id UUID NOT NULL REFERENCES public.rides(id) ON DELETE CASCADE,
    driver_id TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT unique_ride_driver_rejection UNIQUE (ride_id, driver_id)
);

-- Habilitar RLS na tabela de rejeições
ALTER TABLE public.ride_rejected_drivers ENABLE ROW LEVEL SECURITY;

-- Permitir que o próprio motorista autenticado insira suas rejeições
CREATE POLICY "Driver can insert own rejections" ON public.ride_rejected_drivers
    FOR INSERT TO authenticated
    WITH CHECK (driver_id = auth.uid()::text);

-- Permitir leitura das próprias rejeições
CREATE POLICY "Driver can read own rejections" ON public.ride_rejected_drivers
    FOR SELECT TO authenticated
    USING (driver_id = auth.uid()::text);

-- 2. RPC para registrar rejeição de corrida de forma simples
CREATE OR REPLACE FUNCTION public.reject_ride(
  p_ride_id UUID,
  p_driver_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.ride_rejected_drivers (ride_id, driver_id)
  VALUES (p_ride_id, p_driver_id)
  ON CONFLICT (ride_id, driver_id) DO NOTHING;
END;
$$;

-- Garantir acesso da RPC aos autenticados
GRANT EXECUTE ON FUNCTION public.reject_ride(UUID, TEXT) TO authenticated;

-- 3. Atualizar a RPC find_nearby_requested_rides para incluir o filtro de rejeições
CREATE OR REPLACE FUNCTION public.find_nearby_requested_rides(
    lat float8,
    lng float8,
    radius_meters float8 DEFAULT 3000
)
RETURNS TABLE (
    id UUID,
    pickup_address TEXT,
    dropoff_address TEXT,
    fare DECIMAL,
    dist_meters FLOAT8
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        r.id,
        r.pickup_address,
        r.dropoff_address,
        r.fare,
        ST_Distance(
            r.pickup_location,
            ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography
        ) AS dist_meters
    FROM public.rides r
    WHERE r.status = 'requested'
      AND r.driver_id IS NULL
      -- Evita receber corridas que este motorista já rejeitou ou cancelou
      AND r.id NOT IN (
          SELECT rr.ride_id 
          FROM public.ride_rejected_drivers rr 
          WHERE rr.driver_id = auth.uid()::text
      )
      AND ST_DWithin(
          r.pickup_location,
          ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography,
          radius_meters
      )
    ORDER BY dist_meters ASC
    LIMIT 1;
END;
$$;

COMMENT ON FUNCTION public.find_nearby_requested_rides(float8, float8, float8) IS 'Busca corridas próximas solicitadas ativas, filtrando as que o motorista já rejeitou anteriormente para evitar loops de tela.';
