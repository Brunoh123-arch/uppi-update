-- Mantém profiles.total_rides e profiles.total_distance atualizados
-- automaticamente a cada corrida finalizada (insert em driver_earnings,
-- que ocorre exatamente uma vez por corrida dentro de finish_ride).

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

  UPDATE public.profiles_raw
  SET total_rides    = COALESCE(total_rides, 0) + 1,
      total_distance = COALESCE(total_distance, 0) + COALESCE(v_distance, 0)::integer
  WHERE id = NEW.driver_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_driver_ride_totals ON public.driver_earnings;
CREATE TRIGGER trg_update_driver_ride_totals
  AFTER INSERT ON public.driver_earnings
  FOR EACH ROW
  EXECUTE FUNCTION public.update_driver_ride_totals();

-- Corrige o INSERT via view payout_accounts: o trigger INSTEAD OF devolvia
-- NEW com id/created_at nulos (gerados só na tabela raw), quebrando o
-- `insert ... returning` usado pela edge function user-actions.
CREATE OR REPLACE FUNCTION public.payout_accounts_view_dml_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.id := COALESCE(NEW.id, gen_random_uuid());
    NEW.created_at := COALESCE(NEW.created_at, now());
    NEW.is_default := COALESCE(NEW.is_default, false);
    INSERT INTO public.payout_accounts_raw (
      id, driver_id, payout_method_id, routing_number, account_holder_name, bank_name,
      is_default, account_holder_country, account_holder_city, account_holder_state,
      account_holder_address, account_holder_phone, account_holder_zip, created_at,
      encrypted_account_number
    ) VALUES (
      NEW.id, NEW.driver_id, NEW.payout_method_id, NEW.routing_number, NEW.account_holder_name, NEW.bank_name,
      NEW.is_default, NEW.account_holder_country, NEW.account_holder_city, NEW.account_holder_state,
      NEW.account_holder_address, NEW.account_holder_phone, NEW.account_holder_zip, NEW.created_at,
      public.encrypt_val(NEW.account_number)
    );
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    UPDATE public.payout_accounts_raw SET
      driver_id = NEW.driver_id,
      payout_method_id = NEW.payout_method_id,
      routing_number = NEW.routing_number,
      account_holder_name = NEW.account_holder_name,
      bank_name = NEW.bank_name,
      is_default = NEW.is_default,
      account_holder_country = NEW.account_holder_country,
      account_holder_city = NEW.account_holder_city,
      account_holder_state = NEW.account_holder_state,
      account_holder_address = NEW.account_holder_address,
      account_holder_phone = NEW.account_holder_phone,
      account_holder_zip = NEW.account_holder_zip,
      created_at = NEW.created_at,
      encrypted_account_number = CASE
        WHEN NEW.account_number IS DISTINCT FROM OLD.account_number THEN public.encrypt_val(NEW.account_number)
        ELSE encrypted_account_number
      END
    WHERE id = OLD.id;
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    DELETE FROM public.payout_accounts_raw WHERE id = OLD.id;
    RETURN OLD;
  END IF;
END;
$$;

-- Backfill: recalcular totais históricos a partir das corridas existentes
UPDATE public.profiles_raw p
SET total_rides    = agg.cnt,
    total_distance = agg.dist
FROM (
  SELECT driver_id,
         COUNT(*) AS cnt,
         COALESCE(SUM(COALESCE(actual_distance, distance_meters, distance, 0)), 0)::integer AS dist
  FROM public.rides
  WHERE status IN ('completed', 'finished', 'waiting_for_review')
    AND driver_id IS NOT NULL
  GROUP BY driver_id
) agg
WHERE p.id = agg.driver_id;
