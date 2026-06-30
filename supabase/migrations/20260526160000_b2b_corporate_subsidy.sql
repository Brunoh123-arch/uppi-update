-- Migration: B2B Split Payment and Partner Subsidy System (Pilar 26)
-- Target Date: 2026-05-26 16:00:00

-- 1. Create table public.corporate_accounts
CREATE TABLE IF NOT EXISTS public.corporate_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_name TEXT NOT NULL UNIQUE,
    credit_limit NUMERIC(10,2) DEFAULT 0.00,
    balance NUMERIC(10,2) DEFAULT 0.00,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Create table public.corporate_vouchers
CREATE TABLE IF NOT EXISTS public.corporate_vouchers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    corporate_id UUID REFERENCES public.corporate_accounts(id) ON DELETE CASCADE,
    code TEXT NOT NULL UNIQUE,
    subsidy_flat NUMERIC(10,2) NOT NULL CHECK (subsidy_flat > 0),
    max_uses_per_rider INT DEFAULT 1,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Create table public.corporate_transactions (ledger transaction log)
CREATE TABLE IF NOT EXISTS public.corporate_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    corporate_id UUID REFERENCES public.corporate_accounts(id) ON DELETE CASCADE,
    amount NUMERIC(10,2) NOT NULL,
    type TEXT NOT NULL,
    description TEXT,
    ride_id UUID REFERENCES public.rides(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 4. Enable RLS and Policies for B2B Tables
ALTER TABLE public.corporate_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.corporate_vouchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.corporate_transactions ENABLE ROW LEVEL SECURITY;

-- Read policies for authenticated users
DROP POLICY IF EXISTS "allow_select_corporate_accounts_for_authenticated" ON public.corporate_accounts;
CREATE POLICY "allow_select_corporate_accounts_for_authenticated"
    ON public.corporate_accounts
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "allow_select_corporate_vouchers_for_authenticated" ON public.corporate_vouchers;
CREATE POLICY "allow_select_corporate_vouchers_for_authenticated"
    ON public.corporate_vouchers
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "allow_select_corporate_transactions_for_authenticated" ON public.corporate_transactions;
CREATE POLICY "allow_select_corporate_transactions_for_authenticated"
    ON public.corporate_transactions
    FOR SELECT TO authenticated USING (true);

-- Full control policies for admins
DROP POLICY IF EXISTS "allow_admin_manage_corporate_accounts" ON public.corporate_accounts;
CREATE POLICY "allow_admin_manage_corporate_accounts"
    ON public.corporate_accounts
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

DROP POLICY IF EXISTS "allow_admin_manage_corporate_vouchers" ON public.corporate_vouchers;
CREATE POLICY "allow_admin_manage_corporate_vouchers"
    ON public.corporate_vouchers
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

DROP POLICY IF EXISTS "allow_admin_manage_corporate_transactions" ON public.corporate_transactions;
CREATE POLICY "allow_admin_manage_corporate_transactions"
    ON public.corporate_transactions
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

-- 5. Rides Schema Update
ALTER TABLE public.rides
    ADD COLUMN IF NOT EXISTS payment_subsidy_amount NUMERIC(10,2) DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS payment_rider_amount NUMERIC(10,2) DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS corporate_voucher_id UUID REFERENCES public.corporate_vouchers(id);

COMMENT ON COLUMN public.rides.payment_subsidy_amount IS 'Subsidized part paid by the B2B corporate partner.';
COMMENT ON COLUMN public.rides.payment_rider_amount IS 'Residual part paid by the passenger.';
COMMENT ON COLUMN public.rides.corporate_voucher_id IS 'Reference to the B2B corporate voucher used for this ride split payment.';

-- 6. Seed corporate partner data
INSERT INTO public.corporate_accounts (company_name, credit_limit, balance, is_active)
VALUES ('Comércio Parceiro Uppi', 10000.00, 5000.00, true)
ON CONFLICT (company_name) DO NOTHING;

INSERT INTO public.corporate_vouchers (corporate_id, code, subsidy_flat, max_uses_per_rider, is_active)
SELECT id, 'UPPIPARCEIRO10', 10.00, 1, true
FROM public.corporate_accounts
WHERE company_name = 'Comércio Parceiro Uppi'
ON CONFLICT (code) DO NOTHING;

-- 7. Define/Override the finish_ride function supporting split transactions
CREATE OR REPLACE FUNCTION public.finish_ride(
    p_ride_id uuid,
    p_driver_id text,
    p_cash_amount numeric,
    p_toll_amount numeric DEFAULT 0,
    p_actual_distance numeric DEFAULT NULL
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
    -- Pedágio
    v_toll numeric;
    -- Recálculo de rota
    v_service record;
    v_estimated_distance numeric;
    v_recalculated_fare numeric;
    v_distance_km numeric;
    v_duration_min numeric;
    v_surge_multiplier numeric := 1.0;
    v_surge_row record;
    -- B2B Split
    v_subsidy_amount numeric := 0.00;
    v_rider_amount numeric := 0.00;
    v_voucher_flat numeric;
    v_corp_id uuid;
BEGIN
    -- 0. Sanitizar pedágio (máx R$ 30,00)
    v_toll := LEAST(GREATEST(COALESCE(p_toll_amount, 0), 0), 30.00);

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

    -- ─── RECÁLCULO POR DESVIO DE ROTA ───────────────────────────────────
    v_estimated_distance := COALESCE(v_ride.distance, v_ride.distance_meters, 0);

    IF p_actual_distance IS NOT NULL AND p_actual_distance > 0 AND v_estimated_distance > 0 THEN
        -- Gravar distância real
        UPDATE public.rides
        SET actual_distance = p_actual_distance
        WHERE id = p_ride_id;

        -- Verificar se desvio excede 15%
        IF p_actual_distance > (v_estimated_distance * 1.15) THEN
            -- Buscar config de serviço para recalcular
            SELECT s.base_fare, s.per_km_fare, s.per_minute_fare, s.minimum_fare
            INTO v_service
            FROM public.services s
            WHERE s.id = v_ride.service_id
              OR s.id = v_ride.service_type;

            IF v_service IS NOT NULL THEN
                v_distance_km := p_actual_distance / 1000.0;
                v_duration_min := COALESCE(v_ride.duration, v_ride.duration_seconds, 0) / 60.0;

                -- Buscar surge multiplier global
                SELECT value INTO v_surge_row
                FROM public.app_settings
                WHERE key = 'global_surge_multiplier';

                IF v_surge_row IS NOT NULL THEN
                    v_surge_multiplier := COALESCE(v_surge_row.value::numeric, 1.0);
                END IF;

                v_recalculated_fare := (
                    COALESCE(v_service.base_fare, 5.0) +
                    (v_distance_km * COALESCE(v_service.per_km_fare, 2.0)) +
                    (v_duration_min * COALESCE(v_service.per_minute_fare, 0.5))
                ) * v_surge_multiplier;

                IF v_recalculated_fare < COALESCE(v_service.minimum_fare, 7.0) THEN
                    v_recalculated_fare := COALESCE(v_service.minimum_fare, 7.0);
                END IF;

                v_recalculated_fare := ROUND(v_recalculated_fare, 2);

                -- Salvar tarifa anterior e aplicar nova
                UPDATE public.rides
                SET original_fare = fare,
                    fare = v_recalculated_fare
                WHERE id = p_ride_id;

                -- Recarregar dados da corrida com tarifa atualizada
                SELECT * FROM public.rides
                WHERE id = p_ride_id
                FOR UPDATE INTO v_ride;
            END IF;
        END IF;
    END IF;
    -- ─── FIM RECÁLCULO ──────────────────────────────────────────────────

    v_original_fare := COALESCE(v_ride.original_fare, 0);
    IF v_original_fare = 0 THEN
        v_fare_amount := COALESCE(v_ride.fare, 0);
    ELSE
        -- Se houve recálculo, usar a fare atualizada (já contém o novo valor)
        v_fare_amount := COALESCE(v_ride.fare, 0);
    END IF;

    -- ─── B2B SPLIT RECALCULATION OR RETRIEVAL ──────────────────────────
    IF v_ride.corporate_voucher_id IS NOT NULL THEN
        SELECT cv.subsidy_flat, cv.corporate_id INTO v_voucher_flat, v_corp_id
        FROM public.corporate_vouchers cv
        WHERE cv.id = v_ride.corporate_voucher_id;

        IF v_voucher_flat IS NOT NULL THEN
            v_subsidy_amount := LEAST(v_voucher_flat, v_fare_amount);
            v_rider_amount := v_fare_amount - v_subsidy_amount;

            -- Update the split values in the database for the ride to reflect actual final fare
            UPDATE public.rides
            SET payment_subsidy_amount = v_subsidy_amount,
                payment_rider_amount = v_rider_amount
            WHERE id = p_ride_id;
        ELSE
            v_subsidy_amount := COALESCE(v_ride.payment_subsidy_amount, 0.00);
            v_rider_amount := COALESCE(v_ride.payment_rider_amount, v_fare_amount);
        END IF;
    ELSE
        v_subsidy_amount := COALESCE(v_ride.payment_subsidy_amount, 0.00);
        v_rider_amount := COALESCE(v_ride.payment_rider_amount, v_fare_amount);
    END IF;
    -- ─── END B2B SPLIT ─────────────────────────────────────────────────

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

    -- 20% or other platform commission on GROSS fare (v_fare_amount represents gross fare)
    v_commission_amt := ROUND((v_fare_amount * v_commission_percent / 100.0), 2);
    v_platform_fee := v_commission_amt;
    v_driver_earning := v_fare_amount - v_commission_amt;

    -- 4. Calculate balance change for driver (including 100% of tip_incentive)
    IF p_cash_amount >= v_rider_amount THEN
        -- If passenger paid their residual cash portion (or it was cash ride)
        v_balance_change := v_driver_earning + COALESCE(v_ride.tip_incentive, 0) - p_cash_amount;
        v_is_cash_ride := (p_cash_amount >= v_fare_amount); -- Only fully cash ride if cash covers gross fare
    ELSE
        v_balance_change := v_driver_earning + COALESCE(v_ride.tip_incentive, 0) - p_cash_amount;
        v_is_cash_ride := false;
    END IF;

    -- 5. Update driver wallet (UPSERT wallet if it does not exist)
    INSERT INTO public.wallets (user_id, balance, pending_balance, created_at, updated_at)
    VALUES (p_driver_id, v_balance_change, 0, NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE 
    SET balance = public.wallets.balance + EXCLUDED.balance,
        updated_at = NOW();

    -- 6. Insert wallet transactions for driver
    -- Driver always gets credited for the ride fare (gross fare if not cash ride)
    IF NOT v_is_cash_ride THEN
        INSERT INTO public.wallet_transactions (user_id, amount, type, description, ride_id, status)
        VALUES (p_driver_id, v_fare_amount, 'ride_fare', 'Corrida #' || SUBSTRING(p_ride_id::text, 1, 8) || ' (' || COALESCE(v_ride.payment_method, 'unknown') || ')', p_ride_id, 'completed');
    END IF;

    IF v_commission_amt > 0 THEN
        INSERT INTO public.wallet_transactions (user_id, amount, type, description, ride_id, status)
        VALUES (p_driver_id, -v_commission_amt, 'commission', 'Comissão ' || v_commission_percent || '% - Corrida #' || SUBSTRING(p_ride_id::text, 1, 8) || CASE WHEN v_is_cash_ride THEN ' (dinheiro)' ELSE '' END, p_ride_id, 'completed');
    END IF;

    -- Uppi Flex pre-ride tip incentive for driver (100% repassed to driver's wallet)
    IF COALESCE(v_ride.tip_incentive, 0) > 0 THEN
        INSERT INTO public.wallet_transactions (user_id, amount, type, description, ride_id, status)
        VALUES (p_driver_id, v_ride.tip_incentive, 'tip_incentive', 'Incentivo Uppi Flex - Corrida #' || SUBSTRING(p_ride_id::text, 1, 8), p_ride_id, 'completed');
    END IF;

    -- If partial cash was paid but driver credited with gross fare, we deduct the cash held from driver's digital wallet log to match balance!
    -- This keeps driver's wallet log perfectly auditable!
    IF NOT v_is_cash_ride AND p_cash_amount > 0 THEN
        INSERT INTO public.wallet_transactions (user_id, amount, type, description, ride_id, status)
        VALUES (p_driver_id, -p_cash_amount, 'cash_held', 'Valor retido em dinheiro - Corrida #' || SUBSTRING(p_ride_id::text, 1, 8), p_ride_id, 'completed');
    END IF;

    -- 7. Insert driver earnings
    INSERT INTO public.driver_earnings (driver_id, ride_id, gross_amount, commission_pct, commission_amt, platform_commission, net_amount, payment_method)
    VALUES (p_driver_id, p_ride_id, v_fare_amount, v_commission_percent, v_commission_amt, v_platform_fee, v_driver_earning, COALESCE(v_ride.payment_method, 'unknown'));

    -- 8. Digital payment: deduct only payment_rider_amount from rider's wallet
    IF p_cash_amount < v_rider_amount AND v_ride.payment_method <> 'cash' THEN
        v_deduct_amount := v_rider_amount - p_cash_amount;
        
        -- Deduct from rider wallet (UPSERT wallet if it does not exist)
        INSERT INTO public.wallets (user_id, balance, pending_balance, created_at, updated_at)
        VALUES (v_ride.rider_id, -v_deduct_amount, 0, NOW(), NOW())
        ON CONFLICT (user_id) DO UPDATE 
        SET balance = public.wallets.balance + EXCLUDED.balance,
            updated_at = NOW();

        INSERT INTO public.wallet_transactions (user_id, amount, type, description, ride_id, status)
        VALUES (v_ride.rider_id, -v_deduct_amount, 'ride_fare', 'Pagamento corrida #' || SUBSTRING(p_ride_id::text, 1, 8), p_ride_id, 'completed');
    END IF;

    -- Also debit the tip_incentive from the rider's wallet if paid digitally
    IF COALESCE(v_ride.tip_incentive, 0) > 0 AND v_ride.payment_method <> 'cash' THEN
        INSERT INTO public.wallets (user_id, balance, pending_balance, created_at, updated_at)
        VALUES (v_ride.rider_id, -v_ride.tip_incentive, 0, NOW(), NOW())
        ON CONFLICT (user_id) DO UPDATE 
        SET balance = public.wallets.balance + EXCLUDED.balance,
            updated_at = NOW();

        INSERT INTO public.wallet_transactions (user_id, amount, type, description, ride_id, status)
        VALUES (v_ride.rider_id, -v_ride.tip_incentive, 'tip_incentive', 'Incentivo Uppi Flex - Corrida #' || SUBSTRING(p_ride_id::text, 1, 8), p_ride_id, 'completed');
    END IF;

    -- ─── 8b. B2B SUBSIDY PAYMENT: Debit from B2B partner account ────────
    IF v_subsidy_amount > 0 AND v_corp_id IS NOT NULL THEN
        -- Debit from B2B partner account
        UPDATE public.corporate_accounts
        SET balance = balance - v_subsidy_amount
        WHERE id = v_corp_id;

        -- Insert B2B transaction record
        INSERT INTO public.corporate_transactions (corporate_id, amount, type, description, ride_id)
        VALUES (
            v_corp_id, 
            -v_subsidy_amount, 
            'b2b_subsidy', 
            'Subsídio B2B - Corrida #' || SUBSTRING(p_ride_id::text, 1, 8), 
            p_ride_id
        );
    END IF;

    -- ─── 8c. PEDÁGIO: Split financeiro rider → driver ────────────────────
    IF v_toll > 0 THEN
        -- Atualizar toll_amount na corrida
        UPDATE public.rides SET toll_amount = v_toll WHERE id = p_ride_id;

        -- Debitar passageiro
        INSERT INTO public.wallets (user_id, balance, pending_balance, created_at, updated_at)
        VALUES (v_ride.rider_id, -v_toll, 0, NOW(), NOW())
        ON CONFLICT (user_id) DO UPDATE
        SET balance = public.wallets.balance + EXCLUDED.balance,
            updated_at = NOW();

        INSERT INTO public.wallet_transactions (user_id, amount, type, description, ride_id, status)
        VALUES (v_ride.rider_id, -v_toll, 'toll_fee',
                'Pedágio - Corrida #' || SUBSTRING(p_ride_id::text, 1, 8),
                p_ride_id, 'completed');

        -- Creditar motorista
        INSERT INTO public.wallets (user_id, balance, pending_balance, created_at, updated_at)
        VALUES (p_driver_id, v_toll, 0, NOW(), NOW())
        ON CONFLICT (user_id) DO UPDATE
        SET balance = public.wallets.balance + EXCLUDED.balance,
            updated_at = NOW();

        INSERT INTO public.wallet_transactions (user_id, amount, type, description, ride_id, status)
        VALUES (p_driver_id, v_toll, 'toll_fee',
                'Reembolso pedágio - Corrida #' || SUBSTRING(p_ride_id::text, 1, 8),
                p_ride_id, 'completed');
    END IF;
    -- ─── FIM PEDÁGIO ────────────────────────────────────────────────────

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
        'rider_fcm_token', v_rider_fcm_token,
        'toll_amount', v_toll,
        'fare_recalculated', (p_actual_distance IS NOT NULL AND v_ride.original_fare IS NOT NULL AND v_ride.original_fare > 0),
        'payment_subsidy_amount', v_subsidy_amount,
        'payment_rider_amount', v_rider_amount
    );
END;
$$ LANGUAGE plpgsql;

-- Grant permissions explicitly
GRANT EXECUTE ON FUNCTION public.finish_ride(uuid, text, numeric, numeric, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finish_ride(uuid, text, numeric, numeric, numeric) TO service_role;
