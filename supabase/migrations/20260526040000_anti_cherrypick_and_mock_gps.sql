-- ==============================================================================
-- MIGRAÇÃO: Anti Cherry-Picking + Proteção GPS Server-Side
-- 1. Adicionar colunas de controle de rejeição no profiles
-- 2. Modificar reject_ride para aplicar cooldown após 5 rejeições consecutivas
-- 3. Modificar assign_driver_to_ride para resetar contador ao aceitar
-- 4. Modificar rpc_find_and_offer_ride para excluir motoristas em cooldown
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- PARTE 1: Colunas de controle de rejeição
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS consecutive_rejections INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cooldown_until TIMESTAMP WITH TIME ZONE;

-- ─────────────────────────────────────────────────────────────────────────────
-- PARTE 2: reject_ride com cooldown automático
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reject_ride(
  p_ride_id UUID,
  p_driver_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rejections INTEGER;
  v_max_rejections INTEGER := 5;
  v_cooldown_minutes INTEGER := 10;
BEGIN
  -- [SEGURANÇA] Validar se o solicitante é de fato o motorista ou service_role
  IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR auth.uid()::text <> p_driver_id) THEN
      RAISE EXCEPTION 'Operação não autorizada. O motorista não corresponde ao usuário autenticado.';
  END IF;

  -- Inserir nas rejeições de corridas para evitar nova oferta a este motorista
  INSERT INTO public.ride_rejected_drivers (ride_id, driver_id)
  VALUES (p_ride_id, p_driver_id)
  ON CONFLICT (ride_id, driver_id) DO NOTHING;

  -- Atualizar status da oferta para 'rejected'
  UPDATE public.ride_offers
  SET status = 'rejected'
  WHERE ride_id = p_ride_id AND driver_id = p_driver_id AND status = 'offered';

  -- ─── ANTI CHERRY-PICKING: Incrementar rejeições consecutivas ───
  UPDATE public.profiles
  SET consecutive_rejections = COALESCE(consecutive_rejections, 0) + 1
  WHERE id = p_driver_id
  RETURNING consecutive_rejections INTO v_rejections;

  -- Buscar configuração dinâmica de limites (com fallback)
  BEGIN
    SELECT COALESCE((SELECT value::integer FROM app_settings WHERE key = 'max_consecutive_rejections'), 5)
    INTO v_max_rejections;
    SELECT COALESCE((SELECT value::integer FROM app_settings WHERE key = 'rejection_cooldown_minutes'), 10)
    INTO v_cooldown_minutes;
  EXCEPTION WHEN OTHERS THEN
    v_max_rejections := 5;
    v_cooldown_minutes := 10;
  END;

  -- Se atingiu o limite de rejeições consecutivas → cooldown
  IF v_rejections >= v_max_rejections THEN
    UPDATE public.profiles
    SET status = 'offline',
        cooldown_until = NOW() + (v_cooldown_minutes * interval '1 minute'),
        consecutive_rejections = 0
    WHERE id = p_driver_id;

    -- Também tirar de driver_locations
    UPDATE public.driver_locations
    SET status = 'offline'
    WHERE driver_id = p_driver_id;

    -- [SISTEMA DE DISPONIBILIDADE] Motorista atingiu o limite de passes seguidos.
    -- O sistema registra indisponibilidade temporária por alta rotatividade de passes.
    -- Nota juríica: isso é um indicador de qualidade de serviço, não uma sanção trabalhista.
    RAISE NOTICE '[disponibilidade] Parceiro % ficou temporariamente indisponível (alta rotatividade de passes). Pausa de % min. Score de passes resetado.',
      p_driver_id, v_cooldown_minutes;
  END IF;

  -- Avançar o despacho para o próximo motorista imediatamente
  PERFORM public.rpc_find_and_offer_ride(p_ride_id);
END;
$$;

COMMENT ON FUNCTION public.reject_ride(UUID, TEXT) IS 'Registra a rejeição, incrementa contador de rejeições consecutivas, aplica cooldown de 10min após 5 rejeições, e despacha para o próximo motorista. [Protegido via JWT]';

-- ─────────────────────────────────────────────────────────────────────────────
-- PARTE 3: assign_driver_to_ride resetando contador ao aceitar
-- ─────────────────────────────────────────────────────────────────────────────
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
    v_rows INT;
    v_driver_lat DOUBLE PRECISION;
    v_driver_lng DOUBLE PRECISION;
    v_pickup_lat DOUBLE PRECISION;
    v_pickup_lng DOUBLE PRECISION;
    v_dist_meters DOUBLE PRECISION;
    v_eta_minutes INTEGER;
    v_eta_pickup TIMESTAMP WITH TIME ZONE;
