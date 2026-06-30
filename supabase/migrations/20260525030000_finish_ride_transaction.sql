-- Migration: finish_ride database transaction function
-- Resolves finish-order lack of atomic ACID transactions and prevents data inconsistencies.

CREATE OR REPLACE FUNCTION public.finish_ride(
    p_ride_id uuid,
    p_driver_id text,
    p_cash_amount numeric
) RETURNS jsonb SECURITY DEFINER AS $$
DECLARE
    v_ride record;
    v_driver_profile record;
    v_commission_percent numeric := 0;
    v_commission_row record;
    v_commission_amt numeric;
    v_platform_fee numeric;
    v_driver_earning numeric;
    v_balance_change numeric;
    v_already_finished boolean;
    v_is_cash_ride boolean;
    v_deduct_amount numeric;
    v_rider_fcm_token text;
    v_original_fare numeric;
    v_fare_amount numeric;
BEGIN
    -- 1. Check if already finished
    SELECT EXISTS (
        SELECT 1 FROM public.driver_earnings WHERE ride_id = p_ride_id
    ) INTO v_already_finished;

    IF v_already_finished THEN
        RETURN jsonb_build_object(
            'success', true,
            'status', 'waiting_for_review',
            'message', 'Esta corrida já foi finalizada e paga anteriormente.'
        );
    END IF;

    -- 2. Fetch ride details (lock row for write)
    SELECT * FROM public.rides 
    WHERE id = p_ride_id AND driver_id = p_driver_id
    FOR UPDATE INTO v_ride;

    IF v_ride IS NULL THEN
        RAISE EXCEPTION 'Corrida não encontrada ou não pertence a você';
    END IF;

    IF v_ride.status NOT IN ('started', 'in_progress', 'completed') THEN
        RAISE EXCEPTION 'Corrida precisa estar em andamento ou recém-concluída para finalizar';
    END IF;

    v_original_fare := COALESCE(v_ride.original_fare, 0);
    IF v_original_fare = 0 THEN
        v_fare_amount := COALESCE(v_ride.fare, 0);
    ELSE
        v_fare_amount := v_original_fare;
    END IF;

    -- 3. Fetch driver commission percentage
    SELECT commission_percentage, commission_exempt_until 
    FROM public.profiles 
    WHERE id = p_driver_id 
    INTO v_driver_profile;

    IF v_driver_profile.commission_percentage IS NOT NULL THEN
        v_commission_percent := v_driver_profile.commission_percentage;
    ELSE
        -- Fetch global commission rate
        SELECT value FROM public.app_settings 
        WHERE key = 'commission_rate' 
        INTO v_commission_row;
        
        IF v_commission_row IS NOT NULL THEN
            v_commission_percent := COALESCE(v_commission_row.value::numeric, 15.0);
        END IF;
    END IF;

    -- Verify exemption
    IF v_driver_profile.commission_exempt_until IS NOT NULL THEN
        IF v_driver_profile.commission_exempt_until > NOW() THEN
            v_commission_percent := 0;
        END IF;
    END IF;

    v_commission_amt := ROUND((v_fare_amount * v_commission_percent / 100.0), 2);
    v_platform_fee := v_commission_amt;
    v_driver_earning := v_fare_amount - v_commission_amt;

    -- 4. Calculate balance change for driver
    IF p_cash_amount >= v_fare_amount THEN
        v_balance_change := -v_commission_amt; -- Only deduct commission since cash is physically held
        v_is_cash_ride := true;
    ELSE
        v_balance_change := v_driver_earning - p_cash_amount;
        v_is_cash_ride := false;
    END IF;

    -- 5. Update driver wallet (UPSERT wallet if it does not exist)
    INSERT INTO public.wallets (user_id, balance, pending_balance, created_at, updated_at)
    VALUES (p_driver_id, v_balance_change, 0, NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE 
    SET balance = public.wallets.balance + EXCLUDED.balance,
        updated_at = NOW();

    -- 6. Insert wallet transactions for driver
    IF NOT v_is_cash_ride THEN
        INSERT INTO public.wallet_transactions (user_id, amount, type, description, ride_id, status)
        VALUES (p_driver_id, v_fare_amount, 'ride_fare', 'Corrida #' || SUBSTRING(p_ride_id::text, 1, 8) || ' (' || COALESCE(v_ride.payment_method, 'unknown') || ')', p_ride_id, 'completed');
    END IF;

    IF v_commission_amt > 0 THEN
        INSERT INTO public.wallet_transactions (user_id, amount, type, description, ride_id, status)
        VALUES (p_driver_id, -v_commission_amt, 'commission', 'Comissão ' || v_commission_percent || '% - Corrida #' || SUBSTRING(p_ride_id::text, 1, 8) || CASE WHEN v_is_cash_ride THEN ' (dinheiro)' ELSE '' END, p_ride_id, 'completed');
    END IF;

    -- 7. Insert driver earnings
    INSERT INTO public.driver_earnings (driver_id, ride_id, gross_amount, commission_pct, commission_amt, platform_commission, net_amount, payment_method)
    VALUES (p_driver_id, p_ride_id, v_fare_amount, v_commission_percent, v_commission_amt, v_platform_fee, v_driver_earning, COALESCE(v_ride.payment_method, 'unknown'));

    -- 8. Digital payment: deduct from rider
    IF p_cash_amount < COALESCE(v_ride.fare, 0) AND v_ride.payment_method <> 'cash' THEN
        v_deduct_amount := COALESCE(v_ride.fare, 0) - p_cash_amount;
        
        -- Deduct from rider wallet (UPSERT wallet if it does not exist)
        INSERT INTO public.wallets (user_id, balance, pending_balance, created_at, updated_at)
        VALUES (v_ride.rider_id, -v_deduct_amount, 0, NOW(), NOW())
        ON CONFLICT (user_id) DO UPDATE 
        SET balance = public.wallets.balance + EXCLUDED.balance,
            updated_at = NOW();

        INSERT INTO public.wallet_transactions (user_id, amount, type, description, ride_id, status)
        VALUES (v_ride.rider_id, -v_deduct_amount, 'ride_fare', 'Pagamento corrida #' || SUBSTRING(p_ride_id::text, 1, 8), p_ride_id, 'completed');
    END IF;

    -- 9. Update ride status
    UPDATE public.rides 
    SET status = 'waiting_for_review',
        platform_fee = v_platform_fee,
        commission = v_platform_fee,
        finished_at = NOW()
    WHERE id = p_ride_id;

    -- 10. Bring driver back online
    UPDATE public.driver_locations 
    SET status = 'online', updated_at = NOW()
    WHERE driver_id = p_driver_id;

    UPDATE public.profiles 
    SET status = 'online'
    WHERE id = p_driver_id;

    -- 11. Insert activity log
    INSERT INTO public.ride_activities (ride_id, type, actor_id)
    VALUES (p_ride_id, 'finished', p_driver_id);

    -- 12. Fetch rider FCM token for pushing notification
    SELECT fcm_token FROM public.profiles 
    WHERE id = v_ride.rider_id 
    INTO v_rider_fcm_token;

    RETURN jsonb_build_object(
        'success', true,
        'status', 'waiting_for_review',
        'fare', v_fare_amount,
        'commission', v_commission_amt,
        'commission_percent', v_commission_percent,
        'driver_earning', v_driver_earning,
        'rider_id', v_ride.rider_id,
        'rider_fcm_token', v_rider_fcm_token
    );
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.finish_ride(uuid, text, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finish_ride(uuid, text, numeric) TO service_role;
