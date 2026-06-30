-- ==============================================================================
-- MIGRAÇÃO: Cancelar ofertas de corrida ativas quando a corrida é encerrada/cancelada
-- Garante que o motorista pare de receber a oferta no exato segundo em que o
-- passageiro cancela a corrida.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.cancel_active_offers_on_ride_end()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Se o status da corrida mudou para um estado final/cancelado
  IF NEW.status IN ('rider_canceled', 'driver_canceled', 'canceled', 'completed', 'finished', 'expired') THEN
    UPDATE public.ride_offers
    SET status = 'expired'
    WHERE ride_id = NEW.id AND status = 'offered';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cancel_active_offers ON public.rides;
CREATE TRIGGER trg_cancel_active_offers
  AFTER UPDATE OF status ON public.rides
  FOR EACH ROW
  EXECUTE FUNCTION public.cancel_active_offers_on_ride_end();

COMMENT ON FUNCTION public.cancel_active_offers_on_ride_end() IS 
  'Expira automaticamente todas as ofertas pendentes na tabela ride_offers quando a corrida correspondente é cancelada ou concluída.';