BEGIN
    -- [SEGURANÇA] Validar se o solicitante é de fato o motorista ou service_role
    IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR auth.uid()::text <> p_driver_id) THEN
        RAISE EXCEPTION 'Operação não autorizada. O motorista não corresponde ao usuário autenticado.';
    END IF;

    -- [SEGURANÇA] Bloquear linha da corrida para evitar conflitos concorrentes
    SELECT status, pickup_lat, pickup_lng INTO v_status, v_pickup_lat, v_pickup_lng
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

    -- [SEGURANÇA] Atualizar oferta específica deste motorista como 'accepted' e garantir que ela existia e estava ativa
    UPDATE public.ride_offers
    SET status = 'accepted'
    WHERE ride_id = p_ride_id AND driver_id = p_driver_id AND status = 'offered';
    
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 0 THEN
        RAISE EXCEPTION 'Você não possui uma oferta ativa para esta corrida.';
    END IF;

    -- Expirar as demais ofertas ativas para essa corrida
    UPDATE public.ride_offers
    SET status = 'expired'
    WHERE ride_id = p_ride_id AND driver_id <> p_driver_id AND status = 'offered';

    -- Calcular ETA dinâmico baseado no PostGIS
    SELECT lat, lng INTO v_driver_lat, v_driver_lng
    FROM public.driver_locations
    WHERE driver_id = p_driver_id;

    IF v_driver_lat IS NOT NULL AND v_pickup_lat IS NOT NULL THEN
        v_dist_meters := ST_Distance(
            ST_SetSRID(ST_MakePoint(v_driver_lng, v_driver_lat), 4326)::geography,
            ST_SetSRID(ST_MakePoint(v_pickup_lng, v_pickup_lat), 4326)::geography
        );
        v_eta_minutes := CEIL(v_dist_meters / 500.0); -- ~30km/h
        v_eta_pickup := NOW() + (v_eta_minutes * interval '1 minute');
    ELSE
        v_eta_pickup := NOW() + interval '5 minutes';
    END IF;

    -- Atribuir o motorista à corrida, passar o status para 'accepted', definir accepted_at e eta_pickup
    UPDATE public.rides
    SET driver_id = p_driver_id,
        status = 'accepted',
        accepted_at = NOW(),
        eta_pickup = v_eta_pickup,
        updated_at = NOW()
    WHERE id = p_ride_id;

    -- ─── ANTI CHERRY-PICKING: Resetar rejeições ao aceitar corrida ───
    UPDATE public.profiles
    SET consecutive_rejections = 0
    WHERE id = p_driver_id AND consecutive_rejections > 0;
END;
$$;

COMMENT ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) IS 'Atribui o motorista à corrida, marca a oferta como aceita, expira outras ofertas, reseta contador de rejeições consecutivas. [Protegido via JWT e Validação de Oferta]';

-- ─────────────────────────────────────────────────────────────────────────────
-- PARTE 4: rpc_find_and_offer_ride excluindo motoristas em cooldown
-- ─────────────────────────────────────────────────────────────────────────────
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

    -- 2. Buscar o motorista 'online' aprovado mais próximo
    SELECT p.id, COALESCE(p.search_radius, 5000) INTO v_driver_id, v_search_radius
    FROM public.profiles p
    WHERE p.role = 'driver'
      AND p.status = 'online'
      AND p.current_location IS NOT NULL
      -- ─── ANTI CHERRY-PICKING: Excluir motoristas em cooldown ───
      AND (p.cooldown_until IS NULL OR p.cooldown_until < NOW())
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
    ORDER BY 
      ST_Distance(p.current_location, v_pickup_loc) * 
      (1.0 + COALESCE(p.consecutive_rejections, 0) * 0.15) -- Ajuste de score de compatibilidade por passes recentes
    ASC
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

COMMENT ON FUNCTION public.rpc_find_and_offer_ride(UUID) IS 'Busca o motorista disponível mais próximo (excluindo cooldowns), penaliza levemente motoristas com rejeições recentes na ordenação.';

-- Garantir privilégios
REVOKE EXECUTE ON FUNCTION public.rpc_find_and_offer_ride(UUID) FROM authenticated, anon, public;
GRANT EXECUTE ON FUNCTION public.rpc_find_and_offer_ride(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_ride(UUID, TEXT) TO authenticated;
