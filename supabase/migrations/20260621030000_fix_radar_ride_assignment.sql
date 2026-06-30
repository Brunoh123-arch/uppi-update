-- =====================================================================
-- MIGRAÇÃO: Permitir Aceite de Corrida via Radar (requested)
-- Data: 2026-06-21
-- Objetivo: Redefine assign_driver_to_ride para aceitar atribuições diretas
--            quando a corrida está com status 'requested' (aberta no radar),
--            mesmo se não houver registro prévio em ride_offers para o motorista.
-- =====================================================================

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
    v_service_type TEXT;
    v_service_id TEXT;
    v_gender_required TEXT;
    v_driver_gender TEXT;
    v_driver_gender_verified BOOLEAN;
    v_pickup_lat DOUBLE PRECISION;
    v_pickup_lng DOUBLE PRECISION;
    v_driver_lat DOUBLE PRECISION;
    v_driver_lng DOUBLE PRECISION;
    v_dist_meters DOUBLE PRECISION;
    v_eta_minutes INTEGER;
    v_eta_pickup TIMESTAMP WITH TIME ZONE;
    v_rows INT;
BEGIN
    -- 1. [SEGURANÇA] Validar se o solicitante é de fato o motorista ou service_role
    IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR auth.uid()::text <> p_driver_id) THEN
        RAISE EXCEPTION 'Operação não autorizada. O motorista não corresponde ao usuário autenticado.';
    END IF;

    -- 2. [SEGURANÇA] Bloquear linha da corrida para evitar conflitos concorrentes
    SELECT status, service_type, service_id, pickup_lat, pickup_lng 
    INTO v_status, v_service_type, v_service_id, v_pickup_lat, v_pickup_lng
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

    -- 3. [UPPI MULHER] Validar restrição estrita de gênero para o serviço
    SELECT s.gender_required INTO v_gender_required
    FROM public.services s
    WHERE s.id = v_service_id OR s.name = v_service_type OR s.id::text = v_service_type
    LIMIT 1;

    IF v_gender_required IS NOT NULL THEN
        SELECT gender, gender_verified 
        INTO v_driver_gender, v_driver_gender_verified
        FROM public.profiles
        WHERE id = p_driver_id;

        IF v_driver_gender IS DISTINCT FROM v_gender_required OR v_driver_gender_verified IS NOT TRUE THEN
            RAISE EXCEPTION 'Este serviço é exclusivo para motoristas mulheres verificadas.';
        END IF;
    END IF;

    -- 4. [SEGURANÇA] Atualizar oferta específica deste motorista como 'accepted' se ela existir
    UPDATE public.ride_offers
    SET status = 'accepted'
    WHERE ride_id = p_ride_id AND driver_id = p_driver_id AND status = 'offered';
    
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    
    -- Se não havia oferta direcionada ('offered') para este motorista em específico (caso do Radar de Viagens),
    -- mas o status da corrida é 'requested' (está aberta no radar):
    IF v_rows = 0 THEN
        IF v_status = 'requested' THEN
            -- Inserimos um registro em ride_offers como 'accepted' para fins de histórico e integridade
            INSERT INTO public.ride_offers (ride_id, driver_id, status, expires_at)
            VALUES (p_ride_id, p_driver_id, 'accepted', NOW() + interval '1 minute');
        ELSE
            RAISE EXCEPTION 'Você não possui uma oferta ativa para esta corrida.';
        END IF;
    END IF;

    -- 5. Expirar as demais ofertas ativas para essa corrida
    UPDATE public.ride_offers
    SET status = 'expired'
    WHERE ride_id = p_ride_id AND driver_id <> p_driver_id AND status = 'offered';

    -- 6. Calcular ETA dinâmico baseado no PostGIS
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

    -- 7. Atribuir o motorista à corrida, passar o status para 'accepted', definir accepted_at e eta_pickup
    UPDATE public.rides
    SET driver_id = p_driver_id,
        status = 'accepted',
        accepted_at = NOW(),
        eta_pickup = v_eta_pickup,
        updated_at = NOW()
    WHERE id = p_ride_id;

    -- 8. [ANTI CHERRY-PICKING] Resetar rejeições consecutivas do motorista ao aceitar corrida
    UPDATE public.profiles
    SET consecutive_rejections = 0
    WHERE id = p_driver_id AND consecutive_rejections > 0;
END;
$$;

COMMENT ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) IS 'Atribui um motorista a uma corrida com verificação estrita de gênero verificado (Uppi Mulher), aceitação direta para corridas do radar (status requested) e controle transacional de concorrência.';
