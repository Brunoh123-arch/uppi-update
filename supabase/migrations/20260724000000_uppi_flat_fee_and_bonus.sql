-- Migration: Configurar modelo de taxa fixa Uppi (R$ 1.50 pós-corrida) e Saldo Bônus no Cadastro (R$ 20.00)

-- 1. Atualizar ou inserir configurações de taxa na app_settings
INSERT INTO public.app_settings (key, value)
VALUES 
    ('fee_mode', 'flat_per_ride'),
    ('flat_fee_amount', '1.50'),
    ('commission_rate', '0'),
    ('platform_fee_percent', '0'),
    ('driver_welcome_bonus', '20.00')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- 2. Atualizar ou criar função de gatilho para injetar R$ 20.00 de Saldo Bônus no cadastro de motorista
CREATE OR REPLACE FUNCTION public.handle_new_driver_wallet_bonus()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.role = 'driver' AND (OLD IS NULL OR OLD.role IS DISTINCT FROM 'driver') THEN
        -- Se a carteira estiver com saldo zero, injeta os R$ 20,00 de saldo de boas-vindas
        IF COALESCE(NEW.wallet_balance, 0) = 0 THEN
            NEW.wallet_balance := 20.00;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Criar ou recriar a trigger na tabela profiles
DROP TRIGGER IF EXISTS trg_new_driver_wallet_bonus ON public.profiles;
CREATE TRIGGER trg_new_driver_wallet_bonus
    BEFORE INSERT OR UPDATE OF role ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_driver_wallet_bonus();

-- 4. Função auxiliar para aplicar dedução da taxa fixa Uppi (R$ 1.50) na carteira do motorista
CREATE OR REPLACE FUNCTION public.deduct_uppi_flat_fee(
    p_driver_id text,
    p_ride_id uuid,
    p_fee_amount numeric DEFAULT 1.50
) RETURNS numeric AS $$
DECLARE
    v_driver_uuid uuid;
    v_current_balance numeric := 0;
    v_actual_deduct numeric := 0;
BEGIN
    v_driver_uuid := p_driver_id::uuid;

    -- Seleciona e trava o perfil do motorista
    SELECT wallet_balance INTO v_current_balance
    FROM public.profiles
    WHERE id = v_driver_uuid
    FOR UPDATE;

    v_actual_deduct := LEAST(COALESCE(v_current_balance, 0), p_fee_amount);

    -- Atualiza saldo da carteira na tabela profiles
    UPDATE public.profiles
    SET wallet_balance = GREATEST(0, COALESCE(wallet_balance, 0) - p_fee_amount)
    WHERE id = v_driver_uuid;

    -- Atualiza ou insere na tabela wallets
    INSERT INTO public.wallets (user_id, balance, updated_at)
    VALUES (v_driver_uuid, -p_fee_amount, NOW())
    ON CONFLICT (user_id) DO UPDATE
    SET balance = GREATEST(0, public.wallets.balance - p_fee_amount),
        updated_at = NOW();

    -- Registra transação no histórico
    INSERT INTO public.wallet_transactions (user_id, amount, type, description, ride_id, status)
    VALUES (
        v_driver_uuid,
        -p_fee_amount,
        'uppi_flat_fee',
        'Taxa Fixa Uppi - Corrida #' || SUBSTRING(p_ride_id::text, 1, 8),
        p_ride_id,
        'completed'
    );

    RETURN p_fee_amount;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
