-- ==============================================================================
-- MIGRAÇÃO: Loop de Match e Despacho de Corridas (Fila Dinâmica)
-- 1. rpc_find_and_offer_ride(p_ride_id UUID)
-- 2. rpc_sweep_expired_offers()
-- 3. Trigger trg_on_ride_requested
-- 4. Atualização das RPCs reject_ride e assign_driver_to_ride
-- ==============================================================================

-- 1. BUSCA E DESPACHO DINÂMICO DE DRIVERS (PostGIS + CDC)
CREATE OR REPLACE FUNCTION public.rpc_find_and_offer_ride(p_ride_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pickup_loc GEOGRAPHY(POINT);
    v_ride_status TEXT;
    v_driver_id TEXT;
    v_offer_id UUID;
    v_search_radius INTEGER;
BEGIN
    -- 1. Bloquear linha da corrida para evitar conflitos de concorrência
    SELECT status, pickup_location INTO v_ride_status, v_pickup_loc
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    -- Se a corrida não existir ou já tiver sido aceita/cancelada, encerra o loop
    IF v_ride_status IS NULL OR v_ride_status NOT IN ('requested', 'searching') THEN
        RETURN FALSE;
    END IF;

    -- 2. Buscar o motorista 'online' aprovado mais próximo que ainda não rejeitou esta corrida e não esteja ocupado
    SELECT p.id, COALESCE(p.search_radius, 5000) INTO v_driver_id, v_search_radius
    FROM public.profiles p
    WHERE p.role = 'driver'
      AND p.status = 'online'
      AND p.current_location IS NOT NULL
      -- Evitar motoristas que já rejeitaram ou expiraram esta corrida
      AND NOT EXISTS (
          SELECT 1 
          FROM public.ride_rejected_drivers rr 
          WHERE rr.ride_id = p_ride_id 
            AND rr.driver_id = p.id
      )
      -- Evitar motoristas em corridas ativas
      AND NOT EXISTS (
          SELECT 1 
          FROM public.rides r 
          WHERE r.driver_id = p.id 
            AND r.status IN ('accepted', 'arrived', 'in_progress')
      )
      -- Evitar motoristas com ofertas de corrida ativas pendentes (de qualquer corrida)
      AND NOT EXISTS (
          SELECT 1
          FROM public.ride_offers ro
          WHERE ro.driver_id = p.id
            AND ro.status = 'offered'
            AND ro.expires_at > now()
      )
    ORDER BY ST_Distance(p.current_location, v_pickup_loc) ASC
    LIMIT 1;

    -- 3. Se um motorista elegível for encontrado, criar a oferta e atualizar o status
    IF v_driver_id IS NOT NULL THEN
        -- Expirar ofertas anteriores ainda marcadas como 'offered' para esta corrida
        UPDATE public.ride_offers
        SET status = 'expired'
        WHERE ride_id = p_ride_id AND status = 'offered';

        -- Inserir nova oferta de 15 segundos
        INSERT INTO public.ride_offers (ride_id, driver_id, status, expires_at)
        VALUES (p_ride_id, v_driver_id, 'offered', now() + interval '15 seconds')
        RETURNING id INTO v_offer_id;

        -- Alterar status da corrida para 'searching'
        UPDATE public.rides
        SET status = 'searching',
            updated_at = now()
        WHERE id = p_ride_id;

        RETURN TRUE;
    ELSE
        -- Nenhum motorista encontrado na região: reverter status para 'requested'
        UPDATE public.rides
        SET status = 'requested',
            updated_at = now()
        WHERE id = p_ride_id AND status = 'searching';

        RETURN FALSE;
    END IF;
END;
$$;

COMMENT ON FUNCTION public.rpc_find_and_offer_ride(UUID) IS 'Busca o motorista disponível mais próximo via PostGIS e insere uma oferta de 15 segundos em ride_offers.';

-- 2. VARREDURA DE OFERTAS EXPIRADAS (TIMERS EXPIRED)
CREATE OR REPLACE FUNCTION public.rpc_sweep_expired_offers()
RETURNS TABLE (
    offer_id UUID,
    ride_id UUID,
    driver_id TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
BEGIN
    -- Varre ofertas oferecidas expiradas
    FOR r IN 
        SELECT ro.id, ro.ride_id, ro.driver_id
        FROM public.ride_offers ro
        WHERE ro.status = 'offered'
          AND ro.expires_at < now()
    LOOP
        -- Atualizar status da oferta para expirado
        UPDATE public.ride_offers
        SET status = 'expired'
        WHERE id = r.id AND status = 'offered';

        IF FOUND THEN
            -- Inserir motorista na lista de rejeitados para esta corrida para evitar novo loop
            INSERT INTO public.ride_rejected_drivers (ride_id, driver_id)
            VALUES (r.ride_id, r.driver_id)
            ON CONFLICT (ride_id, driver_id) DO NOTHING;

            -- Avançar o match procurando o próximo motorista geolocalizado
            PERFORM public.rpc_find_and_offer_ride(r.ride_id);

            -- Preencher valores de retorno
            offer_id := r.id;
            ride_id := r.ride_id;
            driver_id := r.driver_id;
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.rpc_sweep_expired_offers() IS 'Varre e expira ofertas que excederam o tempo limite de 15 segundos, salvando a rejeição e avançando para o próximo motorista.';

-- 3. TRIGGER AUTOMÁTICO DE CRIAÇÃO/ATUALIZAÇÃO DE CORRIDA
CREATE OR REPLACE FUNCTION public.trg_on_ride_requested_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Evitar loop imediato recursivo se a corrida foi simplesmente revertida de 'searching' para 'requested'
    IF TG_OP = 'UPDATE' AND OLD.status = 'searching' THEN
        RETURN NEW;
    END IF;

    -- Disparar loop de despacho imediatamente
    PERFORM public.rpc_find_and_offer_ride(NEW.id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_on_ride_requested ON public.rides;
CREATE TRIGGER trg_on_ride_requested
    AFTER INSERT OR UPDATE OF status ON public.rides
    FOR EACH ROW
    WHEN (NEW.status = 'requested')
    EXECUTE FUNCTION public.trg_on_ride_requested_fn();

-- 4. ATUALIZAÇÃO DA RPC DE ASSINAR CORRIDA (ACEITE DO MOTORISTA)
CREATE OR REPLACE FUNCTION public.assign_driver_to_ride(
    p_ride_id UUID,
    p_driver_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_status TEXT;
BEGIN
    -- Bloquear linha da corrida para evitar conflitos concorrentes
    SELECT status INTO v_status
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Corrida não encontrada (ID: %)', p_ride_id;
    END IF;

    -- Agora aceitamos tanto 'requested' quanto 'searching'
    IF v_status NOT IN ('requested', 'searching') THEN
        RAISE EXCEPTION 'A corrida não está mais disponível para aceite (status atual: %)', v_status;
    END IF;

    -- Atualizar oferta específica deste motorista como 'accepted'
    UPDATE public.ride_offers
    SET status = 'accepted'
    WHERE ride_id = p_ride_id AND driver_id = p_driver_id AND status = 'offered';

    -- Expirar as demais ofertas ativas para essa corrida
    UPDATE public.ride_offers
    SET status = 'expired'
    WHERE ride_id = p_ride_id AND driver_id <> p_driver_id AND status = 'offered';

    -- Atribuir o motorista à corrida e passar o status para 'accepted'
    UPDATE public.rides
    SET driver_id = p_driver_id,
        status = 'accepted',
        updated_at = now()
    WHERE id = p_ride_id;
END;
$$;

COMMENT ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) IS 'Atribui o motorista à corrida, marca a oferta como aceita e expira outras ofertas pendentes da mesma corrida.';

-- 5. ATUALIZAÇÃO DA RPC DE REJEITAR CORRIDA
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
  -- Inserir nas rejeições de corridas para evitar nova oferta a este motorista
  INSERT INTO public.ride_rejected_drivers (ride_id, driver_id)
  VALUES (p_ride_id, p_driver_id)
  ON CONFLICT (ride_id, driver_id) DO NOTHING;

  -- Atualizar status da oferta para 'rejected'
  UPDATE public.ride_offers
  SET status = 'rejected'
  WHERE ride_id = p_ride_id AND driver_id = p_driver_id AND status = 'offered';

  -- Avançar o despacho para o próximo motorista imediatamente
  PERFORM public.rpc_find_and_offer_ride(p_ride_id);
END;
$$;

COMMENT ON FUNCTION public.reject_ride(UUID, TEXT) IS 'Registra a rejeição do motorista, atualiza a oferta para rejeitada e despacha instantaneamente para o próximo motorista geolocalizado.';

-- 6. AGENDAMENTO CRON DE SEGURANÇA
SELECT cron.unschedule('sweep-expired-ride-offers') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'sweep-expired-ride-offers');

SELECT cron.schedule(
  'sweep-expired-ride-offers',
  '* * * * *',
  $$
    SELECT public.rpc_sweep_expired_offers();
  $$
);

-- Garantir privilégios
GRANT EXECUTE ON FUNCTION public.rpc_find_and_offer_ride(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_sweep_expired_offers() TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_ride(UUID, TEXT) TO authenticated;
