-- =====================================================================
-- MIGRAÇÃO: Correções críticas de triggers e funções — Rodada 3
-- Data: 2026-05-28
-- =====================================================================

-- 1. CORRIGIR notify_ride_status_change
-- Bug: só liberava motorista para 'canceled', ignorando 'driver_canceled' e 'rider_canceled'
-- Resultado: motorista ficava preso em status 'busy' após cancelamento
CREATE OR REPLACE FUNCTION public.notify_ride_status_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;

  -- Motorista aceita corrida → marca como ocupado
  IF NEW.status = 'accepted' AND NEW.driver_id IS NOT NULL THEN
    UPDATE driver_locations SET status = 'busy' WHERE driver_id = NEW.driver_id;
  END IF;

  -- Corrida finalizada ou cancelada (qualquer variação) → libera motorista
  IF NEW.status IN ('completed', 'finished', 'canceled', 'driver_canceled', 'rider_canceled', 'expired', 'no_driver', 'no_close_found')
     AND NEW.driver_id IS NOT NULL THEN
    UPDATE driver_locations SET status = 'online' WHERE driver_id = NEW.driver_id;
    UPDATE profiles SET status = 'online' WHERE id = NEW.driver_id;
  END IF;

  -- Corrida em andamento → atualiza perfil
  IF NEW.status IN ('in_progress', 'started') AND NEW.driver_id IS NOT NULL THEN
    UPDATE profiles SET status = 'in_progress' WHERE id = NEW.driver_id;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_ride_status_change falhou: %', SQLERRM;
  RETURN NEW;
END;
$$;

-- 2. CRIAR increment_wallet_pending (faltava — quebrava handle_completed_ride_financials para pagamentos digitais)
CREATE OR REPLACE FUNCTION public.increment_wallet_pending(
  p_user_id TEXT,
  p_amount NUMERIC
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Credita diretamente na carteira.
  -- Uma coluna 'pending_balance' pode ser adicionada futuramente para separar saldo pendente.
  PERFORM public.increment_wallet(p_user_id, p_amount);
END;
$$;

GRANT EXECUTE ON FUNCTION public.increment_wallet_pending(TEXT, NUMERIC) TO service_role;
GRANT EXECUTE ON FUNCTION public.increment_wallet_pending(TEXT, NUMERIC) TO postgres;

-- 3. CORRIGIR recover_stuck_rides para incluir 'in_progress' (além de 'started')
-- Bug: corridas em 'in_progress' há mais de 3h nunca eram recuperadas
CREATE OR REPLACE FUNCTION public.recover_stuck_rides()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
    v_recovered_count INTEGER := 0;
BEGIN
    -- 2.1 CORRIDAS EM 'requested' há mais de 5 minutos
    FOR rec IN 
        SELECT id, rider_id 
        FROM public.rides 
        WHERE status = 'requested' 
          AND created_at < now() - interval '5 minutes'
    LOOP
        UPDATE public.rides SET status = 'expired', updated_at = now() WHERE id = rec.id;
        UPDATE public.ride_offers SET status = 'expired' WHERE ride_id = rec.id AND status = 'offered';
        INSERT INTO public.app_errors (app_type, error_message, severity, user_id, metadata)
        VALUES ('database', 'Corrida #' || substring(rec.id::text from 1 for 8) || ' expirada: sem motorista em 5 min.', 'warning', rec.rider_id,
                jsonb_build_object('ride_id', rec.id, 'recovery_type', 'requested_stuck'));
        v_recovered_count := v_recovered_count + 1;
    END LOOP;

    -- 2.2 CORRIDAS 'accepted'/'arrived' com motorista offline há >15 min
    FOR rec IN 
        SELECT r.id, r.driver_id, r.rider_id, r.status AS ride_status, dl.updated_at AS last_ping
        FROM public.rides r
        JOIN public.driver_locations dl ON r.driver_id = dl.driver_id
        WHERE r.status IN ('accepted', 'arrived')
          AND r.updated_at < now() - interval '15 minutes'
    LOOP
        IF rec.last_ping IS NULL OR rec.last_ping < now() - interval '5 minutes' THEN
            UPDATE public.rides SET status = 'requested', driver_id = NULL, accepted_at = NULL, updated_at = now() WHERE id = rec.id;
            UPDATE public.profiles SET status = 'offline', updated_at = now() WHERE id = rec.driver_id;
            UPDATE public.driver_locations SET status = 'offline', updated_at = now() WHERE driver_id = rec.driver_id;
            UPDATE public.ride_offers SET status = 'expired' WHERE ride_id = rec.id AND driver_id = rec.driver_id AND status = 'offered';
            INSERT INTO public.app_errors (app_type, error_message, severity, user_id, metadata)
            VALUES ('database', 'Corrida #' || substring(rec.id::text from 1 for 8) || ' re-enfileirada: motorista offline.', 'warning', rec.driver_id,
                    jsonb_build_object('ride_id', rec.id, 'driver_id', rec.driver_id, 'recovery_type', 'driver_offline_recovered'));
            v_recovered_count := v_recovered_count + 1;
        END IF;
    END LOOP;

    -- 2.3 CORRIDAS 'in_progress' ou 'started' há mais de 3h (Bug original: só verificava 'started')
    FOR rec IN 
        SELECT id, driver_id, rider_id 
        FROM public.rides 
        WHERE status IN ('in_progress', 'started')
          AND updated_at < now() - interval '3 hours'
    LOOP
        UPDATE public.rides SET status = 'finished', updated_at = now() WHERE id = rec.id;
        UPDATE public.profiles SET status = 'online', updated_at = now() WHERE id = rec.driver_id;
        INSERT INTO public.app_errors (app_type, error_message, severity, user_id, metadata)
        VALUES ('database', 'ALERTA CRÍTICO: Corrida #' || substring(rec.id::text from 1 for 8) || ' finalizada após 3h em trânsito.', 'critical', rec.driver_id,
                jsonb_build_object('ride_id', rec.id, 'driver_id', rec.driver_id, 'recovery_type', 'ride_duration_exceeded_completed'));
        v_recovered_count := v_recovered_count + 1;
    END LOOP;

    IF v_recovered_count > 0 THEN
        RAISE NOTICE 'Daemon de Recuperação: % anomalias corrigidas.', v_recovered_count;
    END IF;
END;
$$;

-- 4. INSERIR política padrão de cancelamento (estava vazia — handle_cancelled_ride_financials retornava early)
INSERT INTO public.cancellation_policies (grace_period_seconds, cancellation_fee, driver_compensation, is_active)
VALUES (120, 5.00, 3.00, true)
ON CONFLICT DO NOTHING;

-- 5. LIMPAR corridas presas em 'waiting_for_review' há mais de 24h
UPDATE public.rides 
SET status = 'finished', updated_at = now()
WHERE status = 'waiting_for_review'
  AND updated_at < now() - interval '24 hours';
