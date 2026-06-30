-- Migration: Resetar saldos negativos e impedir que fiquem abaixo de zero
-- Decisão de negócio: Garantir que motoristas e passageiros nunca fiquem com saldo negativo.

-- 1. Resetar saldos negativos atuais na tabela public.wallets para 0.00
UPDATE public.wallets
SET balance = 0.00
WHERE balance < 0.00;

-- 2. Criar a função que impede que o saldo fique negativo, limitando a zero
CREATE OR REPLACE FUNCTION public.check_wallet_balance_limits()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.balance < 0.00 THEN
    NEW.balance := 0.00;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Adicionar gatilho BEFORE INSERT OR UPDATE na tabela public.wallets
DROP TRIGGER IF EXISTS wallets_prevent_negative_balance ON public.wallets;
CREATE TRIGGER wallets_prevent_negative_balance
BEFORE INSERT OR UPDATE ON public.wallets
FOR EACH ROW
EXECUTE FUNCTION public.check_wallet_balance_limits();

COMMENT ON FUNCTION public.check_wallet_balance_limits() IS 'Garante que o saldo da carteira digital nunca fique abaixo de zero, limitando qualquer redução para 0.00.';
