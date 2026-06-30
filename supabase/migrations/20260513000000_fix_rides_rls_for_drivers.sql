-- ==============================================================================
-- FIX CRÍTICO: Motoristas precisam VER corridas com status='requested'
-- para poderem aceitar corridas. A RLS anterior só permitia ver corridas
-- onde o motorista já era driver_id (que é NULL em corridas pendentes).
-- ==============================================================================

-- Adiciona policy que permite motoristas verem corridas 'requested'
-- para que o stream CDC e a consulta direta funcionem
DROP POLICY IF EXISTS "rides_select_requested_for_drivers" ON public.rides;

CREATE POLICY "rides_select_requested_for_drivers" ON public.rides
  FOR SELECT TO authenticated
  USING (
    -- Motoristas online podem ver corridas pendentes
    (
      status = 'requested'
      AND EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid()::text 
        AND role = 'driver'
      )
    )
    -- OU é participante da corrida (rider ou driver)
    OR auth.uid()::text = rider_id
    OR auth.uid()::text = driver_id
    -- OU é admin/operator
    OR EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid()::text 
      AND role IN ('admin', 'operator')
    )
  );

-- Remove a policy anterior mais restritiva (para evitar conflito)
DROP POLICY IF EXISTS "rides_select" ON public.rides;

-- ==============================================================================
-- FIM — Motoristas agora podem ver corridas pendentes para aceitar
-- ==============================================================================
