-- ==============================================================================
-- MIGRAÇÃO FASE 3B — UPPI BRASIL
-- Tabelas: payment_gateways, payment_methods, payout_methods, payout_accounts, driver_documents
-- Execute no SQL Editor do Supabase: https://supabase.com/dashboard/project/vunzdjxjzqpbwgcqwahp/sql
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. GATEWAYS DE PAGAMENTO (configurados pelo admin)
-- Substitui a coleção Firestore: 'paymentGateways'
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payment_gateways (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    title TEXT NOT NULL,
    logo_url TEXT,
    is_active BOOLEAN DEFAULT true,
    external_url TEXT,        -- URL de checkout externo (ex: Mercado Pago)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

ALTER TABLE public.payment_gateways ENABLE ROW LEVEL SECURITY;

-- Qualquer usuário autenticado pode ver os gateways disponíveis
CREATE POLICY "Ver gateways ativos" ON public.payment_gateways
    FOR SELECT TO authenticated USING (is_active = true);

-- ------------------------------------------------------------------------------
-- 2. MÉTODOS DE PAGAMENTO SALVOS DO MOTORISTA
-- Substitui a subcoleção Firestore: 'drivers/{uid}/paymentMethods'
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payment_methods (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    driver_id TEXT REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    title TEXT,                  -- Nome do cartão ou método
    last_four TEXT DEFAULT '0000',
    card_type TEXT DEFAULT 'unknown',
    is_default BOOLEAN DEFAULT false,
    is_enabled BOOLEAN DEFAULT true,
    gateway_id UUID REFERENCES public.payment_gateways(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

ALTER TABLE public.payment_methods ENABLE ROW LEVEL SECURITY;

-- Motorista vê apenas seus próprios métodos
CREATE POLICY "Ver próprios métodos de pagamento" ON public.payment_methods
    FOR SELECT USING (auth.uid()::text = driver_id);

CREATE POLICY "Inserir próprios métodos de pagamento" ON public.payment_methods
    FOR INSERT WITH CHECK (auth.uid()::text = driver_id);

CREATE POLICY "Atualizar próprios métodos de pagamento" ON public.payment_methods
    FOR UPDATE USING (auth.uid()::text = driver_id);

CREATE POLICY "Deletar próprios métodos de pagamento" ON public.payment_methods
    FOR DELETE USING (auth.uid()::text = driver_id);

-- ------------------------------------------------------------------------------
-- 3. MÉTODOS DE SAQUE DISPONÍVEIS (configurados pelo admin)
-- Substitui a coleção Firestore: 'payoutMethods'
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payout_methods (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    logo_url TEXT,
    external_url TEXT,           -- URL de onboarding/cadastro do método de saque
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

ALTER TABLE public.payout_methods ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Ver métodos de saque ativos" ON public.payout_methods
    FOR SELECT TO authenticated USING (is_active = true);

-- ------------------------------------------------------------------------------
-- 4. CONTAS DE SAQUE DO MOTORISTA
-- Substitui a coleção Firestore: 'payoutAccounts' (where driverId == uid)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payout_accounts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    driver_id TEXT REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    payout_method_id UUID REFERENCES public.payout_methods(id),
    account_number TEXT,
    routing_number TEXT,
    account_holder_name TEXT,
    bank_name TEXT,
    is_default BOOLEAN DEFAULT false,
    account_holder_country TEXT,
    account_holder_city TEXT,
    account_holder_state TEXT,
    account_holder_address TEXT,
    account_holder_phone TEXT,
    account_holder_zip TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

ALTER TABLE public.payout_accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Ver próprias contas de saque" ON public.payout_accounts
    FOR SELECT USING (auth.uid()::text = driver_id);

CREATE POLICY "Inserir próprias contas de saque" ON public.payout_accounts
    FOR INSERT WITH CHECK (auth.uid()::text = driver_id);

CREATE POLICY "Atualizar próprias contas de saque" ON public.payout_accounts
    FOR UPDATE USING (auth.uid()::text = driver_id);

CREATE POLICY "Deletar próprias contas de saque" ON public.payout_accounts
    FOR DELETE USING (auth.uid()::text = driver_id);

-- Função para garantir apenas uma conta padrão por motorista
CREATE OR REPLACE FUNCTION unset_other_default_payout_accounts()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_default = true THEN
        UPDATE public.payout_accounts
        SET is_default = false
        WHERE driver_id = NEW.driver_id AND id <> NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER enforce_single_default_payout_account
    AFTER INSERT OR UPDATE ON public.payout_accounts
    FOR EACH ROW WHEN (NEW.is_default = true)
    EXECUTE PROCEDURE unset_other_default_payout_accounts();

-- ------------------------------------------------------------------------------
-- 5. DOCUMENTOS DO MOTORISTA
-- Substitui o campo 'documents' dentro do doc 'drivers/{uid}' no Firestore
-- Armazena como coluna JSONB em profiles (já existente) OU tabela separada.
-- Usamos JSONB em profiles.vehicle_details['documents'] para ser compatível
-- com o que já foi implementado. Aqui adicionamos a coluna 'documents' separada.
-- ------------------------------------------------------------------------------
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS documents JSONB DEFAULT '[]'::jsonb;

-- ==============================================================================
-- FIM DA MIGRAÇÃO FASE 3B
-- ==============================================================================
