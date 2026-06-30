-- ==============================================================================
-- MIGRAÇÃO: Controle de Solicitações de Saque (payout_requests) e Triggers de Saldo
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.payout_requests (
    id                  UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    driver_id           TEXT REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    payout_account_id   UUID REFERENCES public.payout_accounts(id) ON DELETE CASCADE NOT NULL,
    amount              NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    status              VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'processed')),
    rejection_reason    TEXT,
    processed_at        TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.payout_requests ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------------------------
-- POLÍTICAS RLS (payout_requests)
-- ------------------------------------------------------------------------------
DROP POLICY IF EXISTS "Drivers can view their own payout requests" ON public.payout_requests;
CREATE POLICY "Drivers can view their own payout requests" ON public.payout_requests
    FOR SELECT TO authenticated USING (
        auth.uid()::text = driver_id OR 
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

DROP POLICY IF EXISTS "Drivers can insert their own pending payout requests" ON public.payout_requests;
CREATE POLICY "Drivers can insert their own pending payout requests" ON public.payout_requests
    FOR INSERT TO authenticated WITH CHECK (
        auth.uid()::text = driver_id AND status = 'pending'
    );

DROP POLICY IF EXISTS "Admins can manage all payout requests" ON public.payout_requests;
CREATE POLICY "Admins can manage all payout requests" ON public.payout_requests
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

-- ------------------------------------------------------------------------------
-- TRIGGERS DE PROVISIONAMENTO E CONTROLE DE SALDO
-- ------------------------------------------------------------------------------

-- 1. Trigger executada ANTES de inserir uma nova solicitação (valida e retém saldo)
CREATE OR REPLACE FUNCTION public.handle_payout_request_insert()
RETURNS TRIGGER AS $$
DECLARE
    v_balance NUMERIC(12,2);
BEGIN
    -- Obter o saldo disponível atual do motorista
    SELECT balance INTO v_balance 
    FROM public.wallets 
    WHERE user_id = NEW.driver_id;
    
    IF v_balance IS NULL OR v_balance < NEW.amount THEN
        RAISE EXCEPTION 'Saldo insuficiente para realizar este saque. Saldo disponível: R$ %', COALESCE(v_balance, 0.00);
    END IF;

    -- Deduzir o valor solicitado do saldo da carteira (evita double spending)
    UPDATE public.wallets 
    SET balance = balance - NEW.amount,
        updated_at = now()
    WHERE user_id = NEW.driver_id;

    -- Inserir a transação pendente no extrato financeiro (ledger)
    INSERT INTO public.wallet_transactions (user_id, amount, transaction_type, type, status, description)
    VALUES (NEW.driver_id, -NEW.amount, 'withdraw', 'withdraw', 'pending', 'Solicitação de Saque (Pix)');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_payout_request_insert ON public.payout_requests;
CREATE TRIGGER trg_payout_request_insert
    BEFORE INSERT ON public.payout_requests
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_payout_request_insert();


-- 2. Trigger executada APÓS atualizar a solicitação (estorna ou confirma)
CREATE OR REPLACE FUNCTION public.handle_payout_request_update()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status = 'pending' AND NEW.status = 'rejected' THEN
        -- Saque rejeitado: devolve o valor retido para o saldo disponível da carteira
        UPDATE public.wallets 
        SET balance = balance + NEW.amount,
            updated_at = now()
        WHERE user_id = NEW.driver_id;

        -- Atualiza a transação correspondente no extrato como rejeitada
        UPDATE public.wallet_transactions
        SET status = 'rejected',
            description = 'Saque Rejeitado: ' || COALESCE(NEW.rejection_reason, 'Dados incorretos')
        WHERE user_id = NEW.driver_id 
          AND amount = -NEW.amount 
          AND transaction_type = 'withdraw'
          AND status = 'pending';

    ELSIF OLD.status = 'pending' AND NEW.status = 'processed' THEN
        -- Saque processado com sucesso: confirma a transação
        UPDATE public.wallet_transactions
        SET status = 'processed',
            description = 'Saque Processado (Pix)'
        WHERE user_id = NEW.driver_id 
          AND amount = -NEW.amount 
          AND transaction_type = 'withdraw'
          AND status = 'pending';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_payout_request_update ON public.payout_requests;
CREATE TRIGGER trg_payout_request_update
    AFTER UPDATE ON public.payout_requests
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_payout_request_update();


-- ------------------------------------------------------------------------------
-- HABILITAR REALTIME
-- ------------------------------------------------------------------------------
BEGIN;
  ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public.payout_requests;
  ALTER PUBLICATION supabase_realtime ADD TABLE public.payout_requests;
COMMIT;
