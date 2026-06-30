-- Migration: 20260525050000_finances_and_kyc_fixes.sql
-- 1. ALTER ASSIGN_DRIVER_TO_RIDE TO UPDATE ACCEPTED_AT
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
BEGIN
    -- [SEGURANÇA] Validar se o solicitante é de fato o motorista ou service_role
    IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR auth.uid()::text <> p_driver_id) THEN
        RAISE EXCEPTION 'Operação não autorizada. O motorista não corresponde ao usuário autenticado.';
    END IF;

    -- [SEGURANÇA] Bloquear linha da corrida para evitar conflitos concorrentes
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

    -- Atribuir o motorista à corrida, passar o status para 'accepted' e preencher accepted_at
    UPDATE public.rides
    SET driver_id = p_driver_id,
        status = 'accepted',
        accepted_at = now(),
        updated_at = now()
    WHERE id = p_ride_id;
END;
$$;

COMMENT ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) IS 'Atribui o motorista à corrida, marca a oferta como aceita, expira outras ofertas pendentes e define o momento do aceite. [Protegido via JWT e Validação de Oferta]';

-- 2. ALTER BADGE_DEFINITIONS TO ADD REWARD COLUMNS
ALTER TABLE public.badge_definitions ADD COLUMN IF NOT EXISTS reward_type TEXT DEFAULT NULL;
ALTER TABLE public.badge_definitions ADD COLUMN IF NOT EXISTS reward_amount NUMERIC(10,2) DEFAULT NULL;

-- Atualizar as conquistas padrão com as recompensas financeiras e isenções de comissão
UPDATE public.badge_definitions SET reward_type = 'walletBonus', reward_amount = 10.00 WHERE id = 'first_ride_driver';
UPDATE public.badge_definitions SET reward_type = 'walletBonus', reward_amount = 50.00 WHERE id = 'ten_rides_driver';
UPDATE public.badge_definitions SET reward_type = 'walletBonus', reward_amount = 100.00 WHERE id = 'fifty_rides_driver';
UPDATE public.badge_definitions SET reward_type = 'walletBonus', reward_amount = 250.00 WHERE id = 'hundred_rides_driver';
UPDATE public.badge_definitions SET reward_type = 'commissionExemption', reward_amount = 7.00 WHERE id = 'five_star_driver';
UPDATE public.badge_definitions SET reward_type = 'walletBonus', reward_amount = 5.00 WHERE id = 'first_ride_rider';
UPDATE public.badge_definitions SET reward_type = 'walletBonus', reward_amount = 15.00 WHERE id = 'ten_rides_rider';
UPDATE public.badge_definitions SET reward_type = 'walletBonus', reward_amount = 10.00 WHERE id = 'generous_tipper';
