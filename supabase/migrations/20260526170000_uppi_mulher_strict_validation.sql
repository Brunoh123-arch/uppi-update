-- Migration: Strict Gender Match and Safety Trava (Uppi Mulher - Pilar 21)
-- Date: 2026-05-26 17:00:00

-- 1. Update assign_driver_to_ride RPC to strictly validate gender before driver assignment
CREATE OR REPLACE FUNCTION public.assign_driver_to_ride(
    p_ride_id UUID,
    p_driver_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_status TEXT;
    v_gender_req TEXT;
    v_driver_gender TEXT;
    v_driver_verified BOOLEAN;
BEGIN
    -- 1. Lock the ride row to prevent race conditions
    SELECT status INTO v_status
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    -- 2. Check if the ride exists
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Corrida não encontrada (ID: %)', p_ride_id;
    END IF;

    -- 3. Check if the ride is still requested or active for assignment
    IF v_status <> 'requested' AND v_status <> 'searching' THEN
        RAISE EXCEPTION 'A corrida não está mais disponível (status atual: %)', v_status;
    END IF;

    -- 4. Strict Gender Requirement Validation
    SELECT s.gender_required INTO v_gender_req
    FROM public.rides r
    LEFT JOIN public.services s ON (s.id = r.service_id OR s.name = r.service_type)
    WHERE r.id = p_ride_id;

    IF v_gender_req IS NOT NULL THEN
        SELECT gender, gender_verified INTO v_driver_gender, v_driver_verified
        FROM public.profiles
        WHERE id = p_driver_id;

        IF v_driver_gender IS NULL OR v_driver_gender <> v_gender_req OR COALESCE(v_driver_verified, FALSE) = FALSE THEN
            RAISE EXCEPTION 'Categoria restrita: motorista não atende aos requisitos de gênero verificado (%) para este serviço', v_gender_req;
        END IF;
    END IF;

    -- 5. Update the ride
    UPDATE public.rides
    SET driver_id = p_driver_id,
        status = 'accepted',
        updated_at = now()
    WHERE id = p_ride_id;
END;
$$;

COMMENT ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) IS 'Atribui um motorista a uma corrida com verificação estrita de gênero verificado (Uppi Mulher) e controle transacional de concorrência.';

-- 2. Create strict BEFORE INSERT trigger on ride_offers for final database safety layer
CREATE OR REPLACE FUNCTION public.fn_validate_ride_offer_gender()
RETURNS TRIGGER AS $$
DECLARE
    v_gender_req TEXT;
    v_driver_gender TEXT;
    v_driver_verified BOOLEAN;
BEGIN
    -- Fetch gender requirement from service associated with the ride
    SELECT s.gender_required INTO v_gender_req
    FROM public.rides r
    LEFT JOIN public.services s ON (s.id = r.service_id OR s.name = r.service_type)
    WHERE r.id = NEW.ride_id;

    -- If no restriction, let it pass
    IF v_gender_req IS NULL THEN
        RETURN NEW;
    END IF;

    -- Fetch driver gender details
    SELECT gender, gender_verified INTO v_driver_gender, v_driver_verified
    FROM public.profiles
    WHERE id = NEW.driver_id;

    -- Validate compatibility
    IF v_driver_gender IS NULL OR v_driver_gender <> v_gender_req OR COALESCE(v_driver_verified, FALSE) = FALSE THEN
        RAISE EXCEPTION 'Ameaça de Segurança: Motorista % não atende aos critérios de gênero exigidos (%) para a corrida %', NEW.driver_id, v_gender_req, NEW.ride_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tg_validate_ride_offer_gender ON public.ride_offers;

CREATE TRIGGER tg_validate_ride_offer_gender
BEFORE INSERT ON public.ride_offers
FOR EACH ROW
EXECUTE FUNCTION public.fn_validate_ride_offer_gender();

COMMENT ON TRIGGER tg_validate_ride_offer_gender ON public.ride_offers IS 'Garante no nível do banco de dados que ofertas de corrida nunca sejam enviadas a motoristas de gênero incompatível ou não verificado.';
