-- =====================================================
-- MIGRAÇÃO: Heartbeat, Session Kick e Mudança de Destino
-- Data: 2026-05-26
-- =====================================================

-- 1. Coluna original_fare: Armazena a tarifa original quando o passageiro
--    muda o destino em corrida (update-ride-destination)
ALTER TABLE public.rides
  ADD COLUMN IF NOT EXISTS original_fare DECIMAL(10,2);

COMMENT ON COLUMN public.rides.original_fare IS 'Tarifa original antes de mudança de destino em corrida. NULL se destino não foi alterado.';

-- 2. Índice para queries do heartbeat cleanup (corridas arrived stale)
CREATE INDEX IF NOT EXISTS idx_rides_arrived_updated
  ON public.rides (status, updated_at)
  WHERE status = 'arrived';

-- 3. Índice para session kick: busca rápida de fcm_token por user
-- (o profiles já tem PK em id, então o SELECT é eficiente)
-- Apenas garantir que fcm_token não seja indexado desnecessariamente

COMMENT ON COLUMN public.profiles.fcm_token IS 'Token FCM do dispositivo ativo. Ao mudar, o token antigo recebe push de session_kick para forçar logout.';
