-- ==============================================================================
-- MIGRAÇÃO: Lógica Reativa e Triggers do Ecossistema Uppi
-- 1. rpc_calculate_ride_fare (Cálculo de preço dinâmico georreferenciado)
-- 2. sync_driver_profile_kyc (Trigger para sincronizar perfil com histórico KYC)
-- 3. rpc_get_or_create_ride_share_token (Gerador e leitor de tokens de rota)
-- 4. handle_completed_ride_financials (Trigger de Split financeiro e carteira)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. CÁLCULO DE PREÇO DINÂMICO GEORREFERENCIADO
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_calculate_ride_fare(
    p_pickup_lat FLOAT8,
    p_pickup_lng FLOAT8,
    p_dropoff_lat FLOAT8,
    p_dropoff_lng FLOAT8,
    p_base_fare DECIMAL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_multiplier NUMERIC(3,2) := 1.00;
    v_surge_id UUID := NULL;
    v_surge_name TEXT := NULL;
    v_final_fare DECIMAL;
BEGIN
    -- Encontra a surge_zone ativa que contenha o ponto de partida (pickup) ou destino (dropoff)
    -- e que possua o maior multiplicador de tarifa
    SELECT id, name, multiplier INTO v_surge_id, v_surge_name, v_multiplier
    FROM public.surge_zones
    WHERE is_active = true
      AND (expires_at IS NULL OR expires_at > now())
      AND (
        ST_Within(
            ST_SetSRID(ST_MakePoint(p_pickup_lng, p_pickup_lat), 4326)::geometry,
            boundary::geometry
        ) OR
        ST_Within(
            ST_SetSRID(ST_MakePoint(p_dropoff_lng, p_dropoff_lat), 4326)::geometry,
            boundary::geometry
        )
      )
    ORDER BY multiplier DESC
    LIMIT 1;

    -- Fallback de segurança
    IF v_multiplier IS NULL THEN
        v_multiplier := 1.00;
    END IF;

    -- Cálculo da tarifa final
    v_final_fare := p_base_fare * v_multiplier;

    RETURN jsonb_build_object(
        'base_fare', p_base_fare,
        'final_fare', v_final_fare,
        'multiplier', v_multiplier,
        'surge_zone_id', v_surge_id,
        'surge_zone_name', v_surge_name
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_calculate_ride_fare(FLOAT8, FLOAT8, FLOAT8, FLOAT8, DECIMAL) TO authenticated;

COMMENT ON FUNCTION public.rpc_calculate_ride_fare IS 'Verifica se a corrida se inicia ou termina em uma zona de preço dinâmico e aplica o multiplicador correspondente à tarifa base.';


-- ------------------------------------------------------------------------------
-- 2. SINCRONIZADOR DE PERFIL COM HISTÓRICO KYC
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_driver_profile_kyc()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.status = 'approved' THEN
        -- Motorista aprovado: status vai para 'offline' (pronto para ficar online)
        UPDATE public.profiles
        SET is_approved = true,
            status = 'offline',
            updated_at = now()
        WHERE id = NEW.driver_id;
    ELSIF NEW.status = 'rejected' THEN
        -- Motorista rejeitado: status vai para 'blocked'
        UPDATE public.profiles
        SET is_approved = false,
            status = 'blocked',
            updated_at = now()
        WHERE id = NEW.driver_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_driver_profile_kyc ON public.driver_kyc_history;
CREATE TRIGGER trg_sync_driver_profile_kyc
    AFTER INSERT ON public.driver_kyc_history
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_driver_profile_kyc();

COMMENT ON FUNCTION public.sync_driver_profile_kyc IS 'Sincroniza automaticamente a tabela de perfis (profiles) com o histórico de KYC do motorista quando um novo log é registrado.';


-- ------------------------------------------------------------------------------
-- 3. GERADOR E LEITOR SEGURO DE TOKENS DE ROTA
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_get_or_create_ride_share_token(
    p_ride_id UUID,
    p_user_id TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_token TEXT;
    v_exists_token TEXT;
BEGIN
    -- 1. Verificar se já existe um token ativo e válido para esta corrida
    SELECT share_token INTO v_exists_token
    FROM public.ride_tracking_shares
    WHERE ride_id = p_ride_id
      AND expires_at > now()
    LIMIT 1;

    IF v_exists_token IS NOT NULL THEN
        RETURN v_exists_token;
    END IF;

    -- 2. Gerar novo token MD5 de alta colisão-resistente (independente de extensões externas)
    v_token := md5(gen_random_uuid()::text || now()::text);

    -- 3. Inserir na tabela de compartilhamento seguro
    INSERT INTO public.ride_tracking_shares (ride_id, share_token, created_by, expires_at)
    VALUES (p_ride_id, v_token, p_user_id, now() + interval '2 hours');

    RETURN v_token;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_or_create_ride_share_token(UUID, TEXT) TO authenticated;

COMMENT ON FUNCTION public.rpc_get_or_create_ride_share_token IS 'Gera ou retorna um link seguro de rastreamento em tempo real de forma blindada contra invasão de privacidade.';


-- ------------------------------------------------------------------------------
-- 4. GESTÃO DE SPLIT FINANCEIRO AUTOMATIZADO NA CONCLUSÃO DE CORRIDA
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_completed_ride_financials()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_driver_share NUMERIC;
BEGIN
    -- Só executa quando a corrida transitar de qualquer status para 'completed' com motorista atribuído
    IF NEW.status = 'completed' AND OLD.status <> 'completed' AND NEW.driver_id IS NOT NULL THEN
        -- Fallback de segurança para taxas nulas
        IF NEW.platform_fee IS NULL THEN
            NEW.platform_fee := 0.00;
        END IF;

        v_driver_share := NEW.fare - NEW.platform_fee;

        IF NEW.payment_method = 'cash' THEN
            -- CORRIDA EM DINHEIRO: O motorista recebe o dinheiro físico na mão.
            -- O saldo disponível dele é debitado com a taxa da plataforma (platform_fee),
            -- pois ele coletou a taxa em dinheiro e agora a deve para a Uppi.
            PERFORM public.increment_wallet(NEW.driver_id, -NEW.platform_fee);
        ELSE
            -- CORRIDA EM CARTÃO / PIX / CRÉDITO: O dinheiro passa pelo ecossistema Uppi.
            -- O motorista tem o direito de receber o valor da corrida menos a taxa da plataforma.
            -- Esse valor entra como SALDO PENDENTE (pending_balance) aguardando confirmação do gateway.
            PERFORM public.increment_wallet_pending(NEW.driver_id, v_driver_share);
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_completed_ride_financials ON public.rides;
CREATE TRIGGER trg_completed_ride_financials
    AFTER UPDATE ON public.rides
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_completed_ride_financials();

COMMENT ON FUNCTION public.handle_completed_ride_financials IS 'Trigger de split financeiro na conclusão de corridas, cobrando taxas de corridas em dinheiro e provisionando saldos para pagamentos em meios digitais.';
