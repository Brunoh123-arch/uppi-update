-- ==============================================================================
-- MIGRAÇÃO: Zonas de Perigo, Pedágio e Recálculo por Desvio de Rota
-- 1. Tabela danger_zones (geofencing PostGIS de áreas de risco)
-- 2. Colunas auxiliares em rides (is_danger_zone, actual_distance, etc.)
-- 3. Trigger check_ride_danger_zone (rotula corridas em áreas de risco)
-- 4. Trigger lock_cash_ride_danger_zone_night (bloqueia dinheiro à noite)
-- 5. Refatoração de finish_ride para pedágio e recálculo por desvio
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. TABELA: Zonas de Perigo (Geofencing de Segurança Física)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.danger_zones (
    id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name        TEXT NOT NULL,
    description TEXT,
    boundary    GEOGRAPHY(POLYGON) NOT NULL,  -- Cerca virtual PostGIS
    severity    TEXT DEFAULT 'high' CHECK (severity IN ('low', 'medium', 'high')),
    is_active   BOOLEAN DEFAULT true,
    created_at  TIMESTAMPTZ DEFAULT timezone('utc', now()),
    updated_at  TIMESTAMPTZ DEFAULT timezone('utc', now())
);

CREATE INDEX IF NOT EXISTS idx_danger_zones_active
    ON public.danger_zones (is_active)
    WHERE is_active = true;

-- RLS: Qualquer autenticado pode LER zonas ativas. Apenas admins gerenciam.
ALTER TABLE public.danger_zones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_select_active_danger_zones" ON public.danger_zones;
CREATE POLICY "allow_select_active_danger_zones" ON public.danger_zones
    FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS "allow_admin_manage_danger_zones" ON public.danger_zones;
CREATE POLICY "allow_admin_manage_danger_zones" ON public.danger_zones
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

COMMENT ON TABLE public.danger_zones IS
    'Zonas de perigo mapeadas pela equipe Uppi. Usadas para alertar motoristas e bloquear dinheiro em horário noturno.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. COLUNAS AUXILIARES EM RIDES
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.rides
    ADD COLUMN IF NOT EXISTS is_danger_zone    BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS danger_zone_name  TEXT,
    ADD COLUMN IF NOT EXISTS actual_distance   NUMERIC(12, 2),
    ADD COLUMN IF NOT EXISTS actual_duration   NUMERIC(12, 2);

COMMENT ON COLUMN public.rides.is_danger_zone IS
    'TRUE se pickup ou dropoff cai dentro de uma danger_zone ativa. Rotulado automaticamente por trigger.';
COMMENT ON COLUMN public.rides.danger_zone_name IS
    'Nome da zona de perigo detectada (para exibir no app do motorista).';
COMMENT ON COLUMN public.rides.actual_distance IS
    'Distância real percorrida em metros (enviada pelo motorista ao finalizar). Usada para recálculo de tarifa por desvio.';
COMMENT ON COLUMN public.rides.actual_duration IS
    'Duração real da corrida em segundos (enviada pelo motorista ao finalizar).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. TRIGGER: Rotular corridas em áreas de risco automaticamente
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_check_ride_danger_zone()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_zone_name TEXT;
BEGIN
    -- Verificar se pickup_location ou dropoff_location cai em uma danger_zone ativa
    SELECT dz.name INTO v_zone_name
    FROM public.danger_zones dz
    WHERE dz.is_active = true
      AND (
          ST_Within(
              NEW.pickup_location::geometry,
              dz.boundary::geometry
          )
          OR
          ST_Within(
              NEW.dropoff_location::geometry,
              dz.boundary::geometry
          )
      )
    ORDER BY dz.severity DESC  -- Prioriza a zona mais perigosa
    LIMIT 1;

    IF v_zone_name IS NOT NULL THEN
        NEW.is_danger_zone   := true;
        NEW.danger_zone_name := v_zone_name;
    ELSE
        NEW.is_danger_zone   := false;
        NEW.danger_zone_name := NULL;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_ride_danger_zone ON public.rides;
CREATE TRIGGER trg_check_ride_danger_zone
    BEFORE INSERT OR UPDATE OF pickup_location, dropoff_location
    ON public.rides
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_check_ride_danger_zone();

COMMENT ON FUNCTION public.fn_check_ride_danger_zone IS
    'Verifica se a corrida se inicia ou termina em uma zona de perigo mapeada e rotula automaticamente.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. TRIGGER: Bloquear corridas em dinheiro em zonas de risco à noite
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_lock_cash_danger_zone_night()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_local_hour INTEGER;
BEGIN
    -- Só aplica se for pagamento em dinheiro E em zona de perigo
    IF NEW.payment_method = 'cash' AND NEW.is_danger_zone = true THEN
        -- Calcular hora local no fuso de Belém/Brasília (UTC-3)
        v_local_hour := EXTRACT(HOUR FROM (now() AT TIME ZONE 'America/Belem'));

        -- Bloquear entre 22:00 e 05:59 (período noturno)
        IF v_local_hour >= 22 OR v_local_hour < 6 THEN
            RAISE EXCEPTION
                'Para garantir a segurança física dos nossos parceiros, viagens em áreas de risco no período noturno (22h às 06h) são restritas a pagamentos eletrônicos (Pix ou Saldo Digital). Por favor, altere seu meio de pagamento.'
                USING ERRCODE = 'P0001';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_lock_cash_danger_zone_night ON public.rides;
CREATE TRIGGER trg_lock_cash_danger_zone_night
    BEFORE INSERT ON public.rides
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_lock_cash_danger_zone_night();

COMMENT ON FUNCTION public.fn_lock_cash_danger_zone_night IS
    'Bloqueia criação de corridas em dinheiro em zonas de perigo durante o período noturno (22h-06h fuso Belém).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. REFATORAÇÃO: finish_ride com Pedágio e Recálculo por Desvio
-- ─────────────────────────────────────────────────────────────────────────────
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

    -- ─── 8b. PEDÁGIO: Split financeiro rider → driver ────────────────────
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
        'fare_recalculated', (p_actual_distance IS NOT NULL AND v_ride.original_fare IS NOT NULL AND v_ride.original_fare > 0)
    );
END;
$$ LANGUAGE plpgsql;

-- Manter grants existentes
GRANT EXECUTE ON FUNCTION public.finish_ride(uuid, text, numeric, numeric, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finish_ride(uuid, text, numeric, numeric, numeric) TO service_role;

-- Habilitar Realtime para danger_zones (admin panel pode gerenciar em tempo real)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_rel pr 
        JOIN pg_publication p ON p.oid = pr.prpubid 
        JOIN pg_class c ON c.oid = pr.prrelid 
        WHERE p.pubname = 'supabase_realtime' 
          AND c.relname = 'danger_zones'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.danger_zones;
    END IF;
END $$;
