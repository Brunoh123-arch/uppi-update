-- ==============================================================================
-- BLINDAGEM FINANCEIRA INTEGRADA — ECOSSISTEMA UPPI
-- Adicionando Saldo Pendente (pending_balance) para evitar fraudes de saques/PIX
-- ==============================================================================

-- 1. Adicionar coluna pending_balance na tabela public.wallets
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'wallets' 
          AND column_name = 'pending_balance'
    ) THEN
        ALTER TABLE public.wallets ADD COLUMN pending_balance NUMERIC(12,2) DEFAULT 0.00 NOT NULL;
        COMMENT ON COLUMN public.wallets.pending_balance IS 'Saldo de corridas finalizadas aguardando compensação/confirmação do gateway de pagamento.';
    END IF;
END $$;

-- 2. RPC para incrementar o saldo pendente (chamada na conclusão da corrida)
CREATE OR REPLACE FUNCTION public.increment_wallet_pending(
  target_user_id TEXT,
  amount_to_add NUMERIC
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Cria wallet se não existir
  INSERT INTO public.wallets (user_id, balance, pending_balance)
  VALUES (target_user_id, 0.00, 0.00)
  ON CONFLICT (user_id) DO NOTHING;

  -- Atualiza o saldo pendente atomicamente
  UPDATE public.wallets
  SET pending_balance = pending_balance + amount_to_add,
      updated_at = now()
  WHERE user_id = target_user_id;
END;
$$;

-- 3. RPC para confirmar/compensar saldo pendente para saldo disponível (chamada pelo Webhook de sucesso de pagamento)
CREATE OR REPLACE FUNCTION public.confirm_pending_wallet_balance(
  target_user_id TEXT,
  amount_to_confirm NUMERIC
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Cria wallet se não existir
  INSERT INTO public.wallets (user_id, balance, pending_balance)
  VALUES (target_user_id, 0.00, 0.00)
  ON CONFLICT (user_id) DO NOTHING;

  -- Remove do saldo pendente e adiciona no saldo disponível (balance)
  UPDATE public.wallets
  SET pending_balance = CASE 
                          WHEN pending_balance - amount_to_confirm < 0 THEN 0.00 
                          ELSE pending_balance - amount_to_confirm 
                        END,
      balance = balance + amount_to_confirm,
      updated_at = now()
  WHERE user_id = target_user_id;
END;
$$;

-- 4. RPC para cancelar saldo pendente (chamada em caso de falha definitiva de pagamento ou recusa do cartão)
CREATE OR REPLACE FUNCTION public.cancel_pending_wallet_balance(
  target_user_id TEXT,
  amount_to_cancel NUMERIC
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Cria wallet se não existir
  INSERT INTO public.wallets (user_id, balance, pending_balance)
  VALUES (target_user_id, 0.00, 0.00)
  ON CONFLICT (user_id) DO NOTHING;

  -- Deduz do saldo pendente
  UPDATE public.wallets
  SET pending_balance = CASE 
                          WHEN pending_balance - amount_to_cancel < 0 THEN 0.00 
                          ELSE pending_balance - amount_to_cancel 
                        END,
      updated_at = now()
  WHERE user_id = target_user_id;
END;
$$;

-- Garantir permissões de execução para autenticados
GRANT EXECUTE ON FUNCTION public.increment_wallet_pending TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_pending_wallet_balance TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_pending_wallet_balance TO authenticated;

COMMENT ON FUNCTION public.increment_wallet_pending(TEXT, NUMERIC) IS 'Incrementa o saldo pendente de corridas ainda sob compensação financeira.';
COMMENT ON FUNCTION public.confirm_pending_wallet_balance(TEXT, NUMERIC) IS 'Transfere o saldo do estado pendente para o saldo real/disponível de forma atômica após webhook de confirmação do gateway.';
COMMENT ON FUNCTION public.cancel_pending_wallet_balance(TEXT, NUMERIC) IS 'Deduze o saldo pendente se o pagamento for rejeitado definitivamente.';
