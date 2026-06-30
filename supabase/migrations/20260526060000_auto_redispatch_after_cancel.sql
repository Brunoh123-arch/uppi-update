-- ==============================================================================
-- MIGRAÇÃO: Suporte ao redespacho automático após cancelamento de motorista
-- Adiciona coluna driver_cancel_count à tabela rides para rastrear o número de
-- vezes que motoristas cancelaram uma corrida específica, habilitando o limite
-- de MAX_DRIVER_CANCELS (3) no cancel-order Edge Function.
-- ==============================================================================

-- Adicionar contador de cancelamentos de motoristas por corrida
ALTER TABLE public.rides
  ADD COLUMN IF NOT EXISTS driver_cancel_count INTEGER DEFAULT 0;

COMMENT ON COLUMN public.rides.driver_cancel_count IS 
  'Número de vezes que motoristas cancelaram esta corrida. Limite de 3 antes de expirar definitivamente.';

-- Criar índice para consulta rápida nas corridas reabertas para redespacho
CREATE INDEX IF NOT EXISTS idx_rides_driver_cancel_count
  ON public.rides (driver_cancel_count)
  WHERE status = 'requested';

-- Criar trigger para incrementar o contador automaticamente ao cancelar
CREATE OR REPLACE FUNCTION public.increment_driver_cancel_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Se o status mudou para driver_canceled, incrementar o contador NA corrida original
  -- (o cancel-order vai reabrir com status='requested', então incrementamos antes)
  IF NEW.status = 'driver_canceled' AND OLD.status NOT IN ('driver_canceled', 'rider_canceled', 'expired', 'completed', 'finished') THEN
    NEW.driver_cancel_count = COALESCE(OLD.driver_cancel_count, 0) + 1;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_increment_driver_cancel ON public.rides;
CREATE TRIGGER trg_increment_driver_cancel
  BEFORE UPDATE ON public.rides
  FOR EACH ROW
  EXECUTE FUNCTION public.increment_driver_cancel_count();

-- ==============================================================================
-- NOTA: O cancel-order Edge Function agora:
-- 1. Lê driver_cancel_count da tabela ride_cancellations (abordagem via JOIN)
-- 2. Se count < 3: reabre a corrida com status='requested' e dispara rpc_find_and_offer_ride
-- 3. Se count >= 3: marca como 'expired' definitivamente
-- A trigger acima garante que o contador é mantido mesmo no registro histórico.
-- ==============================================================================
