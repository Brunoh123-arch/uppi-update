-- =====================================================
-- MIGRAÇÃO: Aumentar Janela de Oferta de Corrida
-- Data: 2026-05-30
-- =====================================================

CREATE OR REPLACE FUNCTION public.rpc_find_and_offer_ride(p_ride_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pickup_loc GEOGRAPHY(POINT);
    v_ride_status TEXT;
    v_service_type TEXT;
    v_gender_required TEXT;
    v_driver_id TEXT;
    v_offer_id UUID;
    v_search_radius INTEGER;
BEGIN
    -- 1. Bloquear linha da corrida para evitar conflitos de concorrência
    SELECT status, pickup_location, service_type INTO v_ride_status, v_pickup_loc, v_service_type
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    -- Se a corrida não existir ou já tiver sido aceita/cancelada, encerra o loop
    IF v_ride_status IS NULL OR v_ride_status NOT IN ('requested', 'searching') THEN
        RETURN FALSE;
    END IF;

    -- 2. Resolver restrição de gênero do serviço selecionado
    SELECT s.gender_required INTO v_gender_required
    FROM public.services s
    WHERE s.name = v_service_type OR s.id::text = v_service_type
    LIMIT 1;

    -- 3. Buscar o motorista 'online' aprovado mais próximo
    SELECT p.id, COALESCE(p.search_radius, 5000) INTO v_driver_id, v_search_radius
    FROM public.profiles p
    WHERE p.role = 'driver'
      AND p.status = 'online'
      AND p.current_location IS NOT NULL
      -- ─── ANTI CHERRY-PICKING: Excluir motoristas em cooldown ───
      AND (p.cooldown_until IS NULL OR p.cooldown_until < NOW())
      -- ═══ UPPI MULHER: Filtro estrito de gênero no servidor ═══
      -- Se o serviço exige gênero específico, SOMENTE motoristas com
      -- gênero verificado e correspondente podem receber a corrida.
      AND (
          v_gender_required IS NULL
          OR (p.gender = v_gender_required AND p.gender_verified = TRUE)
      )
      -- Filtrar por categoria do veículo correspondente ao serviço
      AND (
          v_service_type IS NULL OR
          p.vehicle_type IS NULL OR
          p.vehicle_type = COALESCE(
              (SELECT s.vehicle_category FROM public.services s WHERE s.name = v_service_type LIMIT 1),
              'carro'
          )
      )
      -- Evitar motoristas que já rejeitaram ou expiraram esta corrida recentemente (últimos 30 segundos)
      AND NOT EXISTS (
          SELECT 1 
          FROM public.ride_rejected_drivers rr 
          WHERE rr.ride_id = p_ride_id 
            AND rr.driver_id = p.id
            AND rr.created_at > now() - interval '30 seconds'
      )
      -- Evitar motoristas em corridas ativas
      AND NOT EXISTS (
          SELECT 1 
          FROM public.rides r 
          WHERE r.driver_id = p.id 
            AND r.status IN ('accepted', 'arrived', 'in_progress')
      )
      -- Evitar motoristas com ofertas de corrida ativas pendentes
      AND NOT EXISTS (
          SELECT 1
          FROM public.ride_offers ro
          WHERE ro.driver_id = p.id
            AND ro.status = 'offered'
            AND ro.expires_at > now()
      )
    ORDER BY 
      ST_Distance(p.current_location, v_pickup_loc) * 
      (1.0 + COALESCE(p.consecutive_rejections, 0) * 0.15)
    ASC
    LIMIT 1;

    -- 4. Se um motorista elegível for encontrado, criar a oferta
    IF v_driver_id IS NOT NULL THEN
        UPDATE public.ride_offers
        SET status = 'expired'
        WHERE ride_id = p_ride_id AND status = 'offered';

        -- Aumentado para 30 segundos (antes era 15 seconds)
        INSERT INTO public.ride_offers (ride_id, driver_id, status, expires_at)
        VALUES (p_ride_id, v_driver_id, 'offered', now() + interval '30 seconds')
        RETURNING id INTO v_offer_id;

        UPDATE public.rides
        SET status = 'searching',
            updated_at = now()
        WHERE id = p_ride_id;

        RETURN TRUE;
    ELSE
        UPDATE public.rides
        SET status = 'requested',
            updated_at = now()
        WHERE id = p_ride_id AND status = 'searching';

        RETURN FALSE;
    END IF;
END;
$$;

COMMENT ON FUNCTION public.rpc_find_and_offer_ride(UUID) IS 'Busca o motorista disponível mais próximo com filtro estrito de gênero (Uppi Mulher), anti cherry-picking (cooldown), e penalização por rejeições recentes. Oferta ativa por 30 segundos.';

REVOKE EXECUTE ON FUNCTION public.rpc_find_and_offer_ride(UUID) FROM authenticated, anon, public;
GRANT EXECUTE ON FUNCTION public.rpc_find_and_offer_ride(UUID) TO service_role;
