-- Migration: Exempt new drivers automatically for 30 days
-- Garantir que qualquer novo motorista cadastrado na tabela raw seja isento de comissão por 30 dias automaticamente.

CREATE OR REPLACE FUNCTION public.exempt_new_drivers_commission()
RETURNS TRIGGER AS $$
BEGIN
  -- Se o perfil mudou para 'driver' ou foi criado como 'driver', e a isenção está nula ou no passado:
  IF NEW.role = 'driver' AND (TG_OP = 'INSERT' OR OLD.role IS DISTINCT FROM 'driver' OR NEW.role IS DISTINCT FROM OLD.role) THEN
    IF NEW.commission_exempt_until IS NULL OR NEW.commission_exempt_until < NOW() THEN
      NEW.commission_exempt_until := NOW() + INTERVAL '30 days';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_exempt_new_drivers ON public.profiles_raw;
CREATE TRIGGER trg_exempt_new_drivers
BEFORE INSERT OR UPDATE ON public.profiles_raw
FOR EACH ROW
EXECUTE FUNCTION public.exempt_new_drivers_commission();

COMMENT ON FUNCTION public.exempt_new_drivers_commission() IS 'Isenta automaticamente novos motoristas de comissão pelos primeiros 30 dias de cadastro.';
