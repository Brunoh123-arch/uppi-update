-- ==============================================================================
-- MIGRAÇÃO — AUDITORIA DE CANCELAMENTOS DE CORRIDA (Pillar 6)
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.ride_cancellations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id UUID REFERENCES public.rides(id) ON DELETE CASCADE NOT NULL,
    cancelled_by TEXT REFERENCES public.profiles(id) NOT NULL,
    reason_id UUID REFERENCES public.cancel_reasons(id) ON DELETE SET NULL,
    cancellation_fee NUMERIC(10,2) DEFAULT 0.00,
    driver_compensated_amount NUMERIC(10,2) DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- Habilitar RLS na tabela
ALTER TABLE public.ride_cancellations ENABLE ROW LEVEL SECURITY;

-- Política de leitura: Administradores e envolvidos na corrida podem ler
CREATE POLICY "cancellations_select_policy" ON public.ride_cancellations
    FOR SELECT USING (
        auth.uid()::text = cancelled_by OR 
        EXISTS (
            SELECT 1 FROM public.rides 
            WHERE rides.id = ride_cancellations.ride_id 
            AND (rides.rider_id = auth.uid()::text OR rides.driver_id = auth.uid()::text)
        ) OR
        (SELECT role FROM public.profiles WHERE id = auth.uid()::text) = 'admin'
    );

-- Habilitar Realtime CDC
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'ride_cancellations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_cancellations;
  END IF;
END $$;

ALTER TABLE public.ride_cancellations REPLICA IDENTITY FULL;
