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
