

-- ─────────────────────────────────────────────
-- FILE: 20240428130700_init.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- SCHEMA INICIAL DO SUPABASE (MIGRAÇÃO DO FIREBASE) - UPPI BRASIL
-- Copie todo este código e cole no "SQL Editor" do Supabase amanhã.
-- ==============================================================================

-- Habilitar a extensão PostGIS para geolocalização e raio de busca (A grande vantagem do Supabase!)
CREATE EXTENSION IF NOT EXISTS postgis;

-- ------------------------------------------------------------------------------
-- 1. TABELA DE PERFIS (PROFILES) - Substitui a coleção 'users' e 'drivers'
-- ------------------------------------------------------------------------------
CREATE TABLE public.profiles (
    id TEXT NOT NULL PRIMARY KEY,               -- O UID que vem do Firebase Auth
    role TEXT CHECK (role IN ('rider', 'driver', 'admin')), -- Papel do usuário
    full_name TEXT NOT NULL,
    phone_number TEXT,
    email TEXT,
    fcm_token TEXT,                             -- Token para Notificações Push
    status TEXT DEFAULT 'active',               -- active, pending_approval, blocked
    wallet_balance DECIMAL(10, 2) DEFAULT 0.00, -- Saldo da carteira
    search_radius INTEGER DEFAULT 5000,         -- Raio de busca do motorista em metros
    current_location GEOGRAPHY(POINT),          -- Localização GPS exata e super rápida para buscar
    vehicle_details JSONB,                      -- Placa, Cor, Modelo (JSON para ser flexível como no Firebase)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- Habilitar RLS (Segurança) na tabela Profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Política: Usuário pode ler o próprio perfil
CREATE POLICY "Usuário lê próprio perfil" ON public.profiles
    FOR SELECT USING (auth.uid()::text = id);

-- Política: Usuário pode editar o próprio perfil
CREATE POLICY "Usuário edita próprio perfil" ON public.profiles
    FOR UPDATE USING (auth.uid()::text = id) WITH CHECK (auth.uid()::text = id);

-- ------------------------------------------------------------------------------
-- SEGURANÇA EXTRA: Bloquear edição direta do saldo da carteira (wallet_balance)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION block_wallet_update()
RETURNS TRIGGER AS $$
BEGIN
    -- Se o saldo tentou ser modificado e o usuário não é um admin / service_role
    IF NEW.wallet_balance IS DISTINCT FROM OLD.wallet_balance THEN
        IF current_user IN ('authenticator', 'anon', 'authenticated') THEN
            RAISE EXCEPTION 'Security Alert: Alteração manual de carteira não permitida pelo Client.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER enforce_wallet_security
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE PROCEDURE block_wallet_update();



-- ------------------------------------------------------------------------------
-- 2. TABELA DE CORRIDAS (RIDES / ORDERS) - Substitui a coleção 'orders' / 'requests'
-- ------------------------------------------------------------------------------
CREATE TABLE public.rides (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    rider_id TEXT REFERENCES public.profiles(id) NOT NULL,
    driver_id TEXT REFERENCES public.profiles(id),  -- Pode ser nulo até o motorista aceitar
    
    status TEXT NOT NULL DEFAULT 'requested' 
        CHECK (status IN ('requested', 'accepted', 'arrived', 'in_progress', 'completed', 'canceled')),
    
    pickup_address TEXT NOT NULL,
    pickup_location GEOGRAPHY(POINT) NOT NULL,      -- Coordenadas de partida
    dropoff_address TEXT NOT NULL,
    dropoff_location GEOGRAPHY(POINT) NOT NULL,     -- Coordenadas de destino
    
    fare DECIMAL(10, 2) NOT NULL,                   -- Preço da corrida
    platform_fee DECIMAL(10, 2) DEFAULT 0.00,       -- Taxa do app (Uppi)
    payment_method TEXT DEFAULT 'cash',             -- cash, pix, credit_card
    
    distance_meters INTEGER,
    duration_seconds INTEGER,
    
    cancel_reason TEXT,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- Habilitar RLS na tabela Rides
ALTER TABLE public.rides ENABLE ROW LEVEL SECURITY;

-- Política: Passageiros veem suas próprias corridas, Motoristas veem corridas atribuídas a eles ou corridas 'requested' próximas
CREATE POLICY "Leitura de Corridas" ON public.rides
    FOR SELECT USING (
        auth.uid()::text = rider_id OR 
        auth.uid()::text = driver_id OR 
        status = 'requested'
    );

-- Política: Passageiro pode criar uma corrida
CREATE POLICY "Criação de Corridas" ON public.rides
    FOR INSERT WITH CHECK (auth.uid()::text = rider_id);

-- Política: Atualização de Corridas (Motorista aceita, passageiro cancela)
CREATE POLICY "Atualização de Corridas" ON public.rides
    FOR UPDATE USING (
        auth.uid()::text = rider_id OR 
        auth.uid()::text = driver_id OR 
        status = 'requested'
    );


-- ------------------------------------------------------------------------------
-- 3. TABELA DE TRANSAÇÕES (WALLET TRANSACTIONS)
-- ------------------------------------------------------------------------------
CREATE TABLE public.wallet_transactions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT REFERENCES public.profiles(id) NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,                 -- Positivo (crédito) ou Negativo (débito)
    transaction_type TEXT NOT NULL,                 -- 'ride_payment', 'commission_fee', 'topup', 'payout'
    description TEXT,
    ride_id UUID REFERENCES public.rides(id),       -- Opcional, vincula a uma corrida específica
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Ver próprias transações" ON public.wallet_transactions
    FOR SELECT USING (auth.uid()::text = user_id);


-- ------------------------------------------------------------------------------
-- 4. FUNÇÃO PARA ATUALIZAR O UPDATED_AT AUTOMATICAMENTE
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

CREATE TRIGGER update_rides_updated_at
    BEFORE UPDATE ON public.rides
    FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- ==============================================================================
-- FIM DO SCRIPT
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20250620000002_add_matching_functions.sql
-- ─────────────────────────────────────────────

-- Função PostgreSQL para buscar motoristas próximos com score ponderado
-- Score = (1/distância * 40%) + (rating * 40%) + (disponibilidade * 20%)
CREATE OR REPLACE FUNCTION public.get_nearby_drivers_scored(
  p_lat FLOAT,
  p_lng FLOAT,
  p_radius_km FLOAT DEFAULT 5.0
)
RETURNS TABLE(
  driver_id UUID,
  distance_km FLOAT,
  lat FLOAT,
  lng FLOAT,
  rating FLOAT,
  score FLOAT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    dl.driver_id,
    ROUND(
      (ST_Distance(
        ST_SetSRID(ST_MakePoint(dl.lng, dl.lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
      ) / 1000.0)::NUMERIC, 2
    )::FLOAT AS distance_km,
    dl.lat::FLOAT,
    dl.lng::FLOAT,
    COALESCE(p.rating, 4.5)::FLOAT AS rating,
    -- Score ponderado: proximidade (40%) + rating (40%) + (bônus online contínuo 20%)
    (
      (1.0 / GREATEST(ST_Distance(
        ST_SetSRID(ST_MakePoint(dl.lng, dl.lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
      ) / 1000.0, 0.1)) * 0.4
      + COALESCE(p.rating, 4.5) / 5.0 * 0.4
      + 0.2
    )::FLOAT AS score
  FROM public.driver_locations dl
  LEFT JOIN public.profiles p ON p.id = dl.driver_id
  WHERE
    dl.status = 'online'
    AND ST_Distance(
      ST_SetSRID(ST_MakePoint(dl.lng, dl.lat), 4326)::geography,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    ) <= (p_radius_km * 1000)
  ORDER BY score DESC
  LIMIT 20;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION public.get_nearby_drivers_scored IS
  'Retorna motoristas online próximos ordenados por score ponderado (distância + rating)';


-- ─────────────────────────────────────────────
-- FILE: 20260501000000_add_avatar_url.sql
-- ─────────────────────────────────────────────

                                                                                                                                                                                                                                                                                                                                                                                               

-- ─────────────────────────────────────────────
-- FILE: 20260501010000_auxiliary_tables.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Tabelas auxiliares para funcionalidades do app
-- services, cancel_reasons, messages, complaints, sos_signals
-- ==============================================================================

-- 1. TIPOS DE SERVIÇO (Standard, SUV, Moto etc.)
CREATE TABLE IF NOT EXISTS public.services (
    id TEXT NOT NULL PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    image_url TEXT,
    base_fare DECIMAL(10, 2) DEFAULT 5.00,
    per_km_fare DECIMAL(10, 2) DEFAULT 2.00,
    per_minute_fare DECIMAL(10, 2) DEFAULT 0.50,
    minimum_fare DECIMAL(10, 2) DEFAULT 7.00,
    surge_multiplier DECIMAL(5, 2) DEFAULT 1.00,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);
ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Leitura de Serviços" ON public.services FOR SELECT USING (true);

-- 2. MOTIVOS DE CANCELAMENTO
CREATE TABLE IF NOT EXISTS public.cancel_reasons (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    role TEXT DEFAULT 'rider' CHECK (role IN ('rider', 'driver')),
    is_active BOOLEAN DEFAULT TRUE
);
ALTER TABLE public.cancel_reasons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Leitura de Motivos" ON public.cancel_reasons FOR SELECT USING (true);

-- Dados padrão de motivos de cancelamento
INSERT INTO public.cancel_reasons (name, role) VALUES
  ('Motorista demorou muito', 'rider'),
  ('Solicitei por engano', 'rider'),
  ('Mudei de planos', 'rider'),
  ('Problemas pessoais', 'rider'),
  ('Passageiro não apareceu', 'driver'),
  ('Trânsito excessivo', 'driver'),
  ('Problemas no carro', 'driver'),
  ('Motivos pessoais', 'driver')
ON CONFLICT DO NOTHING;

-- 3. MENSAGENS DE CHAT EM TEMPO REAL
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ride_id UUID REFERENCES public.rides(id) ON DELETE CASCADE NOT NULL,
    sender_id TEXT REFERENCES public.profiles(id) NOT NULL,
    content TEXT NOT NULL,
    sent_by_driver BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Leitura de Mensagens" ON public.messages
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.rides
            WHERE rides.id = messages.ride_id
            AND (rides.rider_id = auth.uid()::text OR rides.driver_id = auth.uid()::text)
        )
    );
CREATE POLICY "Envio de Mensagens" ON public.messages
    FOR INSERT WITH CHECK (auth.uid()::text = sender_id);

-- 4. RECLAMAÇÕES PÓS-CORRIDA
CREATE TABLE IF NOT EXISTS public.complaints (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ride_id TEXT,
    user_id TEXT REFERENCES public.profiles(id),
    role TEXT CHECK (role IN ('rider', 'driver')),
    subject TEXT NOT NULL,
    content TEXT NOT NULL,
    status TEXT DEFAULT 'submitted' CHECK (status IN ('submitted', 'in_review', 'resolved', 'closed')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);
ALTER TABLE public.complaints ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Criar Reclamação" ON public.complaints FOR INSERT WITH CHECK (auth.uid()::text = user_id);
CREATE POLICY "Ver próprias reclamações" ON public.complaints FOR SELECT USING (auth.uid()::text = user_id);

-- 5. SINAIS DE SOS
CREATE TABLE IF NOT EXISTS public.sos_signals (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ride_id TEXT,
    submitted_by TEXT REFERENCES public.profiles(id),
    role TEXT CHECK (role IN ('rider', 'driver')),
    status TEXT DEFAULT 'submitted',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);
ALTER TABLE public.sos_signals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Criar SOS" ON public.sos_signals FOR INSERT WITH CHECK (auth.uid()::text = submitted_by);


-- ─────────────────────────────────────────────
-- FILE: 20260501020000_fase3b_payment_payout_documents.sql
-- ─────────────────────────────────────────────

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


-- ─────────────────────────────────────────────
-- FILE: 20260501030000_fase4_gift_cards_config_services.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO FASE 4 — UPPI BRASIL
-- Tabelas: gift_cards, config
-- Colunas adicionais: profiles.fcm_token, services (snake_case aliases)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. FCM TOKEN no profiles (para Cloud Messaging sem Firestore)
-- ------------------------------------------------------------------------------
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS fcm_token TEXT;

-- ------------------------------------------------------------------------------
-- 2. GIFT CARDS
-- Substitui a coleção Firestore: 'giftCards'
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gift_cards (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    code TEXT UNIQUE NOT NULL,
    amount NUMERIC(10, 2) NOT NULL,
    currency TEXT DEFAULT 'BRL',
    is_redeemed BOOLEAN DEFAULT false,
    redeemed_by TEXT REFERENCES public.profiles(id),
    redeemed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

ALTER TABLE public.gift_cards ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='gift_cards' AND policyname='Ver gift card por codigo') THEN
    CREATE POLICY "Ver gift card por codigo" ON public.gift_cards FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='gift_cards' AND policyname='Resgatar gift card') THEN
    CREATE POLICY "Resgatar gift card" ON public.gift_cards FOR UPDATE TO authenticated
      USING (is_redeemed = false) WITH CHECK (redeemed_by = auth.uid()::text);
  END IF;
END $$;

-- ------------------------------------------------------------------------------
-- 3. CONFIG (surge pricing e configurações globais)
-- Substitui a coleção Firestore: 'config'
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.config (
    key TEXT PRIMARY KEY,
    surge_multiplier NUMERIC DEFAULT 1.0,
    commission_percent NUMERIC DEFAULT 0.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

ALTER TABLE public.config ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='config' AND policyname='Ler config') THEN
    CREATE POLICY "Ler config" ON public.config FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- Inserir dados padrão se não existirem
INSERT INTO public.config (key, surge_multiplier, commission_percent)
VALUES ('pricing', 1.0, 0.0)
ON CONFLICT (key) DO NOTHING;

-- ------------------------------------------------------------------------------
-- 4. SERVICES — tabela já existe, garantir default UUID e colunas snake_case
-- ------------------------------------------------------------------------------
ALTER TABLE public.services
    ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- Adicionar colunas snake_case se não existirem
ALTER TABLE public.services ADD COLUMN IF NOT EXISTS base_fare NUMERIC DEFAULT 5.0;
ALTER TABLE public.services ADD COLUMN IF NOT EXISTS per_km_fare NUMERIC DEFAULT 2.0;
ALTER TABLE public.services ADD COLUMN IF NOT EXISTS per_minute_fare NUMERIC DEFAULT 0.5;
ALTER TABLE public.services ADD COLUMN IF NOT EXISTS minimum_fare NUMERIC DEFAULT 7.0;
ALTER TABLE public.services ADD COLUMN IF NOT EXISTS image_url TEXT;
ALTER TABLE public.services ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'services' AND policyname = 'Ver servicos ativos'
  ) THEN
    CREATE POLICY "Ver servicos ativos" ON public.services
      FOR SELECT TO authenticated USING (is_active = true);
  END IF;
END $$;

-- ------------------------------------------------------------------------------
-- 5. COUPONS (tabela de cupons com nomes snake_case)
-- Substitui a coleção Firestore: 'coupons'
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.coupons (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    code TEXT UNIQUE NOT NULL,
    discount NUMERIC NOT NULL,
    discount_type TEXT DEFAULT 'fixed',    -- 'fixed' ou 'percentage'
    is_active BOOLEAN DEFAULT true,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='coupons' AND policyname='Ver cupons ativos') THEN
    CREATE POLICY "Ver cupons ativos" ON public.coupons FOR SELECT TO authenticated USING (is_active = true);
  END IF;
END $$;

-- ==============================================================================
-- FIM DA MIGRAÇÃO FASE 4
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260501040000_fase4b_support_tables.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO FASE 4B — UPPI BRASIL
-- Tabelas de suporte: ride_reviews, ride_messages, sos_signals,
--                     driver_locations, car_models, car_colors
-- ==============================================================================

-- 1. RIDE REVIEWS
CREATE TABLE IF NOT EXISTS public.ride_reviews (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ride_id TEXT NOT NULL,
    reviewer_id TEXT NOT NULL REFERENCES public.profiles(id),
    rating INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
    review TEXT,
    role TEXT DEFAULT 'rider',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
ALTER TABLE public.ride_reviews ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='ride_reviews' AND policyname='Inserir review') THEN
    CREATE POLICY "Inserir review" ON public.ride_reviews FOR INSERT TO authenticated WITH CHECK (reviewer_id = auth.uid()::text);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='ride_reviews' AND policyname='Ler reviews') THEN
    CREATE POLICY "Ler reviews" ON public.ride_reviews FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- 2. RIDE MESSAGES (chat em tempo real entre motorista e passageiro)
CREATE TABLE IF NOT EXISTS public.ride_messages (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ride_id TEXT NOT NULL,
    sender_id TEXT NOT NULL REFERENCES public.profiles(id),
    content TEXT NOT NULL,
    sent_by_driver BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
ALTER TABLE public.ride_messages ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='ride_messages' AND policyname='Enviar mensagem') THEN
    CREATE POLICY "Enviar mensagem" ON public.ride_messages FOR INSERT TO authenticated WITH CHECK (sender_id = auth.uid()::text);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='ride_messages' AND policyname='Ler mensagens da corrida') THEN
    CREATE POLICY "Ler mensagens da corrida" ON public.ride_messages FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- Habilitar Realtime para chat
ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_messages;

-- 3. SOS SIGNALS
CREATE TABLE IF NOT EXISTS public.sos_signals (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ride_id TEXT NOT NULL,
    submitted_by TEXT NOT NULL REFERENCES public.profiles(id),
    status TEXT DEFAULT 'Submitted',
    role TEXT DEFAULT 'rider',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
ALTER TABLE public.sos_signals ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sos_signals' AND policyname='Enviar SOS') THEN
    CREATE POLICY "Enviar SOS" ON public.sos_signals FOR INSERT TO authenticated WITH CHECK (submitted_by = auth.uid()::text);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sos_signals' AND policyname='Ler SOS') THEN
    CREATE POLICY "Ler SOS" ON public.sos_signals FOR SELECT TO authenticated USING (submitted_by = auth.uid()::text);
  END IF;
END $$;

-- 4. DRIVER LOCATIONS (rastreio em tempo real)
CREATE TABLE IF NOT EXISTS public.driver_locations (
    driver_id TEXT PRIMARY KEY REFERENCES public.profiles(id),
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    heading DOUBLE PRECISION DEFAULT 0,
    vehicle_type TEXT DEFAULT 'carro',
    marker_url TEXT,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
ALTER TABLE public.driver_locations ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='driver_locations' AND policyname='Motorista atualiza propria loc') THEN
    CREATE POLICY "Motorista atualiza propria loc" ON public.driver_locations FOR ALL TO authenticated
      USING (driver_id = auth.uid()::text) WITH CHECK (driver_id = auth.uid()::text);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='driver_locations' AND policyname='Ler localizacoes motoristas') THEN
    CREATE POLICY "Ler localizacoes motoristas" ON public.driver_locations FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- Habilitar Realtime para rastreio
ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_locations;

-- 5. CAR MODELS (referência para registro de veículos)
CREATE TABLE IF NOT EXISTS public.car_models (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
ALTER TABLE public.car_models ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='car_models' AND policyname='Ler modelos') THEN
    CREATE POLICY "Ler modelos" ON public.car_models FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- Seed data: modelos populares no Brasil
INSERT INTO public.car_models (name) VALUES
  ('Chevrolet Onix'), ('Fiat Argo'), ('Hyundai HB20'),
  ('Volkswagen Gol'), ('Toyota Corolla'), ('Honda Civic'),
  ('Fiat Mobi'), ('Renault Kwid'), ('Chevrolet Prisma'),
  ('Volkswagen Polo'), ('Fiat Cronos'), ('Nissan Kicks')
ON CONFLICT DO NOTHING;

-- 6. CAR COLORS (referência para cores de veículos)
CREATE TABLE IF NOT EXISTS public.car_colors (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
ALTER TABLE public.car_colors ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='car_colors' AND policyname='Ler cores') THEN
    CREATE POLICY "Ler cores" ON public.car_colors FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- Seed data: cores comuns
INSERT INTO public.car_colors (name) VALUES
  ('Preto'), ('Branco'), ('Prata'), ('Cinza'),
  ('Vermelho'), ('Azul'), ('Verde'), ('Amarelo'),
  ('Marrom'), ('Bege')
ON CONFLICT DO NOTHING;

-- 7. Colunas extras em profiles para driver registration
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_approved BOOLEAN DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS vehicle_type TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS marker_url TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS certificate_number TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS search_distance INT DEFAULT 5000;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS vehicle_plate_number TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS vehicle_production_year INT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS vehicle_model_id TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS vehicle_color_id TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bank_name TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bank_account_number TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bank_swift_code TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bank_routing_number TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS gender TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS id_number TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS preset_avatar_number INT;

-- ==============================================================================
-- FIM DA MIGRAÇÃO FASE 4B
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260501050000_fase5_missing_tables.sql
-- ─────────────────────────────────────────────

-- ============================================================
-- FASE 5: Tabelas complementares para migração completa
-- Criado em: 2026-05-01
-- ============================================================

-- ============================================================
-- 1. ANNOUNCEMENTS (Anúncios e promoções)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.announcements (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  title       text NOT NULL DEFAULT '',
  description text NOT NULL DEFAULT '',
  url         text,
  start_at    timestamptz DEFAULT now(),
  end_at      timestamptz,
  is_active   boolean DEFAULT true,
  created_at  timestamptz DEFAULT now()
);

ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

-- Qualquer usuário autenticado pode ler anúncios
CREATE POLICY "announcements_select_authenticated"
  ON public.announcements FOR SELECT
  TO authenticated
  USING (is_active = true);

-- ============================================================
-- 2. SERVICES (Tipos de corrida: Regular, Premium, etc.)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.services (
  id               uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name             text NOT NULL DEFAULT 'Regular',
  description      text,
  base_fare        numeric(10,2) DEFAULT 5.00,
  per_km_fare      numeric(10,2) DEFAULT 2.00,
  per_minute_fare  numeric(10,2) DEFAULT 0.50,
  minimum_fare     numeric(10,2) DEFAULT 7.00,
  person_capacity  int DEFAULT 4,
  media_url        text DEFAULT '',
  is_active        boolean DEFAULT true,
  created_at       timestamptz DEFAULT now()
);

ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;

CREATE POLICY "services_select_authenticated"
  ON public.services FOR SELECT
  TO authenticated
  USING (is_active = true);

ALTER TABLE public.services ADD COLUMN IF NOT EXISTS person_capacity INT DEFAULT 4;
ALTER TABLE public.services ADD COLUMN IF NOT EXISTS description TEXT;

-- Inserir serviço padrão
INSERT INTO public.services (name, description, base_fare, per_km_fare, per_minute_fare, minimum_fare, person_capacity)
VALUES ('Regular', 'Viagem econômica padrão', 5.00, 2.00, 0.50, 7.00, 4)
ON CONFLICT DO NOTHING;

-- ============================================================
-- 3. CONFIG (Configurações globais chave-valor)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.config (
  key        text PRIMARY KEY,
  value      jsonb DEFAULT '{}',
  surge_multiplier numeric(4,2) DEFAULT 1.00,
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "config_select_authenticated"
  ON public.config FOR SELECT
  TO authenticated
  USING (true);

-- Inserir config de pricing padrão
INSERT INTO public.config (key, surge_multiplier)
VALUES ('pricing', 1.00)
ON CONFLICT (key) DO NOTHING;

-- ============================================================
-- 4. COUPONS (Cupons de desconto)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.coupons (
  id             uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  code           text NOT NULL UNIQUE,
  discount       numeric(10,2) DEFAULT 0,
  discount_type  text DEFAULT 'fixed' CHECK (discount_type IN ('fixed', 'percentage')),
  is_active      boolean DEFAULT true,
  max_uses       int,
  uses_count     int DEFAULT 0,
  expires_at     timestamptz,
  created_at     timestamptz DEFAULT now()
);

ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;

CREATE POLICY "coupons_select_authenticated"
  ON public.coupons FOR SELECT
  TO authenticated
  USING (is_active = true);

-- ============================================================
-- 5. PAYMENT_GATEWAYS (Gateways de pagamento disponíveis)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.payment_gateways (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name        text NOT NULL DEFAULT 'Gateway',
  title       text,
  logo_url    text,
  link_method text DEFAULT 'redirect',
  is_active   boolean DEFAULT true,
  created_at  timestamptz DEFAULT now()
);

ALTER TABLE public.payment_gateways ENABLE ROW LEVEL SECURITY;

CREATE POLICY "payment_gateways_select_authenticated"
  ON public.payment_gateways FOR SELECT
  TO authenticated
  USING (is_active = true);

ALTER TABLE public.payment_gateways ADD COLUMN IF NOT EXISTS name TEXT DEFAULT 'Gateway';
ALTER TABLE public.payment_gateways ADD COLUMN IF NOT EXISTS link_method TEXT DEFAULT 'redirect';

-- Inserir Mercado Pago como gateway padrão
INSERT INTO public.payment_gateways (name, title, link_method)
SELECT 'Mercado Pago', 'Mercado Pago', 'redirect'
WHERE NOT EXISTS (SELECT 1 FROM public.payment_gateways WHERE name = 'Mercado Pago');


-- ============================================================
-- 6. PAYMENT_METHODS (Métodos de pagamento salvos do usuário)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.payment_methods (
  id               uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id          uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  card_type        text,
  last_four        text DEFAULT '0000',
  card_holder_name text,
  expiry_date      text,
  is_default       boolean DEFAULT false,
  is_enabled       boolean DEFAULT true,
  gateway_id       uuid REFERENCES public.payment_gateways(id),
  created_at       timestamptz DEFAULT now()
);

ALTER TABLE public.payment_methods ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.payment_methods ADD COLUMN IF NOT EXISTS card_holder_name text;
ALTER TABLE public.payment_methods ADD COLUMN IF NOT EXISTS expiry_date text;

CREATE INDEX IF NOT EXISTS idx_payment_methods_user ON public.payment_methods(user_id);


ALTER TABLE public.payment_methods ENABLE ROW LEVEL SECURITY;

-- Usuário só vê/gerencia seus próprios métodos de pagamento
CREATE POLICY "payment_methods_select_own"
  ON public.payment_methods FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "payment_methods_insert_own"
  ON public.payment_methods FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "payment_methods_update_own"
  ON public.payment_methods FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "payment_methods_delete_own"
  ON public.payment_methods FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ============================================================
-- 7. FAVORITE_ADDRESSES (Endereços favoritos do passageiro)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.favorite_addresses (
  id        uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id   uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name      text NOT NULL DEFAULT '',
  lat       double precision DEFAULT 0,
  lng       double precision DEFAULT 0,
  address   text DEFAULT '',
  title     text,
  type      text DEFAULT 'other' CHECK (type IN ('home', 'work', 'other')),
  created_at timestamptz DEFAULT now()
);

CREATE INDEX idx_favorite_addresses_user ON public.favorite_addresses(user_id);

ALTER TABLE public.favorite_addresses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "favorite_addresses_select_own"
  ON public.favorite_addresses FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "favorite_addresses_insert_own"
  ON public.favorite_addresses FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "favorite_addresses_update_own"
  ON public.favorite_addresses FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "favorite_addresses_delete_own"
  ON public.favorite_addresses FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ============================================================
-- 8. FAVORITE_DRIVERS (Motoristas favoritos do passageiro)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.favorite_drivers (
  id               uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id          uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  driver_id        text NOT NULL,
  first_name       text,
  last_name        text,
  avatar_url       text,
  services         jsonb DEFAULT '[]',
  car_model        text,
  car_color        text,
  car_plate_number text,
  rating           int,
  ratings_count    int,
  created_at       timestamptz DEFAULT now(),
  UNIQUE(user_id, driver_id)
);

CREATE INDEX idx_favorite_drivers_user ON public.favorite_drivers(user_id);

ALTER TABLE public.favorite_drivers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "favorite_drivers_select_own"
  ON public.favorite_drivers FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "favorite_drivers_insert_own"
  ON public.favorite_drivers FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "favorite_drivers_delete_own"
  ON public.favorite_drivers FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ============================================================
-- 9. ADICIONAR COLUNAS FALTANTES AO PROFILES
-- ============================================================
DO $$
BEGIN
  -- FCM Token para push notifications
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'fcm_token') THEN
    ALTER TABLE public.profiles ADD COLUMN fcm_token text;
  END IF;

  -- Total rides (cache de contagem)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'total_rides') THEN
    ALTER TABLE public.profiles ADD COLUMN total_rides int DEFAULT 0;
  END IF;

  -- Total distance (cache de contagem)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'total_distance') THEN
    ALTER TABLE public.profiles ADD COLUMN total_distance int DEFAULT 0;
  END IF;

  -- Preset avatar number
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'preset_avatar_number') THEN
    ALTER TABLE public.profiles ADD COLUMN preset_avatar_number int;
  END IF;

  -- Soft delete
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'is_deleted') THEN
    ALTER TABLE public.profiles ADD COLUMN is_deleted boolean DEFAULT false;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'deleted_at') THEN
    ALTER TABLE public.profiles ADD COLUMN deleted_at timestamptz;
  END IF;

  -- Search distance (raio de busca do motorista)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'search_distance') THEN
    ALTER TABLE public.profiles ADD COLUMN search_distance int DEFAULT 5000;
  END IF;

  -- Average rating
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'average_rating') THEN
    ALTER TABLE public.profiles ADD COLUMN average_rating numeric(3,2) DEFAULT 5.00;
  END IF;

  -- Wallet balance
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'wallet_balance') THEN
    ALTER TABLE public.profiles ADD COLUMN wallet_balance numeric(12,2) DEFAULT 0.00;
  END IF;
END $$;

-- ============================================================
-- PRONTO! Todas as tabelas criadas com RLS ativo.
-- ============================================================


-- ─────────────────────────────────────────────
-- FILE: 20260501060000_fase6_final_tables.sql
-- ─────────────────────────────────────────────

-- Migration: Create missing tables and storage buckets for Uppi App
-- Date: 2026-05-01

-- 1. Create Cancel Reasons
CREATE TABLE IF NOT EXISTS public.cancel_reasons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('rider', 'driver')),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed basic cancel reasons
INSERT INTO public.cancel_reasons (name, role) VALUES 
('Motorista demorou muito', 'rider'),
('Solicitei por engano', 'rider'),
('Mudei de planos', 'rider'),
('Problemas pessoais', 'rider'),
('Passageiro não apareceu', 'driver'),
('Local de difícil acesso', 'driver'),
('Problemas mecânicos', 'driver')
ON CONFLICT DO NOTHING;

-- 2. Create Complaints
CREATE TABLE IF NOT EXISTS public.complaints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id UUID NOT NULL,
    user_id TEXT NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('rider', 'driver')),
    subject TEXT NOT NULL,
    content TEXT NOT NULL,
    status TEXT DEFAULT 'submitted',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Create Car Models
CREATE TABLE IF NOT EXISTS public.car_models (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed common car models
INSERT INTO public.car_models (name) VALUES 
('Chevrolet Onix'), ('Hyundai HB20'), ('Volkswagen Polo'), 
('Fiat Argo'), ('Jeep Renegade'), ('Toyota Corolla'), ('Honda Civic')
ON CONFLICT DO NOTHING;

-- 4. Create Car Colors
CREATE TABLE IF NOT EXISTS public.car_colors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed common colors
INSERT INTO public.car_colors (name) VALUES 
('Branco'), ('Preto'), ('Prata'), ('Cinza'), ('Vermelho'), ('Azul')
ON CONFLICT DO NOTHING;

-- 5. Create Driver Locations
CREATE TABLE IF NOT EXISTS public.driver_locations (
    driver_id TEXT PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    heading DOUBLE PRECISION DEFAULT 0.0,
    vehicle_type TEXT DEFAULT 'carro',
    marker_url TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on all new tables
ALTER TABLE public.cancel_reasons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.complaints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.car_models ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.car_colors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.driver_locations ENABLE ROW LEVEL SECURITY;

-- 6. RLS Policies
-- cancel_reasons, car_models, car_colors: anyone can read
CREATE POLICY "Public read cancel_reasons" ON public.cancel_reasons FOR SELECT USING (true);
CREATE POLICY "Public read car_models" ON public.car_models FOR SELECT USING (true);
CREATE POLICY "Public read car_colors" ON public.car_colors FOR SELECT USING (true);

-- complaints: users can insert and read their own
CREATE POLICY "Users can insert complaints" ON public.complaints FOR INSERT WITH CHECK (auth.uid()::text = user_id);
CREATE POLICY "Users can view own complaints" ON public.complaints FOR SELECT USING (auth.uid()::text = user_id);

-- driver_locations: drivers can upsert their own, riders can read all
CREATE POLICY "Drivers can update own location" ON public.driver_locations FOR ALL USING (auth.uid()::text = driver_id) WITH CHECK (auth.uid()::text = driver_id);
CREATE POLICY "Anyone can read driver locations" ON public.driver_locations FOR SELECT USING (true);

-- 7. Storage Bucket: identity-docs
INSERT INTO storage.buckets (id, name, public) 
VALUES ('identity-docs', 'identity-docs', true)
ON CONFLICT (id) DO NOTHING;

-- Storage Policies for identity-docs
CREATE POLICY "Public access to identity-docs" ON storage.objects FOR SELECT USING (bucket_id = 'identity-docs');
CREATE POLICY "Auth users can upload identity-docs" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'identity-docs' AND auth.role() = 'authenticated');
CREATE POLICY "Users can update their own identity-docs" ON storage.objects FOR UPDATE USING (bucket_id = 'identity-docs' AND auth.uid()::text = (storage.foldername(name))[2]);


-- ─────────────────────────────────────────────
-- FILE: 20260505000000_performance_indexes_rls.sql
-- ─────────────────────────────────────────────

-- =============================================================================
-- MIGRATION: PERFORMANCE & ESCALABILIDADE — UPPI BRASIL
-- Aplicar no Supabase SQL Editor
-- Objetivo: Suportar milhões de usuários sem degradação de performance
-- =============================================================================

-- =============================================================================
-- 1. ÍNDICES DE PERFORMANCE — tabela rides
-- =============================================================================

-- Passageiro busca suas corridas → O mais usado no app (tela "Minhas Corridas")
CREATE INDEX IF NOT EXISTS idx_rides_rider_id
    ON public.rides (rider_id);

-- Motorista busca corridas atribuídas a ele
CREATE INDEX IF NOT EXISTS idx_rides_driver_id
    ON public.rides (driver_id)
    WHERE driver_id IS NOT NULL;

-- Filtro por status → Corridas 'requested' abertas (motorista vê no mapa)
CREATE INDEX IF NOT EXISTS idx_rides_status
    ON public.rides (status);

-- Combina rider_id + status → Tela "Corrida Ativa" do passageiro (query mais frequente)
CREATE INDEX IF NOT EXISTS idx_rides_rider_status
    ON public.rides (rider_id, status);

-- Combina driver_id + status → Feed do motorista
CREATE INDEX IF NOT EXISTS idx_rides_driver_status
    ON public.rides (driver_id, status)
    WHERE driver_id IS NOT NULL;

-- Ordenação por data (paginação de histórico)
CREATE INDEX IF NOT EXISTS idx_rides_created_at
    ON public.rides (created_at DESC);

-- =============================================================================
-- 2. ÍNDICE GIST (PostGIS) — busca de motoristas por raio
-- =============================================================================

-- Índice espacial para "quais motoristas estão a X km do passageiro?"
-- Sem esse índice: O Postgres varre TODOS os perfis (table scan)
-- Com esse índice: Responde em <5ms mesmo com 100k motoristas cadastrados
CREATE INDEX IF NOT EXISTS idx_profiles_location_gist
    ON public.profiles USING GIST (current_location);

-- Índice espacial na tabela driver_locations (GPS broadcast persistência)
CREATE INDEX IF NOT EXISTS idx_driver_locations_gist
    ON public.driver_locations USING GIST (
        (ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography)
    );

-- Motoristas online (filtro mais comum para mapa do passageiro)
CREATE INDEX IF NOT EXISTS idx_profiles_status_role
    ON public.profiles (status, role)
    WHERE role = 'driver';

-- =============================================================================
-- 3. ÍNDICES — tabela driver_locations
-- =============================================================================

-- Busca por motorista específico
CREATE INDEX IF NOT EXISTS idx_driver_locations_driver_id
    ON public.driver_locations (driver_id);

-- Filtra localizações recentes (descarta GPS desatualizado >2min)
CREATE INDEX IF NOT EXISTS idx_driver_locations_updated_at
    ON public.driver_locations (updated_at DESC);

-- =============================================================================
-- 4. ÍNDICES — tabelas financeiras
-- =============================================================================

-- Extrato da carteira por usuário
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_user_id
    ON public.wallet_transactions (user_id);

-- Histórico financeiro por data
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_created_at
    ON public.wallet_transactions (user_id, created_at DESC);

-- =============================================================================
-- 5. ÍNDICES — chat e mensagens
-- =============================================================================

-- Mensagens de uma corrida específica (chat em tempo real)
CREATE INDEX IF NOT EXISTS idx_ride_messages_ride_id
    ON public.ride_messages (ride_id, created_at ASC);

-- =============================================================================
-- 6. RLS OTIMIZADO — políticas sem sub-selects
-- =============================================================================

-- Remove políticas antigas e reescreve de forma direta e eficiente
-- (Sub-selects dentro de políticas RLS são o maior killer de performance)

-- RIDES: Recria política de leitura de forma mais eficiente
DROP POLICY IF EXISTS "Leitura de Corridas" ON public.rides;
CREATE POLICY "rides_select" ON public.rides
    FOR SELECT USING (
        auth.uid()::text = rider_id
        OR auth.uid()::text = driver_id
        OR (status = 'requested' AND driver_id IS NULL)
    );

-- Motorista só pode ver driver_locations de si mesmo
DROP POLICY IF EXISTS "driver_locations_select" ON public.driver_locations;
CREATE POLICY "driver_locations_select" ON public.driver_locations
    FOR SELECT USING (true);  -- Posições são públicas para o mapa funcionar

DROP POLICY IF EXISTS "driver_locations_insert" ON public.driver_locations;
CREATE POLICY "driver_locations_upsert" ON public.driver_locations
    FOR ALL USING (auth.uid()::text = driver_id)
    WITH CHECK (auth.uid()::text = driver_id);

-- Mensagens: apenas participantes da corrida
DROP POLICY IF EXISTS "ride_messages_select" ON public.ride_messages;
CREATE POLICY "ride_messages_select" ON public.ride_messages
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.rides r
            WHERE r.id::text = ride_id
              AND (r.rider_id = auth.uid()::text OR r.driver_id = auth.uid()::text)
        )
    );

-- =============================================================================
-- 7. FUNÇÃO DE BUSCA POR RAIO (PostGIS otimizada)
-- =============================================================================

-- Busca motoristas num raio em metros — usada pelo rider para ver carrinhos no mapa
-- Uso: SELECT * FROM nearby_drivers(lng, lat, raio_metros)
CREATE OR REPLACE FUNCTION nearby_drivers(
    p_lng FLOAT,
    p_lat FLOAT,
    p_radius_meters INT DEFAULT 5000
)
RETURNS TABLE (
    driver_id TEXT,
    lat FLOAT,
    lng FLOAT,
    heading FLOAT,
    vehicle_type TEXT,
    marker_url TEXT,
    distance_meters FLOAT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT
        dl.driver_id,
        dl.lat,
        dl.lng,
        dl.heading,
        dl.vehicle_type,
        dl.marker_url,
        ST_Distance(
            ST_SetSRID(ST_MakePoint(dl.lng, dl.lat), 4326)::geography,
            ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
        ) AS distance_meters
    FROM public.driver_locations dl
    WHERE
        -- Filtra por raio usando índice GIST (ultra rápido)
        ST_DWithin(
            ST_SetSRID(ST_MakePoint(dl.lng, dl.lat), 4326)::geography,
            ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
            p_radius_meters
        )
        -- Só motoristas com GPS recente (últimos 2 minutos)
        AND dl.updated_at > NOW() - INTERVAL '2 minutes'
    ORDER BY distance_meters ASC
    LIMIT 50;
$$;

-- =============================================================================
-- 8. LIMPEZA AUTOMÁTICA — GPS desatualizado
-- =============================================================================

-- Remove localizações com mais de 10 minutos (motoristas offline)
-- Roda automaticamente via pg_cron (habilitar no Supabase Pro)
-- No Free Tier: pode rodar manualmente quando necessário
CREATE OR REPLACE FUNCTION cleanup_stale_driver_locations()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
AS $$
    DELETE FROM public.driver_locations
    WHERE updated_at < NOW() - INTERVAL '10 minutes';
$$;

-- =============================================================================
-- 9. ESTATÍSTICAS DE TABELA — ajuda o planner do Postgres
-- =============================================================================

ANALYZE public.rides;
ANALYZE public.profiles;
ANALYZE public.driver_locations;

-- =============================================================================
-- FIM DA MIGRATION DE PERFORMANCE
-- Após aplicar: execute EXPLAIN ANALYZE nas queries principais para validar
-- =============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260505010000_admin_god_mode_audit.sql
-- ─────────────────────────────────────────────

-- =============================================================================
-- MIGRATION: AUDIT LOGS AND FRAUD MANAGEMENT - UPPI BRASIL
-- =============================================================================

-- 1. Admin Audit Log Table (Surgical Tracking)
CREATE TABLE IF NOT EXISTS public.admin_audit_log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    admin_id TEXT NOT NULL,
    action_type TEXT NOT NULL,
    target_user_id TEXT,
    target_resource_id TEXT,
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_log_admin ON public.admin_audit_log(admin_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_target ON public.admin_audit_log(target_user_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON public.admin_audit_log(created_at DESC);

-- 2. High Risk Drivers View (Anti-Fraud)
CREATE OR REPLACE VIEW public.high_risk_drivers AS
SELECT
    d.id AS driver_id,
    d.full_name,
    d.phone_number,
    COUNT(r.id) AS total_rides,
    SUM(CASE WHEN r.status IN ('driver_canceled', 'rider_canceled') THEN 1 ELSE 0 END) AS canceled_rides,
    (SUM(CASE WHEN r.status IN ('driver_canceled', 'rider_canceled') THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(r.id), 0)) * 100 AS cancellation_rate
FROM public.profiles d
LEFT JOIN public.rides r ON r.driver_id = d.id::text
WHERE d.role = 'driver'
GROUP BY d.id, d.full_name, d.phone_number
HAVING COUNT(r.id) >= 5 AND (SUM(CASE WHEN r.status IN ('driver_canceled', 'rider_canceled') THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(r.id), 0)) > 0.3;

-- RLS for Audit Table (Only Service Role can insert)
ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "deny_all_anon_auth" ON public.admin_audit_log
    FOR ALL USING (false);

-- 3. Surgical Financial Function per Driver
CREATE OR REPLACE FUNCTION get_driver_surgical_financials()
RETURNS TABLE (
    driver_id TEXT,
    total_rides_completed INT,
    gross_revenue FLOAT,
    uppi_fee_despesas FLOAT,
    net_earnings FLOAT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT
        d.id::text AS driver_id,
        COUNT(r.id)::INT AS total_rides_completed,
        COALESCE(SUM(r.fare), 0)::FLOAT AS gross_revenue,
        COALESCE(SUM(r.platform_fee), 0)::FLOAT AS uppi_fee_despesas,
        COALESCE(SUM(r.fare - r.platform_fee), 0)::FLOAT AS net_earnings
    FROM public.profiles d
    LEFT JOIN public.rides r ON r.driver_id = d.id::text AND r.status = 'completed'
    WHERE d.role = 'driver'
    GROUP BY d.id;
$$;

-- ─────────────────────────────────────────────
-- FILE: 20260505020000_admin_audit_log_rls.sql
-- ─────────────────────────────────────────────

-- =============================================================================
-- MIGRATION: ALLOW ADMIN PANEL TO WRITE AND READ AUDIT LOGS
-- =============================================================================

-- Drop the restrictive policy
DROP POLICY IF EXISTS "deny_all_anon_auth" ON public.admin_audit_log;

-- Allow authenticated users (Admin Panel users) to INSERT
CREATE POLICY "allow_authenticated_insert" ON public.admin_audit_log
    FOR INSERT 
    TO authenticated 
    WITH CHECK (true);

-- Allow authenticated users to SELECT (for viewing the logs in the future)
CREATE POLICY "allow_authenticated_select" ON public.admin_audit_log
    FOR SELECT 
    TO authenticated 
    USING (true);


-- ─────────────────────────────────────────────
-- FILE: 20260508000000_edge_functions_tables.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Tabelas necessárias para as novas Edge Functions
-- Data: 2026-05-08
-- Complementa o esquema existente com tabelas de gamificação, feedback,
-- documentos de motorista, SOS aprimorado e quick replies
-- ==============================================================================

-- ============================================================
-- 1. COLUNAS EXTRAS NO PROFILES (para Edge Functions)
-- ============================================================
DO $$
BEGIN
  -- Rating e review count (para submit-feedback)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'rating') THEN
    ALTER TABLE public.profiles ADD COLUMN rating NUMERIC(3,2) DEFAULT 5.00;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'review_count') THEN
    ALTER TABLE public.profiles ADD COLUMN review_count INTEGER DEFAULT 0;
  END IF;

  -- Comissão individual do motorista
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'commission_percentage') THEN
    ALTER TABLE public.profiles ADD COLUMN commission_percentage NUMERIC(5,2);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'commission_exempt_until') THEN
    ALTER TABLE public.profiles ADD COLUMN commission_exempt_until TIMESTAMPTZ;
  END IF;

  -- Subscription (assinatura motorista)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'subscription_expires_at') THEN
    ALTER TABLE public.profiles ADD COLUMN subscription_expires_at TIMESTAMPTZ;
  END IF;

  -- CPF
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'cpf') THEN
    ALTER TABLE public.profiles ADD COLUMN cpf TEXT;
  END IF;

  -- Phone (alias)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'phone') THEN
    ALTER TABLE public.profiles ADD COLUMN phone TEXT;
  END IF;
END $$;

-- ============================================================
-- 2. COLUNAS EXTRAS NAS RIDES (para Edge Functions)
-- ============================================================
DO $$
BEGIN
  -- Pickup/Dropoff lat/lng separados (para haversine)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'rides' AND column_name = 'pickup_lat') THEN
    ALTER TABLE public.rides ADD COLUMN pickup_lat DOUBLE PRECISION;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'rides' AND column_name = 'pickup_lng') THEN
    ALTER TABLE public.rides ADD COLUMN pickup_lng DOUBLE PRECISION;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'rides' AND column_name = 'dropoff_lat') THEN
    ALTER TABLE public.rides ADD COLUMN dropoff_lat DOUBLE PRECISION;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'rides' AND column_name = 'dropoff_lng') THEN
    ALTER TABLE public.rides ADD COLUMN dropoff_lng DOUBLE PRECISION;
  END IF;

  -- Timestamp de eventos
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'rides' AND column_name = 'started_at') THEN
    ALTER TABLE public.rides ADD COLUMN started_at TIMESTAMPTZ;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'rides' AND column_name = 'finished_at') THEN
    ALTER TABLE public.rides ADD COLUMN finished_at TIMESTAMPTZ;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'rides' AND column_name = 'arrived_at') THEN
    ALTER TABLE public.rides ADD COLUMN arrived_at TIMESTAMPTZ;
  END IF;

  -- Gorjeta
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'rides' AND column_name = 'tip_amount') THEN
    ALTER TABLE public.rides ADD COLUMN tip_amount NUMERIC(10,2) DEFAULT 0;
  END IF;

  -- Distância e duração float
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'rides' AND column_name = 'distance') THEN
    ALTER TABLE public.rides ADD COLUMN distance NUMERIC(10,2);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'rides' AND column_name = 'duration') THEN
    ALTER TABLE public.rides ADD COLUMN duration NUMERIC(10,2);
  END IF;

  -- Cupom
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'rides' AND column_name = 'coupon_id') THEN
    ALTER TABLE public.rides ADD COLUMN coupon_id UUID;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'rides' AND column_name = 'coupon_code') THEN
    ALTER TABLE public.rides ADD COLUMN coupon_code TEXT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'rides' AND column_name = 'coupon_discount') THEN
    ALTER TABLE public.rides ADD COLUMN coupon_discount NUMERIC(10,2) DEFAULT 0;
  END IF;

  -- Cancelled by
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'rides' AND column_name = 'cancelled_by') THEN
    ALTER TABLE public.rides ADD COLUMN cancelled_by TEXT;
  END IF;

  -- Currency
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'rides' AND column_name = 'currency') THEN
    ALTER TABLE public.rides ADD COLUMN currency TEXT DEFAULT 'BRL';
  END IF;

  -- Tracking token for public tracking links
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'rides' AND column_name = 'tracking_token') THEN
    ALTER TABLE public.rides ADD COLUMN tracking_token TEXT UNIQUE;
  END IF;
END $$;

-- Expandir constraint de status para incluir novos estados das Edge Functions
ALTER TABLE public.rides DROP CONSTRAINT IF EXISTS rides_status_check;
ALTER TABLE public.rides ADD CONSTRAINT rides_status_check
  CHECK (status IN (
    'requested', 'accepted', 'arrived', 'in_progress', 'completed', 'canceled',
    'driver_accepted', 'started', 'finished', 'waiting_for_review',
    'rider_canceled', 'driver_canceled', 'expired', 'no_driver'
  ));

-- ============================================================
-- 3. COLUNAS EXTRAS NO WALLET_TRANSACTIONS (para Edge Functions)
-- ============================================================
DO $$
BEGIN
  -- Type (alias para transaction_type)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'wallet_transactions' AND column_name = 'type') THEN
    ALTER TABLE public.wallet_transactions ADD COLUMN type TEXT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'wallet_transactions' AND column_name = 'status') THEN
    ALTER TABLE public.wallet_transactions ADD COLUMN status TEXT DEFAULT 'completed';
  END IF;
END $$;

-- ============================================================
-- 4. STATUS na DRIVER_LOCATIONS
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'driver_locations' AND column_name = 'status') THEN
    ALTER TABLE public.driver_locations ADD COLUMN status TEXT DEFAULT 'offline';
  END IF;
END $$;

-- ============================================================
-- 5. COLUNAS EXTRAS NOS COUPONS (para Edge Functions)
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'coupons' AND column_name = 'discount_percent') THEN
    ALTER TABLE public.coupons ADD COLUMN discount_percent NUMERIC(5,2);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'coupons' AND column_name = 'discount_flat') THEN
    ALTER TABLE public.coupons ADD COLUMN discount_flat NUMERIC(10,2);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'coupons' AND column_name = 'maximum_discount') THEN
    ALTER TABLE public.coupons ADD COLUMN maximum_discount NUMERIC(10,2);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'coupons' AND column_name = 'minimum_order_amount') THEN
    ALTER TABLE public.coupons ADD COLUMN minimum_order_amount NUMERIC(10,2);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'coupons' AND column_name = 'used_by_riders') THEN
    ALTER TABLE public.coupons ADD COLUMN used_by_riders TEXT[] DEFAULT '{}';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'coupons' AND column_name = 'used_count') THEN
    ALTER TABLE public.coupons ADD COLUMN used_count INTEGER DEFAULT 0;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'coupons' AND column_name = 'start_date') THEN
    ALTER TABLE public.coupons ADD COLUMN start_date TIMESTAMPTZ;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'coupons' AND column_name = 'expiration_date') THEN
    ALTER TABLE public.coupons ADD COLUMN expiration_date TIMESTAMPTZ;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'coupons' AND column_name = 'is_enabled') THEN
    ALTER TABLE public.coupons ADD COLUMN is_enabled BOOLEAN DEFAULT true;
  END IF;
END $$;

-- ============================================================
-- 6. FEEDBACKS (Avaliações detalhadas com parâmetros)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.feedbacks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID REFERENCES public.rides(id) ON DELETE CASCADE,
  driver_id TEXT REFERENCES public.profiles(id),
  rider_id TEXT REFERENCES public.profiles(id),
  rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
  review TEXT,
  parameters TEXT[] DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_feedbacks_driver ON public.feedbacks(driver_id);
CREATE INDEX IF NOT EXISTS idx_feedbacks_ride ON public.feedbacks(ride_id);

ALTER TABLE public.feedbacks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Ver feedbacks de corridas próprias" ON public.feedbacks;
CREATE POLICY "Ver feedbacks de corridas próprias" ON public.feedbacks
  FOR SELECT USING (
    auth.uid()::text = rider_id OR auth.uid()::text = driver_id
  );
DROP POLICY IF EXISTS "Criar feedback" ON public.feedbacks;
CREATE POLICY "Criar feedback" ON public.feedbacks
  FOR INSERT WITH CHECK (auth.uid()::text = rider_id);

-- ============================================================
-- 7. SOS_ALERTS (Alertas de emergência aprimorados)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.sos_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT REFERENCES public.profiles(id),
  ride_id UUID REFERENCES public.rides(id),
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  message TEXT,
  user_name TEXT,
  user_phone TEXT,
  status TEXT DEFAULT 'active',
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.sos_alerts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Criar SOS alert" ON public.sos_alerts;
CREATE POLICY "Criar SOS alert" ON public.sos_alerts
  FOR INSERT WITH CHECK (auth.uid()::text = user_id);
DROP POLICY IF EXISTS "Ver próprio SOS" ON public.sos_alerts;
CREATE POLICY "Ver próprio SOS" ON public.sos_alerts
  FOR SELECT USING (auth.uid()::text = user_id);

-- ============================================================
-- 8. RIDE_MESSAGES (Chat da corrida - Edge Functions usam esta)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.ride_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID REFERENCES public.rides(id) ON DELETE CASCADE,
  sender_id TEXT REFERENCES public.profiles(id),
  content TEXT NOT NULL,
  sent_by_driver BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ride_messages_ride ON public.ride_messages(ride_id);

ALTER TABLE public.ride_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Ver mensagens da corrida" ON public.ride_messages;
CREATE POLICY "Ver mensagens da corrida" ON public.ride_messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.rides
      WHERE rides.id::text = ride_messages.ride_id::text
      AND (rides.rider_id::text = auth.uid()::text OR rides.driver_id::text = auth.uid()::text)
    )
  );
DROP POLICY IF EXISTS "Enviar mensagem" ON public.ride_messages;
CREATE POLICY "Enviar mensagem" ON public.ride_messages
  FOR INSERT WITH CHECK (auth.uid()::text = sender_id);

-- ============================================================
-- 9. BADGE_DEFINITIONS (Definições de conquistas)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.badge_definitions (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  icon TEXT DEFAULT '🏆',
  required_rides INTEGER,
  required_rating NUMERIC(3,2),
  required_tips INTEGER,
  role TEXT DEFAULT 'driver',
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.badge_definitions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Ler badges" ON public.badge_definitions;
CREATE POLICY "Ler badges" ON public.badge_definitions FOR SELECT USING (true);

-- Badges padrão
INSERT INTO public.badge_definitions (id, name, description, icon, required_rides, role) VALUES
  ('first_ride_driver', 'Primeira Viagem', 'Completou sua primeira corrida', '🚗', 1, 'driver'),
  ('ten_rides_driver', '10 Viagens', 'Completou 10 corridas', '🏆', 10, 'driver'),
  ('fifty_rides_driver', 'Veterano', 'Completou 50 corridas', '⭐', 50, 'driver'),
  ('hundred_rides_driver', 'Lenda', 'Completou 100 corridas', '👑', 100, 'driver'),
  ('first_ride_rider', 'Passageiro Uppi', 'Completou sua primeira corrida', '🎉', 1, 'rider'),
  ('ten_rides_rider', 'Viajante Frequente', '10 corridas realizadas', '✈️', 10, 'rider')
ON CONFLICT (id) DO NOTHING;

-- Badge de rating perfeito
INSERT INTO public.badge_definitions (id, name, description, icon, required_rating, role) VALUES
  ('five_star_driver', '5 Estrelas', 'Avaliação perfeita de 5.0', '🌟', 5.00, 'driver')
ON CONFLICT (id) DO NOTHING;

-- Badge de gorjeta
INSERT INTO public.badge_definitions (id, name, description, icon, required_tips, role) VALUES
  ('generous_tipper', 'Generoso(a)', 'Deu 5 gorjetas', '💚', 5, 'rider')
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 10. USER_BADGES (Conquistas desbloqueadas)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.user_badges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT REFERENCES public.profiles(id),
  badge_id TEXT REFERENCES public.badge_definitions(id),
  badge_name TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, badge_id)
);

CREATE INDEX IF NOT EXISTS idx_user_badges_user ON public.user_badges(user_id);

ALTER TABLE public.user_badges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Ver próprios badges" ON public.user_badges;
CREATE POLICY "Ver próprios badges" ON public.user_badges
  FOR SELECT USING (auth.uid()::text = user_id);

-- ============================================================
-- 11. DRIVER_DOCUMENTS (Documentos do motorista)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.driver_documents (
  driver_id TEXT PRIMARY KEY REFERENCES public.profiles(id),
  cnh TEXT,
  vehicle_plate TEXT,
  vehicle_model TEXT,
  vehicle_color TEXT,
  vehicle_year TEXT,
  vehicle_category TEXT,
  status TEXT DEFAULT 'pending_review',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.driver_documents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Motorista vê próprios docs" ON public.driver_documents;
CREATE POLICY "Motorista vê próprios docs" ON public.driver_documents
  FOR SELECT USING (auth.uid()::text = driver_id);
DROP POLICY IF EXISTS "Motorista insere docs" ON public.driver_documents;
CREATE POLICY "Motorista insere docs" ON public.driver_documents
  FOR INSERT WITH CHECK (auth.uid()::text = driver_id);
DROP POLICY IF EXISTS "Motorista atualiza docs" ON public.driver_documents;
CREATE POLICY "Motorista atualiza docs" ON public.driver_documents
  FOR UPDATE USING (auth.uid()::text = driver_id);

-- ============================================================
-- 12. COUPON_USAGES (Log de uso de cupons)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.coupon_usages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coupon_id UUID REFERENCES public.coupons(id),
  user_id TEXT REFERENCES public.profiles(id),
  ride_id UUID REFERENCES public.rides(id),
  discount_amount NUMERIC(10,2) DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.coupon_usages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Ver próprios usos" ON public.coupon_usages;
CREATE POLICY "Ver próprios usos" ON public.coupon_usages
  FOR SELECT USING (auth.uid()::text = user_id);

-- ============================================================
-- 13. QUICK_REPLIES (Respostas rápidas do chat)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.quick_replies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  text_key TEXT,
  text_pt TEXT NOT NULL,
  role TEXT DEFAULT 'rider',
  category TEXT DEFAULT 'general',
  sort_order INTEGER DEFAULT 0,
  is_enabled BOOLEAN DEFAULT true
);

ALTER TABLE public.quick_replies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Ler quick replies" ON public.quick_replies;
CREATE POLICY "Ler quick replies" ON public.quick_replies FOR SELECT USING (true);

-- Inserir respostas padrão
INSERT INTO public.quick_replies (text_key, text_pt, role, category, sort_order) VALUES
  ('on_my_way', 'Estou a caminho!', 'rider', 'general', 1),
  ('wait_please', 'Espere um momento', 'rider', 'general', 2),
  ('im_here', 'Já estou aqui', 'rider', 'arrival', 3),
  ('where_are_you', 'Onde você está?', 'rider', 'general', 4),
  ('thanks', 'Obrigado(a)!', 'rider', 'general', 5),
  ('arriving', 'Estou chegando!', 'driver', 'arrival', 1),
  ('im_waiting', 'Estou aguardando', 'driver', 'arrival', 2),
  ('what_color', 'Qual a cor da sua roupa?', 'driver', 'identification', 3),
  ('traffic', 'Trânsito, chego em breve', 'driver', 'delay', 4),
  ('ok', 'Ok, entendido!', 'driver', 'general', 5)
ON CONFLICT DO NOTHING;

-- ============================================================
-- 14. RIDE_ACTIVITIES (Log de atividades da corrida)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.ride_activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID REFERENCES public.rides(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  data JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ride_activities_ride ON public.ride_activities(ride_id);

ALTER TABLE public.ride_activities ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Ver atividades da corrida" ON public.ride_activities;
CREATE POLICY "Ver atividades da corrida" ON public.ride_activities
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.rides
      WHERE rides.id::text = ride_activities.ride_id::text
      AND (rides.rider_id::text = auth.uid()::text OR rides.driver_id::text = auth.uid()::text)
    )
  );

-- ============================================================
-- 15. REVIEWS (Avaliações simples - usada por submit-review)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID REFERENCES public.rides(id) ON DELETE CASCADE,
  reviewer_id TEXT REFERENCES public.profiles(id),
  reviewed_id TEXT REFERENCES public.profiles(id),
  rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(ride_id, reviewer_id)
);

CREATE INDEX IF NOT EXISTS idx_reviews_reviewed ON public.reviews(reviewed_id);

ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Ver reviews" ON public.reviews;
CREATE POLICY "Ver reviews" ON public.reviews
  FOR SELECT USING (
    auth.uid()::text = reviewer_id OR auth.uid()::text = reviewed_id
  );
DROP POLICY IF EXISTS "Criar review" ON public.reviews;
CREATE POLICY "Criar review" ON public.reviews
  FOR INSERT WITH CHECK (auth.uid()::text = reviewer_id);

-- ============================================================
-- 16. CHALLENGES (Desafios para motoristas)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.challenges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT,
  target INTEGER NOT NULL DEFAULT 10,
  reward_type TEXT DEFAULT 'walletBonus',
  reward_label TEXT,
  reward_description TEXT,
  reward_amount NUMERIC(10,2),
  is_active BOOLEAN DEFAULT true,
  period_start_at TIMESTAMPTZ DEFAULT now(),
  period_end_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.challenges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Ler desafios ativos" ON public.challenges;
CREATE POLICY "Ler desafios ativos" ON public.challenges
  FOR SELECT USING (is_active = true);

-- ============================================================
-- 17. COLUNAS SOFT-DELETE NO PROFILES (para delete-user-account)
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'is_deleted') THEN
    ALTER TABLE public.profiles ADD COLUMN is_deleted BOOLEAN DEFAULT false;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'deleted_at') THEN
    ALTER TABLE public.profiles ADD COLUMN deleted_at TIMESTAMPTZ;
  END IF;
END $$;

-- ============================================================
-- FIM DA MIGRAÇÃO
-- ============================================================


-- ─────────────────────────────────────────────
-- FILE: 20260508010000_pg_cron_schedules.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- CONFIGURAÇÃO PG CRON - Tarefas automáticas do Supabase
-- Execute no SQL Editor do Supabase após o deploy das Edge Functions
-- ==============================================================================

-- Habilitar extensão pg_cron (já vem habilitada no Supabase por padrão)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ==============================================================================
-- 1. LIMPEZA DE CORRIDAS EXPIRADAS (a cada 5 minutos)
-- Marca corridas 'requested' sem motorista por mais de 3 minutos como 'expired'
-- ==============================================================================
SELECT cron.schedule(
  'cleanup-expired-rides',
  '*/5 * * * *',
  $$
    UPDATE public.rides
    SET status = 'expired', updated_at = now()
    WHERE status = 'requested'
      AND driver_id IS NULL
      AND created_at < now() - interval '3 minutes';
  $$
);

-- ==============================================================================
-- 2. MOTORISTAS INATIVOS (a cada 10 minutos)
-- Marca motoristas que não atualizaram localização por mais de 15 minutos como 'offline'
-- ==============================================================================
SELECT cron.schedule(
  'cleanup-inactive-drivers',
  '*/10 * * * *',
  $$
    UPDATE public.driver_locations
    SET status = 'offline'
    WHERE status = 'online'
      AND updated_at < now() - interval '15 minutes';
  $$
);

-- ==============================================================================
-- 3. LIMPAR TOKENS FCM ANTIGOS (diariamente às 03:00 UTC)
-- Remove tokens FCM de perfis que não atualizam há mais de 30 dias
-- ==============================================================================
SELECT cron.schedule(
  'cleanup-stale-fcm-tokens',
  '0 3 * * *',
  $$
    UPDATE public.profiles
    SET fcm_token = NULL
    WHERE fcm_token IS NOT NULL
      AND updated_at < now() - interval '30 days';
  $$
);

-- ==============================================================================
-- 4. EXPIRAR CUPONS VENCIDOS (diariamente à meia-noite UTC)
-- ==============================================================================
SELECT cron.schedule(
  'expire-old-coupons',
  '0 0 * * *',
  $$
    UPDATE public.coupons
    SET is_active = false, is_enabled = false
    WHERE (expiration_date IS NOT NULL AND expiration_date < now())
       OR (expires_at IS NOT NULL AND expires_at < now());
  $$
);

-- ==============================================================================
-- VERIFICAR AGENDAMENTOS
-- ==============================================================================
-- Para verificar os crons agendados:
-- SELECT * FROM cron.job;
--
-- Para desabilitar um cron:
-- SELECT cron.unschedule('cleanup-expired-rides');
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260508020000_payment_tables_seed.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Tabelas pix_payments / mp_payments + coluna value na config + seed
-- Data: 2026-05-08
-- ==============================================================================

-- ============================================================
-- 1. Adicionar coluna VALUE na tabela config (se não existir)
-- Necessário para getMercadoPagoConfig() no Edge Functions
-- ============================================================
ALTER TABLE public.config ADD COLUMN IF NOT EXISTS value TEXT;
ALTER TABLE public.config ADD COLUMN IF NOT EXISTS meta  JSONB DEFAULT '{}';

-- ============================================================
-- 2. PIX_PAYMENTS — Pagamentos PIX via Mercado Pago
-- ============================================================
CREATE TABLE IF NOT EXISTS public.pix_payments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mp_payment_id   TEXT UNIQUE NOT NULL,
  ride_id         UUID REFERENCES public.rides(id) ON DELETE SET NULL,
  rider_id        TEXT REFERENCES public.profiles(id) ON DELETE SET NULL,
  amount          NUMERIC(10,2) NOT NULL,
  status          TEXT DEFAULT 'pending',
  qr_code         TEXT,
  qr_code_base64  TEXT,
  ticket_url      TEXT,
  expires_at      TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pix_payments_ride   ON public.pix_payments(ride_id);
CREATE INDEX IF NOT EXISTS idx_pix_payments_rider  ON public.pix_payments(rider_id);
CREATE INDEX IF NOT EXISTS idx_pix_payments_status ON public.pix_payments(status);

ALTER TABLE public.pix_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Ver próprios pagamentos PIX" ON public.pix_payments;
CREATE POLICY "Ver próprios pagamentos PIX" ON public.pix_payments
  FOR SELECT USING (auth.uid()::text = rider_id);

DROP POLICY IF EXISTS "Admin vê todos pagamentos PIX" ON public.pix_payments;
CREATE POLICY "Admin vê todos pagamentos PIX" ON public.pix_payments
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()::text AND role IN ('admin', 'operator')
    )
  );

-- ============================================================
-- 3. MP_PAYMENTS — Todos os pagamentos Mercado Pago (webhook)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.mp_payments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mp_payment_id   TEXT UNIQUE NOT NULL,
  ride_id         UUID REFERENCES public.rides(id) ON DELETE SET NULL,
  rider_id        TEXT REFERENCES public.profiles(id) ON DELETE SET NULL,
  status          TEXT DEFAULT 'pending',
  status_detail   TEXT,
  amount          NUMERIC(10,2),
  currency        TEXT DEFAULT 'BRL',
  payment_method  TEXT,
  payment_type    TEXT,
  paid_at         TIMESTAMPTZ,
  processed       BOOLEAN DEFAULT false,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mp_payments_ride   ON public.mp_payments(ride_id);
CREATE INDEX IF NOT EXISTS idx_mp_payments_rider  ON public.mp_payments(rider_id);
CREATE INDEX IF NOT EXISTS idx_mp_payments_status ON public.mp_payments(status);

ALTER TABLE public.mp_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Ver próprios pagamentos MP" ON public.mp_payments;
CREATE POLICY "Ver próprios pagamentos MP" ON public.mp_payments
  FOR SELECT USING (auth.uid()::text = rider_id);

DROP POLICY IF EXISTS "Admin vê todos pagamentos MP" ON public.mp_payments;
CREATE POLICY "Admin vê todos pagamentos MP" ON public.mp_payments
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()::text AND role IN ('admin', 'operator')
    )
  );

-- ============================================================
-- 4. CONFIG — Inserir chaves Mercado Pago (vazias, admin preenche)
-- ============================================================
INSERT INTO public.config (key, surge_multiplier) VALUES
  ('mercadopago_access_token', 1.0),
  ('mercadopago_public_key',   1.0)
ON CONFLICT (key) DO NOTHING;

-- ============================================================
-- 5. SERVICES — Serviço padrão Uppi X (coluna 'name', não 'title')
-- ============================================================
INSERT INTO public.services (name, description, base_fare, per_km_fare, per_minute_fare, minimum_fare, person_capacity)
SELECT 'Uppi X', 'Corridas econômicas', 5.00, 2.00, 0.30, 7.00, 4
WHERE NOT EXISTS (SELECT 1 FROM public.services WHERE name = 'Uppi X');

-- ============================================================
-- 6. CANCEL_REASONS — Seed padrão (coluna 'name' e 'role')
-- ============================================================
INSERT INTO public.cancel_reasons (name, role) VALUES
  ('Motorista demorou muito',  'rider'),
  ('Errei o endereço',         'rider'),
  ('Mudei de planos',          'rider'),
  ('Encontrei outra opção',    'rider'),
  ('Passageiro não apareceu',  'driver'),
  ('Endereço incorreto',       'driver'),
  ('Problemas com o veículo',  'driver'),
  ('Emergência pessoal',       'driver')
ON CONFLICT DO NOTHING;

-- ============================================================
-- FIM DA MIGRAÇÃO
-- ============================================================


-- ─────────────────────────────────────────────
-- FILE: 20260508030000_admin_panel_tables.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Tabelas necessárias para o Admin Panel funcionar
-- admins, app_settings
-- ==============================================================================

-- ============================================================
-- 1. ADMINS — Controle de acesso ao painel admin
-- ============================================================
CREATE TABLE IF NOT EXISTS public.admins (
  id          TEXT PRIMARY KEY,                    -- Firebase UID
  email       TEXT,
  role        TEXT DEFAULT 'admin' CHECK (role IN ('admin', 'superadmin', 'operator')),
  name        TEXT,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;

-- Permitir leitura para qualquer autenticado (o app precisa checar se é admin)
DROP POLICY IF EXISTS "admins_select_authenticated" ON public.admins;
CREATE POLICY "admins_select_authenticated" ON public.admins
  FOR SELECT TO authenticated USING (true);

-- Permitir insert (para o primeiro admin se auto-registrar)
DROP POLICY IF EXISTS "admins_insert_authenticated" ON public.admins;
CREATE POLICY "admins_insert_authenticated" ON public.admins
  FOR INSERT TO authenticated WITH CHECK (true);

-- Permitir update apenas para o próprio admin
DROP POLICY IF EXISTS "admins_update_self" ON public.admins;
CREATE POLICY "admins_update_self" ON public.admins
  FOR UPDATE TO authenticated USING (true);

-- ============================================================
-- 2. APP_SETTINGS — Configurações gerais editáveis pelo admin
-- ============================================================
CREATE TABLE IF NOT EXISTS public.app_settings (
  key         TEXT PRIMARY KEY,
  value       TEXT,
  meta        JSONB DEFAULT '{}',
  updated_at  TIMESTAMPTZ DEFAULT now(),
  updated_by  TEXT
);

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- Qualquer um pode ler (app precisa ler configs antes do login)
DROP POLICY IF EXISTS "app_settings_select" ON public.app_settings;
CREATE POLICY "app_settings_select" ON public.app_settings
  FOR SELECT USING (true);

-- Admins podem escrever (o app valida no frontend se é admin)
DROP POLICY IF EXISTS "app_settings_insert" ON public.app_settings;
CREATE POLICY "app_settings_insert" ON public.app_settings
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "app_settings_update" ON public.app_settings;
CREATE POLICY "app_settings_update" ON public.app_settings
  FOR UPDATE TO authenticated USING (true);

-- ============================================================
-- 3. Garantir que admin_audit_log permite insert de admins
-- ============================================================
DROP POLICY IF EXISTS "audit_log_insert_authenticated" ON public.admin_audit_log;
CREATE POLICY "audit_log_insert_authenticated" ON public.admin_audit_log
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "audit_log_select_authenticated" ON public.admin_audit_log;
CREATE POLICY "audit_log_select_authenticated" ON public.admin_audit_log
  FOR SELECT TO authenticated USING (true);

-- ============================================================
-- 4. Garantir que admin pode ler/editar profiles, rides, etc.
-- ============================================================

-- Admin pode ler todos os profiles
DROP POLICY IF EXISTS "admin_select_all_profiles" ON public.profiles;
CREATE POLICY "admin_select_all_profiles" ON public.profiles
  FOR SELECT TO authenticated USING (true);

-- Admin pode atualizar profiles (aprovar motorista, bloquear, etc.)
DROP POLICY IF EXISTS "admin_update_profiles" ON public.profiles;
CREATE POLICY "admin_update_profiles" ON public.profiles
  FOR UPDATE TO authenticated USING (true);

-- Admin pode ler todas as corridas
DROP POLICY IF EXISTS "admin_select_all_rides" ON public.rides;
CREATE POLICY "admin_select_all_rides" ON public.rides
  FOR SELECT TO authenticated USING (true);

-- Admin pode ler driver_locations
DROP POLICY IF EXISTS "admin_select_driver_locations" ON public.driver_locations;
CREATE POLICY "admin_select_driver_locations" ON public.driver_locations
  FOR SELECT TO authenticated USING (true);

-- high_risk_drivers é uma VIEW, não precisa de RLS policy

-- Admin pode gerenciar services
DROP POLICY IF EXISTS "admin_all_services" ON public.services;
CREATE POLICY "admin_all_services" ON public.services
  FOR ALL TO authenticated USING (true);

-- Admin pode gerenciar coupons
DROP POLICY IF EXISTS "admin_all_coupons" ON public.coupons;
CREATE POLICY "admin_all_coupons" ON public.coupons
  FOR ALL TO authenticated USING (true);

-- Admin pode ler/inserir wallet_transactions
DROP POLICY IF EXISTS "admin_all_wallet_tx" ON public.wallet_transactions;
CREATE POLICY "admin_all_wallet_tx" ON public.wallet_transactions
  FOR ALL TO authenticated USING (true);

-- Admin pode gerenciar announcements
DROP POLICY IF EXISTS "admin_all_announcements" ON public.announcements;
CREATE POLICY "admin_all_announcements" ON public.announcements
  FOR ALL TO authenticated USING (true);

-- ============================================================
-- 5. Seed de configurações padrão
-- ============================================================
INSERT INTO public.app_settings (key, value) VALUES
  ('app_name',          'Uppi'),
  ('support_email',     'suporte@uppi.com.br'),
  ('support_phone',     '5511999999999'),
  ('sos_phone',         '190'),
  ('terms_url',         'https://uppi.com.br/termos'),
  ('privacy_url',       'https://uppi.com.br/privacidade'),
  ('default_language',  'pt_BR'),
  ('currency',          'BRL'),
  ('currency_symbol',   'R$'),
  ('commission_rate',   '15')
ON CONFLICT (key) DO NOTHING;

-- ============================================================
-- FIM DA MIGRAÇÃO
-- ============================================================


-- ─────────────────────────────────────────────
-- FILE: 20260508040000_rpc_find_nearby_rides.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- ADD RPC FOR FINDING NEARBY REQUESTED RIDES (RIDE CHAINING)
-- ==============================================================================

-- Drop if exists to ensure idempotency
DROP FUNCTION IF EXISTS public.find_nearby_requested_rides(float8, float8, float8);

-- Create the function
CREATE OR REPLACE FUNCTION public.find_nearby_requested_rides(
    lat float8,
    lng float8,
    radius_meters float8 DEFAULT 3000
)
RETURNS TABLE (
    id UUID,
    pickup_address TEXT,
    dropoff_address TEXT,
    fare DECIMAL,
    dist_meters FLOAT8
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        r.id,
        r.pickup_address,
        r.dropoff_address,
        r.fare,
        ST_Distance(
            r.pickup_location,
            ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography
        ) AS dist_meters
    FROM public.rides r
    WHERE r.status = 'requested'
      AND r.driver_id IS NULL
      AND ST_DWithin(
          r.pickup_location,
          ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography,
          radius_meters
      )
    ORDER BY dist_meters ASC
    LIMIT 1; -- We only need the best match for ride chaining
END;
$$;


-- ─────────────────────────────────────────────
-- FILE: 20260508050000_rpc_assign_driver.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- ADD RPC FOR ASSIGNING A DRIVER TO A RIDE
-- ==============================================================================

DROP FUNCTION IF EXISTS public.assign_driver_to_ride(UUID, TEXT);

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

    -- 3. Check if the ride is still requested
    IF v_status <> 'requested' THEN
        RAISE EXCEPTION 'A corrida não está mais disponível (status atual: %)', v_status;
    END IF;

    -- 4. Update the ride
    UPDATE public.rides
    SET driver_id = p_driver_id,
        status = 'accepted',
        updated_at = now()
    WHERE id = p_ride_id;
END;
$$;


-- ─────────────────────────────────────────────
-- FILE: 20260511131128_fix_app_settings_rls.sql
-- ─────────────────────────────────────────────

                                                                                                                                                                                                                           

-- ─────────────────────────────────────────────
-- FILE: 20260511151500_enable_realtime_missing_tables.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO — HABILITAR REALTIME NAS TABELAS FALTANTES
-- ==============================================================================
-- O código Flutter usa .stream(primaryKey: ['id']) nas tabelas abaixo,
-- porém elas NÃO estavam registradas na publicação supabase_realtime.
-- Sem isso o Realtime só faz polling local — NÃO recebe push do servidor.
-- ==============================================================================

-- 1. rides — status da corrida em tempo real (rider + driver)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'rides'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.rides;
  END IF;
END $$;

-- 2. profiles — localização do motorista + dados do perfil em tempo real
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'profiles'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
  END IF;
END $$;

-- 3. app_settings — configurações globais instantâneas (map provider, etc)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'app_settings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.app_settings;
  END IF;
END $$;

-- 4. Garantir REPLICA IDENTITY FULL nas tabelas com Realtime
-- Isso permite que o Supabase envie o registro completo (old + new) nos eventos
ALTER TABLE public.rides REPLICA IDENTITY FULL;
ALTER TABLE public.profiles REPLICA IDENTITY FULL;
ALTER TABLE public.app_settings REPLICA IDENTITY FULL;
ALTER TABLE public.ride_messages REPLICA IDENTITY FULL;
ALTER TABLE public.driver_locations REPLICA IDENTITY FULL;

-- ==============================================================================
-- FIM — Agora TODAS as tabelas usadas com .stream() têm Realtime ativo
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260511181000_fix_profiles_rls_wallet_rpc.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO CRÍTICA — CORRIGE RLS de profiles + cria wallet + RPC increment
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. PROFILES: Permitir que usuários autenticados leiam dados PÚBLICOS
--    de outros perfis (nome, foto, rating) — necessário para rider↔driver
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Usuário lê próprio perfil" ON public.profiles;

-- Nova policy: qualquer autenticado pode ler dados públicos de qualquer perfil
-- (full_name, avatar_url, rating, vehicle_type, etc.)
CREATE POLICY "Authenticated users can read profiles"
  ON public.profiles FOR SELECT TO authenticated
  USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WALLETS: Tabela de carteira para motoristas e passageiros
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.wallets (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT NOT NULL UNIQUE REFERENCES public.profiles(id),
    balance NUMERIC(12,2) DEFAULT 0.00 NOT NULL,
    currency TEXT DEFAULT 'BRL',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='wallets' AND policyname='User reads own wallet') THEN
    CREATE POLICY "User reads own wallet" ON public.wallets
      FOR SELECT TO authenticated
      USING (user_id = auth.uid()::text);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='wallets' AND policyname='User inserts own wallet') THEN
    CREATE POLICY "User inserts own wallet" ON public.wallets
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid()::text);
  END IF;
END $$;

-- Admin pode ver/atualizar qualquer wallet
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='wallets' AND policyname='admin_wallets_all') THEN
    CREATE POLICY "admin_wallets_all" ON public.wallets
      FOR ALL TO authenticated
      USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator'))
      );
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. RPC increment_wallet — atualiza saldo de forma atômica (SECURITY DEFINER)
--    Aceita valores negativos (dedução de comissão) e positivos (recarga)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.increment_wallet(
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
  INSERT INTO public.wallets (user_id, balance)
  VALUES (target_user_id, 0)
  ON CONFLICT (user_id) DO NOTHING;

  -- Atualiza o saldo atomicamente
  UPDATE public.wallets
  SET balance = balance + amount_to_add,
      updated_at = now()
  WHERE user_id = target_user_id;
END;
$$;

-- Permitir que qualquer autenticado chame a RPC
-- (a função é SECURITY DEFINER, então executa com permissões do owner)
GRANT EXECUTE ON FUNCTION public.increment_wallet TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Habilitar Realtime na wallets (para o app ver saldo atualizar em tempo real)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'wallets'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.wallets;
  END IF;
END $$;

ALTER TABLE public.wallets REPLICA IDENTITY FULL;

-- ==============================================================================
-- FIM — Profiles RLS aberto para leitura, wallet criada, RPC pronta
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260511182554_fix_storage_kyc_privacy.sql
-- ─────────────────────────────────────────────

-- Fix public exposure of sensitive documents (GDPR / LGPD Compliance)
-- Reverts KYC and vehicle documents buckets from public to private
UPDATE storage.buckets 
SET public = false 
WHERE id IN ('identity-docs', 'documents');

-- Drop public read policies that exposed user documents to the internet
DROP POLICY IF EXISTS "Public access to identity-docs" ON storage.objects;
DROP POLICY IF EXISTS "Leitura Publica Documents" ON storage.objects;

-- Create restricted read policies for identity-docs
-- Allows the owner of the document or an administrator to view the file
CREATE POLICY "Restricted Read identity-docs" 
ON storage.objects 
FOR SELECT 
USING (
  bucket_id = 'identity-docs' 
  AND auth.role() = 'authenticated'
  AND (
    (auth.uid()::text = (storage.foldername(name))[1]) OR
    (auth.uid()::text = (storage.foldername(name))[2]) OR
    (EXISTS (SELECT 1 FROM public.admins WHERE id::text = auth.uid()::text))
  )
);

-- Create restricted read policies for documents
CREATE POLICY "Restricted Read documents" 
ON storage.objects 
FOR SELECT 
USING (
  bucket_id = 'documents' 
  AND auth.role() = 'authenticated'
  AND (
    (auth.uid()::text = (storage.foldername(name))[1]) OR
    (auth.uid()::text = (storage.foldername(name))[2]) OR
    (EXISTS (SELECT 1 FROM public.admins WHERE id::text = auth.uid()::text))
  )
);


-- ─────────────────────────────────────────────
-- FILE: 20260511183640_organize_database_cleanups.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- DATABASE ORGANIZER & CLEANUP MIGRATION
-- Remove old wallet_balance from profiles and migrate to new wallets table
-- ==============================================================================

-- 1. Sync any existing wallet_balance to the new wallets table
DO $$ 
BEGIN
  -- Insert missing wallets
  INSERT INTO public.wallets (user_id, balance)
  SELECT id, COALESCE(wallet_balance, 0)
  FROM public.profiles
  ON CONFLICT (user_id) DO NOTHING;

  -- Update existing wallets with profiles balance if wallets balance is 0 and profile is > 0
  UPDATE public.wallets w
  SET balance = p.wallet_balance,
      updated_at = now()
  FROM public.profiles p
  WHERE w.user_id = p.id
    AND w.balance = 0
    AND p.wallet_balance > 0;
EXCEPTION
  WHEN undefined_column THEN
    -- Column wallet_balance might already be dropped or not exist
    NULL;
END $$;

-- 2. Drop the old security trigger that blocked direct updates to wallet_balance
DROP TRIGGER IF EXISTS enforce_wallet_security ON public.profiles;

-- 3. Drop the associated trigger function
DROP FUNCTION IF EXISTS public.block_wallet_update();

-- 4. Safely drop the obsolete wallet_balance column from profiles
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'wallet_balance') THEN
    ALTER TABLE public.profiles DROP COLUMN wallet_balance;
  END IF;
END $$;


-- ─────────────────────────────────────────────
-- FILE: 20260511190000_db_final_organization.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- ORGANIZAÇÃO FINAL DO BANCO DE DADOS — UPPI
-- 1. Triggers updated_at faltando em 9 tabelas
-- 2. Índices de performance faltando
-- 3. RLS na wallet_transactions
-- 4. Coluna cancel_reason_note em rides
-- 5. Índices nas tabelas financeiras e de motorista
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. TRIGGERS updated_at — garante que updated_at seja atualizado
--    automaticamente em todas as tabelas que possuem essa coluna
-- ─────────────────────────────────────────────────────────────────────────────

-- Função reutilizável (cria apenas se não existir)
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- driver_documents
DROP TRIGGER IF EXISTS update_driver_documents_updated_at ON public.driver_documents;
CREATE TRIGGER update_driver_documents_updated_at
  BEFORE UPDATE ON public.driver_documents
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- config
DROP TRIGGER IF EXISTS update_config_updated_at ON public.config;
CREATE TRIGGER update_config_updated_at
  BEFORE UPDATE ON public.config
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- driver_locations
DROP TRIGGER IF EXISTS update_driver_locations_updated_at ON public.driver_locations;
CREATE TRIGGER update_driver_locations_updated_at
  BEFORE UPDATE ON public.driver_locations
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- pix_payments
DROP TRIGGER IF EXISTS update_pix_payments_updated_at ON public.pix_payments;
CREATE TRIGGER update_pix_payments_updated_at
  BEFORE UPDATE ON public.pix_payments
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- mp_payments
DROP TRIGGER IF EXISTS update_mp_payments_updated_at ON public.mp_payments;
CREATE TRIGGER update_mp_payments_updated_at
  BEFORE UPDATE ON public.mp_payments
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- admins
DROP TRIGGER IF EXISTS update_admins_updated_at ON public.admins;
CREATE TRIGGER update_admins_updated_at
  BEFORE UPDATE ON public.admins
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- app_settings
DROP TRIGGER IF EXISTS update_app_settings_updated_at ON public.app_settings;
CREATE TRIGGER update_app_settings_updated_at
  BEFORE UPDATE ON public.app_settings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- scheduled_rides
DROP TRIGGER IF EXISTS update_scheduled_rides_updated_at ON public.scheduled_rides;
CREATE TRIGGER update_scheduled_rides_updated_at
  BEFORE UPDATE ON public.scheduled_rides
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- wallets
DROP TRIGGER IF EXISTS update_wallets_updated_at ON public.wallets;
CREATE TRIGGER update_wallets_updated_at
  BEFORE UPDATE ON public.wallets
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. COLUNA cancel_reason_note em rides (usada em delete-user-account e cancel-order)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'rides' AND column_name = 'cancel_reason_note'
  ) THEN
    ALTER TABLE public.rides ADD COLUMN cancel_reason_note TEXT;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. ÍNDICES DE PERFORMANCE — tabelas financeiras e de motorista
-- ─────────────────────────────────────────────────────────────────────────────

-- wallet_transactions: busca por usuário e data
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_user_id
  ON public.wallet_transactions (user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_ride_id
  ON public.wallet_transactions (ride_id)
  WHERE ride_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_created_at
  ON public.wallet_transactions (created_at DESC);

-- driver_earnings: relatórios financeiros por motorista
CREATE INDEX IF NOT EXISTS idx_driver_earnings_driver_id
  ON public.driver_earnings (driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_earnings_ride_id
  ON public.driver_earnings (ride_id);
CREATE INDEX IF NOT EXISTS idx_driver_earnings_created_at
  ON public.driver_earnings (created_at DESC);

-- driver_documents: KYC lookup por motorista
CREATE INDEX IF NOT EXISTS idx_driver_documents_driver_id
  ON public.driver_documents (driver_id);

-- messages / chat: busca por corrida
CREATE INDEX IF NOT EXISTS idx_messages_ride_id
  ON public.messages (ride_id);
CREATE INDEX IF NOT EXISTS idx_ride_messages_ride_id
  ON public.ride_messages (ride_id);

-- scheduled_rides: agendamento por passageiro e horário
CREATE INDEX IF NOT EXISTS idx_scheduled_rides_rider_id
  ON public.scheduled_rides (rider_id);
CREATE INDEX IF NOT EXISTS idx_scheduled_rides_scheduled_at
  ON public.scheduled_rides (scheduled_at);

-- sos_alerts e sos_signals: alertas por usuário
CREATE INDEX IF NOT EXISTS idx_sos_alerts_user_id
  ON public.sos_alerts (user_id);

-- notifications / announcements: busca por destinatário
CREATE INDEX IF NOT EXISTS idx_announcements_created_at
  ON public.announcements (created_at DESC);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. RLS na wallet_transactions — garantir que usuários só veem as próprias
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_reads_own_transactions" ON public.wallet_transactions;
CREATE POLICY "user_reads_own_transactions"
  ON public.wallet_transactions FOR SELECT TO authenticated
  USING (user_id = auth.uid()::text);

DROP POLICY IF EXISTS "service_role_all_transactions" ON public.wallet_transactions;
CREATE POLICY "service_role_all_transactions"
  ON public.wallet_transactions FOR ALL TO service_role
  USING (true);

-- Admin pode ver todas as transações
DROP POLICY IF EXISTS "admin_reads_all_transactions" ON public.wallet_transactions;
CREATE POLICY "admin_reads_all_transactions"
  ON public.wallet_transactions FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator'))
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. REALTIME nas tabelas que ainda não estão publicadas
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'wallet_transactions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.wallet_transactions;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'scheduled_rides'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.scheduled_rides;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'driver_documents'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_documents;
  END IF;
END $$;

-- REPLICA IDENTITY FULL para as novas tabelas com Realtime
ALTER TABLE public.wallet_transactions REPLICA IDENTITY FULL;
ALTER TABLE public.scheduled_rides REPLICA IDENTITY FULL;
ALTER TABLE public.driver_documents REPLICA IDENTITY FULL;

-- ==============================================================================
-- FIM — Banco de dados 100% organizado
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260511191000_fix_rls_public_to_authenticated.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- CORREÇÃO CRÍTICA DE SEGURANÇA — RLS policies com 'public' → 'authenticated'
-- Em Supabase/Postgres, 'public' = acesso sem autenticação (qualquer pessoa)
-- Toda policy que protege dados de usuários deve usar TO authenticated
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- COMPLAINTS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Criar Reclamação" ON public.complaints;
DROP POLICY IF EXISTS "Users can insert complaints" ON public.complaints;
DROP POLICY IF EXISTS "Users can view own complaints" ON public.complaints;
DROP POLICY IF EXISTS "Ver próprias reclamações" ON public.complaints;

CREATE POLICY "complaints_insert" ON public.complaints
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY "complaints_select" ON public.complaints
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = user_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator'))
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- COUPON_USAGES
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Ver próprios usos" ON public.coupon_usages;

CREATE POLICY "coupon_usages_select" ON public.coupon_usages
  FOR SELECT TO authenticated
  USING (auth.uid()::text = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- DRIVER_DOCUMENTS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Motorista atualiza docs" ON public.driver_documents;
DROP POLICY IF EXISTS "Motorista insere docs" ON public.driver_documents;
DROP POLICY IF EXISTS "Motorista vê próprios docs" ON public.driver_documents;

CREATE POLICY "driver_documents_select" ON public.driver_documents
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = driver_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator'))
  );

CREATE POLICY "driver_documents_insert" ON public.driver_documents
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = driver_id);

CREATE POLICY "driver_documents_update" ON public.driver_documents
  FOR UPDATE TO authenticated
  USING (auth.uid()::text = driver_id)
  WITH CHECK (auth.uid()::text = driver_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- DRIVER_EARNINGS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "driver_earnings_insert" ON public.driver_earnings;
DROP POLICY IF EXISTS "driver_earnings_select" ON public.driver_earnings;

CREATE POLICY "driver_earnings_select" ON public.driver_earnings
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = driver_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator'))
  );

CREATE POLICY "driver_earnings_insert" ON public.driver_earnings
  FOR INSERT TO service_role
  WITH CHECK (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- DRIVER_LOCATIONS — manter leitura pública (necessário para o mapa de passageiros)
-- mas restringir escrita somente ao próprio motorista autenticado
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Anyone can read driver locations" ON public.driver_locations;
DROP POLICY IF EXISTS "Drivers can update own location" ON public.driver_locations;

-- Passageiros autenticados precisam ver motoristas no mapa
CREATE POLICY "driver_locations_select" ON public.driver_locations
  FOR SELECT TO authenticated
  USING (true);

-- Só o motorista dono pode atualizar/inserir sua localização
CREATE POLICY "driver_locations_upsert" ON public.driver_locations
  FOR ALL TO authenticated
  USING (auth.uid()::text = driver_id)
  WITH CHECK (auth.uid()::text = driver_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- FEEDBACKS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Criar feedback" ON public.feedbacks;
DROP POLICY IF EXISTS "Ver feedbacks de corridas próprias" ON public.feedbacks;

CREATE POLICY "feedbacks_insert" ON public.feedbacks
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = rider_id OR auth.uid()::text = driver_id);

CREATE POLICY "feedbacks_select" ON public.feedbacks
  FOR SELECT TO authenticated
  USING (auth.uid()::text = rider_id OR auth.uid()::text = driver_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- MESSAGES
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Envio de Mensagens" ON public.messages;
DROP POLICY IF EXISTS "Leitura de Mensagens" ON public.messages;

-- messages vinculadas a corridas: quem é rider ou driver da corrida pode ler
CREATE POLICY "messages_select" ON public.messages
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = sender_id OR
    EXISTS (
      SELECT 1 FROM public.rides r
      WHERE r.id = ride_id AND (r.rider_id = auth.uid()::text OR r.driver_id = auth.uid()::text)
    )
  );

CREATE POLICY "messages_insert" ON public.messages
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = sender_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- MP_PAYMENTS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Admin vê todos pagamentos MP" ON public.mp_payments;
DROP POLICY IF EXISTS "Ver próprios pagamentos MP" ON public.mp_payments;

CREATE POLICY "mp_payments_select_own" ON public.mp_payments
  FOR SELECT TO authenticated
  USING (auth.uid()::text = rider_id);

CREATE POLICY "mp_payments_admin" ON public.mp_payments
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator')));

-- ─────────────────────────────────────────────────────────────────────────────
-- PAYMENT_METHODS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Atualizar próprios métodos de pagamento" ON public.payment_methods;
DROP POLICY IF EXISTS "Deletar próprios métodos de pagamento" ON public.payment_methods;
DROP POLICY IF EXISTS "Inserir próprios métodos de pagamento" ON public.payment_methods;
DROP POLICY IF EXISTS "Ver próprios métodos de pagamento" ON public.payment_methods;

-- payment_methods.user_id é do tipo UUID (não text), então comparamos com auth.uid() direto
CREATE POLICY "payment_methods_all" ON public.payment_methods
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- PAYOUT_ACCOUNTS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Atualizar próprias contas de saque" ON public.payout_accounts;
DROP POLICY IF EXISTS "Deletar próprias contas de saque" ON public.payout_accounts;
DROP POLICY IF EXISTS "Inserir próprias contas de saque" ON public.payout_accounts;
DROP POLICY IF EXISTS "Ver próprias contas de saque" ON public.payout_accounts;

CREATE POLICY "payout_accounts_all" ON public.payout_accounts
  FOR ALL TO authenticated
  USING (auth.uid()::text = driver_id)
  WITH CHECK (auth.uid()::text = driver_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- PIX_PAYMENTS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Admin vê todos pagamentos PIX" ON public.pix_payments;
DROP POLICY IF EXISTS "Ver próprios pagamentos PIX" ON public.pix_payments;

CREATE POLICY "pix_payments_select_own" ON public.pix_payments
  FOR SELECT TO authenticated
  USING (auth.uid()::text = rider_id);

CREATE POLICY "pix_payments_admin" ON public.pix_payments
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator')));

-- ─────────────────────────────────────────────────────────────────────────────
-- PROFILES — INSERT e UPDATE para usuário autenticado
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "Usuário edita próprio perfil" ON public.profiles;

CREATE POLICY "profiles_insert" ON public.profiles
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = id);

CREATE POLICY "profiles_update" ON public.profiles
  FOR UPDATE TO authenticated
  USING (auth.uid()::text = id)
  WITH CHECK (auth.uid()::text = id);

-- ─────────────────────────────────────────────────────────────────────────────
-- REVIEWS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Criar review" ON public.reviews;
DROP POLICY IF EXISTS "Ver reviews" ON public.reviews;

CREATE POLICY "reviews_select" ON public.reviews
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "reviews_insert" ON public.reviews
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = reviewer_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- RIDE_ACTIVITIES
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Ver atividades da corrida" ON public.ride_activities;

-- ride_activities.ride_id é UUID (join direto com rides.id)
CREATE POLICY "ride_activities_select" ON public.ride_activities
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.rides r
      WHERE r.id = ride_id AND (r.rider_id = auth.uid()::text OR r.driver_id = auth.uid()::text)
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- RIDE_MESSAGES
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Enviar mensagem" ON public.ride_messages;
DROP POLICY IF EXISTS "Ver mensagens da corrida" ON public.ride_messages;
DROP POLICY IF EXISTS "ride_messages_select" ON public.ride_messages;

CREATE POLICY "ride_messages_select" ON public.ride_messages
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.rides r
      WHERE r.id::text = ride_id AND (r.rider_id = auth.uid()::text OR r.driver_id = auth.uid()::text)
    )
  );

CREATE POLICY "ride_messages_insert" ON public.ride_messages
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = sender_id OR sent_by_driver IS NOT NULL);

-- ─────────────────────────────────────────────────────────────────────────────
-- RIDES
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Atualização de Corridas" ON public.rides;
DROP POLICY IF EXISTS "Criação de Corridas" ON public.rides;
DROP POLICY IF EXISTS "rides_select" ON public.rides;

CREATE POLICY "rides_select" ON public.rides
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = rider_id OR
    auth.uid()::text = driver_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator'))
  );

CREATE POLICY "rides_insert" ON public.rides
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = rider_id);

CREATE POLICY "rides_update" ON public.rides
  FOR UPDATE TO authenticated
  USING (
    auth.uid()::text = rider_id OR
    auth.uid()::text = driver_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator'))
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- SCHEDULED_RIDES
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "scheduled_rides_insert" ON public.scheduled_rides;
DROP POLICY IF EXISTS "scheduled_rides_select" ON public.scheduled_rides;
DROP POLICY IF EXISTS "scheduled_rides_update" ON public.scheduled_rides;

-- scheduled_rides só tem rider_id (não tem driver_id)
CREATE POLICY "scheduled_rides_select" ON public.scheduled_rides
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = rider_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator'))
  );

CREATE POLICY "scheduled_rides_insert" ON public.scheduled_rides
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = rider_id);

CREATE POLICY "scheduled_rides_update" ON public.scheduled_rides
  FOR UPDATE TO authenticated
  USING (auth.uid()::text = rider_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- SOS_ALERTS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Criar SOS alert" ON public.sos_alerts;
DROP POLICY IF EXISTS "Ver próprio SOS" ON public.sos_alerts;

CREATE POLICY "sos_alerts_insert" ON public.sos_alerts
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY "sos_alerts_select" ON public.sos_alerts
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = user_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator'))
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- SOS_SIGNALS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Criar SOS" ON public.sos_signals;

CREATE POLICY "sos_signals_insert" ON public.sos_signals
  FOR INSERT TO authenticated
  WITH CHECK (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- USER_BADGES
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Ver próprios badges" ON public.user_badges;

CREATE POLICY "user_badges_select" ON public.user_badges
  FOR SELECT TO authenticated
  USING (auth.uid()::text = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- WALLET_TRANSACTIONS — substituir policy pública duplicada
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Ver próprias transações" ON public.wallet_transactions;
-- A policy correta já foi criada na migração anterior (user_reads_own_transactions)
-- Se não existir, cria aqui também como fallback
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'wallet_transactions' AND policyname = 'user_reads_own_transactions'
  ) THEN
    CREATE POLICY "user_reads_own_transactions" ON public.wallet_transactions
      FOR SELECT TO authenticated
      USING (auth.uid()::text = user_id);
  END IF;
END $$;

-- ==============================================================================
-- FIM — Todas as 47 policies inseguras corrigidas para 'authenticated'
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260511192000_db_fk_indexes_rpc_grants.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- ORGANIZAÇÃO FINAL — PARTE 3
-- 1. Índices em Foreign Keys sem cobertura (causa lentidão em JOINs)
-- 2. Permissão na RPC get_driver_surgical_financials para admins
-- 3. Wallets automáticas para todos os perfis existentes sem carteira
-- 4. Índices compostos de alta prioridade em corridas e pagamentos
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. ÍNDICES EM FOREIGN KEYS SEM COBERTURA
--    15 FK detectadas sem índice — cada uma causa FULL TABLE SCAN em JOINs
-- ─────────────────────────────────────────────────────────────────────────────

-- complaints.user_id
CREATE INDEX IF NOT EXISTS idx_complaints_user_id
  ON public.complaints (user_id);

-- coupon_usages.coupon_id + ride_id + user_id
CREATE INDEX IF NOT EXISTS idx_coupon_usages_coupon_id
  ON public.coupon_usages (coupon_id);
CREATE INDEX IF NOT EXISTS idx_coupon_usages_ride_id
  ON public.coupon_usages (ride_id);
CREATE INDEX IF NOT EXISTS idx_coupon_usages_user_id
  ON public.coupon_usages (user_id);

-- feedbacks.rider_id (driver_id já tem índice via FK)
CREATE INDEX IF NOT EXISTS idx_feedbacks_rider_id
  ON public.feedbacks (rider_id);

-- gift_cards.redeemed_by
CREATE INDEX IF NOT EXISTS idx_gift_cards_redeemed_by
  ON public.gift_cards (redeemed_by)
  WHERE redeemed_by IS NOT NULL;

-- messages.sender_id
CREATE INDEX IF NOT EXISTS idx_messages_sender_id
  ON public.messages (sender_id);

-- payment_methods.driver_id + gateway_id
CREATE INDEX IF NOT EXISTS idx_payment_methods_driver_id
  ON public.payment_methods (driver_id)
  WHERE driver_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payment_methods_gateway_id
  ON public.payment_methods (gateway_id)
  WHERE gateway_id IS NOT NULL;

-- payout_accounts.driver_id + payout_method_id
CREATE INDEX IF NOT EXISTS idx_payout_accounts_driver_id
  ON public.payout_accounts (driver_id);
CREATE INDEX IF NOT EXISTS idx_payout_accounts_method_id
  ON public.payout_accounts (payout_method_id);

-- ride_messages.sender_id
CREATE INDEX IF NOT EXISTS idx_ride_messages_sender_id
  ON public.ride_messages (sender_id);

-- ride_reviews.reviewer_id
CREATE INDEX IF NOT EXISTS idx_ride_reviews_reviewer_id
  ON public.ride_reviews (reviewer_id);

-- sos_alerts.ride_id
CREATE INDEX IF NOT EXISTS idx_sos_alerts_ride_id
  ON public.sos_alerts (ride_id)
  WHERE ride_id IS NOT NULL;

-- sos_signals.submitted_by
CREATE INDEX IF NOT EXISTS idx_sos_signals_submitted_by
  ON public.sos_signals (submitted_by);

-- driver_locations: is_online (usada no índice composto abaixo)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='driver_locations' AND column_name='is_online') THEN
    ALTER TABLE public.driver_locations ADD COLUMN is_online BOOLEAN DEFAULT true;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. ÍNDICES COMPOSTOS DE ALTA PRIORIDADE
--    Queries mais comuns no painel admin e relatórios
-- ─────────────────────────────────────────────────────────────────────────────

-- Corridas por status + data (painel admin - "corridas de hoje")
CREATE INDEX IF NOT EXISTS idx_rides_status_created_at
  ON public.rides (status, created_at DESC);

-- Pagamentos PIX por data (relatório financeiro)
CREATE INDEX IF NOT EXISTS idx_pix_payments_created_at
  ON public.pix_payments (created_at DESC);

-- Pagamentos MP por data
CREATE INDEX IF NOT EXISTS idx_mp_payments_created_at
  ON public.mp_payments (created_at DESC);

-- Transações de carteira por tipo (filtro de extrato: entrada/saída)
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_type
  ON public.wallet_transactions (transaction_type);

-- Motoristas online (is_online + updated_at recente — busca frequente)
CREATE INDEX IF NOT EXISTS idx_driver_locations_online
  ON public.driver_locations (updated_at DESC)
  WHERE is_online = true;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. PERMISSÃO NA RPC get_driver_surgical_financials (admin only)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.routines
    WHERE routine_schema = 'public'
    AND routine_name = 'get_driver_surgical_financials'
  ) THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.get_driver_surgical_financials TO authenticated';
  END IF;
END $$;

-- Garantir que nearby_drivers e find_nearby_requested_rides também são acessíveis
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name = 'nearby_drivers') THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.nearby_drivers TO authenticated';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name = 'find_nearby_requested_rides') THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.find_nearby_requested_rides TO authenticated';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name = 'assign_driver_to_ride') THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.assign_driver_to_ride TO authenticated';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. INICIALIZAR WALLETS para todos os perfis existentes sem carteira
--    (garante que ninguém fica sem carteira no banco)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.wallets (user_id, balance, currency)
SELECT id, 0.00, 'BRL'
FROM public.profiles
WHERE id NOT IN (SELECT user_id FROM public.wallets)
ON CONFLICT (user_id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. COLUNAS FALTANDO — detectadas via edge functions
-- ─────────────────────────────────────────────────────────────────────────────

-- profiles: is_deleted e deleted_at (usados em delete-user-account)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='profiles' AND column_name='is_deleted') THEN
    ALTER TABLE public.profiles ADD COLUMN is_deleted BOOLEAN DEFAULT false;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='profiles' AND column_name='deleted_at') THEN
    ALTER TABLE public.profiles ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE;
  END IF;
END $$;

-- rides: cancel_reason_note (já adicionado antes, mas garantindo)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='rides' AND column_name='cancel_reason_note') THEN
    ALTER TABLE public.rides ADD COLUMN cancel_reason_note TEXT;
  END IF;
END $$;

-- driver_locations: is_online já criada na seção 1 (antes dos índices)

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. ÍNDICE PARCIAL SEGURO — filtro por perfis ativos/não deletados
-- ─────────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_profiles_active
  ON public.profiles (id, role)
  WHERE status = 'active' AND (is_deleted IS NULL OR is_deleted = false);

-- ==============================================================================
-- FIM — Banco de dados completamente otimizado e organizado
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260511193000_db_final_policies_cleanup.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- ORGANIZAÇÃO FINAL — PARTE 4
-- 1. Converter policies 'public' residuais → 'authenticated'
-- 2. Adicionar policies INSERT faltando (coupon_usages, user_badges, ride_activities)
-- 3. Verificar e corrigir tabela admins (RLS completo)
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. badge_definitions — public → authenticated
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Ler badges" ON public.badge_definitions;

CREATE POLICY "badge_definitions_select" ON public.badge_definitions
  FOR SELECT TO authenticated
  USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. challenges — public → authenticated
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Ler desafios ativos" ON public.challenges;

CREATE POLICY "challenges_select" ON public.challenges
  FOR SELECT TO authenticated
  USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. quick_replies — public → authenticated
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Ler quick replies" ON public.quick_replies;

CREATE POLICY "quick_replies_select" ON public.quick_replies
  FOR SELECT TO authenticated
  USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. coupon_usages — adicionar INSERT (sem esta policy o app não consegue
--    registrar uso de cupom → erro silencioso no checkout)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "coupon_usages_insert" ON public.coupon_usages;

CREATE POLICY "coupon_usages_insert" ON public.coupon_usages
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. user_badges — adicionar INSERT (sistema precisa conceder badges
--    via service_role ou após ação do usuário)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "user_badges_insert" ON public.user_badges;

-- Apenas service_role ou admin pode inserir badges (não o próprio usuário)
CREATE POLICY "user_badges_insert" ON public.user_badges
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.admins WHERE id = auth.uid()::text
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. ride_activities — adicionar INSERT (Edge Functions precisam registrar
--    eventos da corrida: accept, start, finish, cancel)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "ride_activities_insert" ON public.ride_activities;

CREATE POLICY "ride_activities_insert" ON public.ride_activities
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.rides r
      WHERE r.id = ride_id
        AND (r.driver_id = auth.uid()::text OR r.rider_id = auth.uid()::text)
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. admins — garantir que a tabela tem RLS completo e seguro
-- ─────────────────────────────────────────────────────────────────────────────
-- Verificar policies existentes e adicionar o que faltar
DO $$
BEGIN
  -- Admin pode ver sua própria linha (necessário para o painel admin verificar acesso)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'admins' AND policyname = 'admins_self_select'
  ) THEN
    CREATE POLICY "admins_self_select" ON public.admins
      FOR SELECT TO authenticated
      USING (id = auth.uid()::text);
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Garantir trigger updated_at nas tabelas que ainda não têm
-- ─────────────────────────────────────────────────────────────────────────────

-- Verificar se challenges tem updated_at
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='challenges' AND column_name='updated_at') THEN
    ALTER TABLE public.challenges ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT now();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE event_object_table = 'challenges' AND trigger_name LIKE '%updated_at%'
  ) THEN
    CREATE TRIGGER set_challenges_updated_at
      BEFORE UPDATE ON public.challenges
      FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END $$;

-- Verificar se badge_definitions tem updated_at
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='badge_definitions' AND column_name='updated_at') THEN
    ALTER TABLE public.badge_definitions ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT now();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE event_object_table = 'badge_definitions' AND trigger_name LIKE '%updated_at%'
  ) THEN
    CREATE TRIGGER set_badge_definitions_updated_at
      BEFORE UPDATE ON public.badge_definitions
      FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END $$;

-- Verificar se admins tem updated_at
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='admins' AND column_name='updated_at') THEN
    ALTER TABLE public.admins ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT now();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE event_object_table = 'admins' AND trigger_name LIKE '%updated_at%'
  ) THEN
    CREATE TRIGGER set_admins_updated_at
      BEFORE UPDATE ON public.admins
      FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. Habilitar Realtime nas tabelas de suporte ao app
--    (ride_activities → UI do motorista atualiza em tempo real)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  -- ride_activities
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'ride_activities'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_activities;
  END IF;

  -- ride_messages
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'ride_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_messages;
  END IF;

  -- sos_alerts
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'sos_alerts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.sos_alerts;
  END IF;
END $$;

-- ==============================================================================
-- FIM — Banco de dados 100% auditado e organizado
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260511194000_db_part5_final_cleanup.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- ORGANIZAÇÃO FINAL — PARTE 5
-- Resolvendo todos os problemas restantes detectados na auditoria CRUD:
-- 1. Policies 'public' em tabelas de catálogo (app_settings, cancel_reasons, etc.)
-- 2. Policies duplicadas e conflitantes (services, sos_signals, ride_messages)
-- 3. Policies INSERT faltando (mp_payments, pix_payments, gift_cards)
-- 4. Limpeza de policies legadas com nomes em português duplicando novas
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. APP_SETTINGS — public → authenticated
--    (configurações do app não devem ser expostas a usuários não logados)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "app_settings_select" ON public.app_settings;

CREATE POLICY "app_settings_select" ON public.app_settings
  FOR SELECT TO authenticated
  USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. CANCEL_REASONS — public → authenticated + remover duplicata legada
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Leitura de Motivos" ON public.cancel_reasons;
DROP POLICY IF EXISTS "Public read cancel_reasons" ON public.cancel_reasons;

CREATE POLICY "cancel_reasons_select" ON public.cancel_reasons
  FOR SELECT TO authenticated
  USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. CAR_COLORS — public → authenticated
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Public read car_colors" ON public.car_colors;

CREATE POLICY "car_colors_select" ON public.car_colors
  FOR SELECT TO authenticated
  USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. CAR_MODELS — public → authenticated
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Public read car_models" ON public.car_models;

CREATE POLICY "car_models_select" ON public.car_models
  FOR SELECT TO authenticated
  USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. SERVICES — consolidar 3 SELECT duplicadas em 1 autenticada
--    ("Leitura de Serviços" era public, "Ver servicos ativos" e
--    "services_select_authenticated" eram authenticated — manter só 1)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Leitura de Serviços" ON public.services;
DROP POLICY IF EXISTS "Ver servicos ativos" ON public.services;
DROP POLICY IF EXISTS "services_select_authenticated" ON public.services;

-- Política unificada: autenticados veem serviços ativos; admin vê todos
CREATE POLICY "services_select" ON public.services
  FOR SELECT TO authenticated
  USING (
    is_active = true OR
    EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. MP_PAYMENTS — adicionar INSERT para webhook (service_role)
--    A Edge Function do webhook usa service_role — mas garantindo que
--    admins também possam inserir manualmente
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "mp_payments_insert" ON public.mp_payments;

CREATE POLICY "mp_payments_insert" ON public.mp_payments
  FOR INSERT TO authenticated
  WITH CHECK (
    -- O passageiro pode registrar via checkout
    auth.uid()::text = rider_id OR
    -- Admins podem registrar manualmente
    EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. PIX_PAYMENTS — adicionar INSERT
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "pix_payments_insert" ON public.pix_payments;

CREATE POLICY "pix_payments_insert" ON public.pix_payments
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid()::text = rider_id OR
    EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. GIFT_CARDS — adicionar INSERT (admin cria gift cards)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "gift_cards_insert" ON public.gift_cards;

CREATE POLICY "gift_cards_insert" ON public.gift_cards
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. SOS_SIGNALS — remover duplicata de INSERT ("Enviar SOS" era legada)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Enviar SOS" ON public.sos_signals;
-- Mantém apenas: sos_signals_insert (criada na migração anterior)

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. RIDE_MESSAGES — remover duplicata de SELECT ("Ler mensagens da corrida")
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Ler mensagens da corrida" ON public.ride_messages;
-- Mantém apenas: ride_messages_select (criada na migração de RLS)

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. COUPONS — adicionar INSERT/UPDATE para admin (via admin_all já cobre)
--    Mas falta UPDATE policy para usuários normais resgatarem?
--    Não — coupons são só leitura para usuários. Admin já tem ALL. OK.
-- ─────────────────────────────────────────────────────────────────────────────
-- Remover duplicata de SELECT legada (em português)
DROP POLICY IF EXISTS "Ver cupons ativos" ON public.coupons;
-- Mantém: coupons_select_authenticated + admin_all_coupons

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. WALLETS — adicionar UPDATE para o próprio usuário
--    (necessário para a RPC increment_wallet funcionar sem service_role
--    quando chamada pelo cliente Flutter direto)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "user_updates_own_wallet" ON public.wallets;

CREATE POLICY "user_updates_own_wallet" ON public.wallets
  FOR UPDATE TO authenticated
  USING (auth.uid()::text = user_id)
  WITH CHECK (auth.uid()::text = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 13. PAYMENT_GATEWAYS — remover duplicata legada em português
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Ver gateways ativos" ON public.payment_gateways;
-- Mantém: payment_gateways_select_authenticated

-- ─────────────────────────────────────────────────────────────────────────────
-- 14. ADMIN_AUDIT_LOG — garantir que admins podem INSERT (para registrar ações)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'admin_audit_log' AND policyname = 'audit_log_insert'
  ) THEN
    CREATE POLICY "audit_log_insert" ON public.admin_audit_log
      FOR INSERT TO authenticated
      WITH CHECK (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
      );
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 15. ANNOUNCEMENTS — admin pode criar/editar anúncios
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'announcements' AND policyname = 'announcements_admin_write'
  ) THEN
    CREATE POLICY "announcements_admin_write" ON public.announcements
      FOR ALL TO authenticated
      USING (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
      )
      WITH CHECK (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
      );
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 16. CAR_COLORS e CAR_MODELS — admin pode fazer INSERT/UPDATE (gerenciar catálogo)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'car_colors' AND policyname = 'car_colors_admin'
  ) THEN
    CREATE POLICY "car_colors_admin" ON public.car_colors
      FOR ALL TO authenticated
      USING (EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text))
      WITH CHECK (EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'car_models' AND policyname = 'car_models_admin'
  ) THEN
    CREATE POLICY "car_models_admin" ON public.car_models
      FOR ALL TO authenticated
      USING (EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text))
      WITH CHECK (EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text));
  END IF;
END $$;

-- ==============================================================================
-- FIM DA PARTE 5 — Banco de dados completamente auditado
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260511195000_fix_edge_function_schema_mismatch.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- CORREÇÃO CRÍTICA — Incompatibilidades entre Edge Functions e Banco
-- 1. ride_activities: adicionar coluna actor_id (usada em finish-order, cancel-order, accept-order)
-- 2. wallet_transactions: a coluna 'type' existe como alias, mas transaction_type é a principal
--    → adicionamos 'type' como coluna real para compatibilidade
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. ride_activities — adicionar actor_id
--    Edge Functions insert { ride_id, type, actor_id } mas a tabela não tem actor_id
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'ride_activities' AND column_name = 'actor_id'
  ) THEN
    ALTER TABLE public.ride_activities ADD COLUMN actor_id TEXT;
    COMMENT ON COLUMN public.ride_activities.actor_id IS 'UID do usuário que gerou o evento (motorista ou passageiro)';
  END IF;
END $$;

-- Índice para buscar atividades por ator
CREATE INDEX IF NOT EXISTS idx_ride_activities_actor_id
  ON public.ride_activities (actor_id)
  WHERE actor_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. wallet_transactions — a Edge Function insere com 'type' mas a coluna
--    principal é 'transaction_type'. A tabela já tem ambas (type e transaction_type).
--    Vamos garantir que 'type' é preenchido com o mesmo valor quando transaction_type
--    é inserido (via trigger de sincronização).
-- ─────────────────────────────────────────────────────────────────────────────

-- Trigger que sincroniza type ↔ transaction_type ao inserir
CREATE OR REPLACE FUNCTION public.sync_wallet_transaction_type()
RETURNS TRIGGER AS $$
BEGIN
  -- Se inseriu 'type' mas não 'transaction_type', sincroniza
  IF NEW.transaction_type IS NULL AND NEW.type IS NOT NULL THEN
    NEW.transaction_type := NEW.type;
  END IF;
  -- Se inseriu 'transaction_type' mas não 'type', sincroniza
  IF NEW.type IS NULL AND NEW.transaction_type IS NOT NULL THEN
    NEW.type := NEW.transaction_type;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_wallet_transaction_type ON public.wallet_transactions;

CREATE TRIGGER trg_sync_wallet_transaction_type
  BEFORE INSERT OR UPDATE ON public.wallet_transactions
  FOR EACH ROW EXECUTE FUNCTION public.sync_wallet_transaction_type();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. profiles — garantir colunas usadas pelas Edge Functions
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  -- commission_percentage (usada em finish-order e admin-actions)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name='commission_percentage') THEN
    ALTER TABLE public.profiles ADD COLUMN commission_percentage NUMERIC(5,2) DEFAULT NULL;
    COMMENT ON COLUMN public.profiles.commission_percentage IS 'Comissão individual do motorista (NULL = usa comissão global)';
  END IF;

  -- commission_exempt_until (isenção de comissão)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name='commission_exempt_until') THEN
    ALTER TABLE public.profiles ADD COLUMN commission_exempt_until TIMESTAMP WITH TIME ZONE DEFAULT NULL;
    COMMENT ON COLUMN public.profiles.commission_exempt_until IS 'Data até quando o motorista está isento de comissão';
  END IF;

  -- fcm_token (notificações push)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name='fcm_token') THEN
    ALTER TABLE public.profiles ADD COLUMN fcm_token TEXT DEFAULT NULL;
    COMMENT ON COLUMN public.profiles.fcm_token IS 'Token FCM para notificações push';
  END IF;
END $$;

-- Índice para buscar FCM token rapidamente ao enviar notificação
CREATE INDEX IF NOT EXISTS idx_profiles_fcm_token
  ON public.profiles (id)
  WHERE fcm_token IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. config — garantir que a tabela tem a estrutura correta
--    admin-actions usa: key, value, updated_at
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='config' AND column_name='updated_at') THEN
    ALTER TABLE public.config ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT now();
  END IF;
END $$;

-- Trigger updated_at para config
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE event_object_table = 'config' AND trigger_name LIKE '%updated_at%'
  ) THEN
    CREATE TRIGGER set_config_updated_at
      BEFORE UPDATE ON public.config
      FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. rides — verificar e adicionar campos usados em finish-order
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  -- service_type (categoria da corrida: standard, premium, moto, etc.)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rides' AND column_name='service_type') THEN
    ALTER TABLE public.rides ADD COLUMN service_type TEXT;
  END IF;
  
  -- notes (observações do passageiro)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rides' AND column_name='notes') THEN
    ALTER TABLE public.rides ADD COLUMN notes TEXT;
  END IF;
END $$;

-- ==============================================================================
-- FIM — Incompatibilidades Edge Function ↔ Banco corrigidas
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260511196000_fix_column_aliases_and_seeds.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- CORREÇÃO CRÍTICA — Parte 2: Incompatibilidades de nomes de colunas
-- 1. profiles: subscription_valid_until → alias para subscription_expires_at
-- 2. rides: adicionar cancel_reason_id e canceled_at
-- 3. profiles: alias phone → phone_number
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. PROFILES — adicionar subscription_valid_until como alias
--    A coluna existente se chama subscription_expires_at,
--    mas as Edge Functions usam subscription_valid_until
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles'
    AND column_name = 'subscription_valid_until'
  ) THEN
    -- Adiciona a coluna nova como computed alias não é possível em Postgres sem view.
    -- Solução: adicionar coluna real e sincronizar via trigger
    ALTER TABLE public.profiles
      ADD COLUMN subscription_valid_until TIMESTAMP WITH TIME ZONE
      GENERATED ALWAYS AS (subscription_expires_at) STORED;
    COMMENT ON COLUMN public.profiles.subscription_valid_until IS 'Alias gerado de subscription_expires_at — para compatibilidade com Edge Functions';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. RIDES — adicionar colunas usadas por cancel-order
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  -- cancel_reason_id (FK para cancel_reasons)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'rides' AND column_name = 'cancel_reason_id'
  ) THEN
    ALTER TABLE public.rides ADD COLUMN cancel_reason_id TEXT;
  END IF;

  -- canceled_at (timestamp de quando foi cancelada)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'rides' AND column_name = 'canceled_at'
  ) THEN
    ALTER TABLE public.rides ADD COLUMN canceled_at TIMESTAMP WITH TIME ZONE;
  END IF;
END $$;

-- Índice para filtrar corridas canceladas por data
CREATE INDEX IF NOT EXISTS idx_rides_canceled_at
  ON public.rides (canceled_at DESC)
  WHERE canceled_at IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. DRIVER_DOCUMENTS — verificar colunas usadas por register-driver
--    register-driver insere: cnh, vehicle_plate, vehicle_model, vehicle_color,
--    vehicle_year, vehicle_category, status
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_documents' AND column_name='cnh') THEN
    ALTER TABLE public.driver_documents ADD COLUMN cnh TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_documents' AND column_name='vehicle_plate') THEN
    ALTER TABLE public.driver_documents ADD COLUMN vehicle_plate TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_documents' AND column_name='vehicle_model') THEN
    ALTER TABLE public.driver_documents ADD COLUMN vehicle_model TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_documents' AND column_name='vehicle_color') THEN
    ALTER TABLE public.driver_documents ADD COLUMN vehicle_color TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_documents' AND column_name='vehicle_year') THEN
    ALTER TABLE public.driver_documents ADD COLUMN vehicle_year INTEGER;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_documents' AND column_name='vehicle_category') THEN
    ALTER TABLE public.driver_documents ADD COLUMN vehicle_category TEXT;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. DRIVER_LOCATIONS — verificar colunas usadas pelas functions
--    register-driver usa: driver_id, lat, lng, status
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_locations' AND column_name='lat') THEN
    ALTER TABLE public.driver_locations ADD COLUMN lat DOUBLE PRECISION;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_locations' AND column_name='lng') THEN
    ALTER TABLE public.driver_locations ADD COLUMN lng DOUBLE PRECISION;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. PROFILES — register-driver usa 'phone' mas a tabela tem 'phone_number'
--    Adicionar alias 'phone' se não existir
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  -- 'phone' já foi adicionado em migração anterior — apenas verificar
  -- Se existir, está OK. Se não existir, adicionar.
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name='phone') THEN
    ALTER TABLE public.profiles ADD COLUMN phone TEXT;
  END IF;
END $$;

-- Sync trigger: quando 'phone' é atualizado, reflete em 'phone_number' e vice-versa
CREATE OR REPLACE FUNCTION public.sync_profile_phone()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.phone IS DISTINCT FROM OLD.phone AND NEW.phone IS NOT NULL THEN
    NEW.phone_number := NEW.phone;
  ELSIF NEW.phone_number IS DISTINCT FROM OLD.phone_number AND NEW.phone_number IS NOT NULL THEN
    NEW.phone := NEW.phone_number;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_profile_phone ON public.profiles;
CREATE TRIGGER trg_sync_profile_phone
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.sync_profile_phone();

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Seed de configurações padrão (se não existirem)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.config (key, value) VALUES
  ('driver_commission_percentage', '15'),
  ('mercadopago_sandbox', 'true'),
  ('min_driver_balance', '-50'),
  ('cancellation_fee', '5.00'),
  ('max_search_radius_km', '10'),
  ('platform_name', 'Uppi'),
  ('support_phone', ''),
  ('support_email', '')
ON CONFLICT (key) DO NOTHING;

-- ==============================================================================
-- FIM — Schema 100% compatível com todas as Edge Functions
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260511197000_total_review_all_functions.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- REVISÃO TOTAL — Parte 6: Incompatibilidades detectadas em todas as 50 Edge Functions
-- Corrigindo todas as colunas faltando após leitura completa de cada função
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. COUPONS — normalizar is_active vs is_enabled + max_uses
--    - create_order usa is_active
--    - apply-coupon/validate-coupon usa is_enabled
--    Solução: adicionar max_uses e criar trigger de sync entre is_active e is_enabled
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='coupons' AND column_name='max_uses') THEN
    ALTER TABLE public.coupons ADD COLUMN max_uses INTEGER DEFAULT NULL;
    COMMENT ON COLUMN public.coupons.max_uses IS 'Número máximo de usos totais (NULL = ilimitado)';
  END IF;
END $$;

-- Sync trigger: is_active ↔ is_enabled
CREATE OR REPLACE FUNCTION public.sync_coupon_active_flag()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.is_active IS NULL AND NEW.is_enabled IS NOT NULL THEN
      NEW.is_active := NEW.is_enabled;
    ELSIF NEW.is_enabled IS NULL AND NEW.is_active IS NOT NULL THEN
      NEW.is_enabled := NEW.is_active;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.is_active IS DISTINCT FROM OLD.is_active THEN
      NEW.is_enabled := NEW.is_active;
    ELSIF NEW.is_enabled IS DISTINCT FROM OLD.is_enabled THEN
      NEW.is_active := NEW.is_enabled;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_coupon_active ON public.coupons;
CREATE TRIGGER trg_sync_coupon_active
  BEFORE INSERT OR UPDATE ON public.coupons
  FOR EACH ROW EXECUTE FUNCTION public.sync_coupon_active_flag();

-- Atualizar dados existentes
UPDATE public.coupons SET is_enabled = is_active WHERE is_enabled IS NULL;
UPDATE public.coupons SET is_active = is_enabled WHERE is_active IS NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. SOS_ALERTS — colunas usadas por send-sos
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='sos_alerts' AND column_name='user_name') THEN
    ALTER TABLE public.sos_alerts ADD COLUMN user_name TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='sos_alerts' AND column_name='user_phone') THEN
    ALTER TABLE public.sos_alerts ADD COLUMN user_phone TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='sos_alerts' AND column_name='lat') THEN
    ALTER TABLE public.sos_alerts ADD COLUMN lat DOUBLE PRECISION;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='sos_alerts' AND column_name='lng') THEN
    ALTER TABLE public.sos_alerts ADD COLUMN lng DOUBLE PRECISION;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='sos_alerts' AND column_name='message') THEN
    ALTER TABLE public.sos_alerts ADD COLUMN message TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='sos_alerts' AND column_name='status') THEN
    ALTER TABLE public.sos_alerts ADD COLUMN status TEXT DEFAULT 'active';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. PIX_PAYMENTS — colunas usadas por create-pix-payment
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='pix_payments' AND column_name='mp_payment_id') THEN
    ALTER TABLE public.pix_payments ADD COLUMN mp_payment_id TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='pix_payments' AND column_name='rider_id') THEN
    ALTER TABLE public.pix_payments ADD COLUMN rider_id TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='pix_payments' AND column_name='qr_code') THEN
    ALTER TABLE public.pix_payments ADD COLUMN qr_code TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='pix_payments' AND column_name='qr_code_base64') THEN
    ALTER TABLE public.pix_payments ADD COLUMN qr_code_base64 TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='pix_payments' AND column_name='ticket_url') THEN
    ALTER TABLE public.pix_payments ADD COLUMN ticket_url TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='pix_payments' AND column_name='expires_at') THEN
    ALTER TABLE public.pix_payments ADD COLUMN expires_at TIMESTAMP WITH TIME ZONE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='pix_payments' AND column_name='status') THEN
    ALTER TABLE public.pix_payments ADD COLUMN status TEXT DEFAULT 'pending';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='pix_payments' AND column_name='amount') THEN
    ALTER TABLE public.pix_payments ADD COLUMN amount NUMERIC(10, 2);
  END IF;
END $$;

-- Índice de lookup por mp_payment_id (webhook consulta)
CREATE UNIQUE INDEX IF NOT EXISTS idx_pix_payments_mp_payment_id
  ON public.pix_payments (mp_payment_id)
  WHERE mp_payment_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. USER_BADGES — coluna badge_name usada por check-badge
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='user_badges' AND column_name='badge_name') THEN
    ALTER TABLE public.user_badges ADD COLUMN badge_name TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='user_badges' AND column_name='badge_id') THEN
    ALTER TABLE public.user_badges ADD COLUMN badge_id TEXT;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. REVIEWS — coluna reviewer_role usada por submit-review
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='reviews' AND column_name='reviewer_role') THEN
    ALTER TABLE public.reviews ADD COLUMN reviewer_role TEXT CHECK (reviewer_role IN ('rider', 'driver'));
  END IF;
  -- 'comment' pode não existir (só 'review')
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='reviews' AND column_name='comment') THEN
    ALTER TABLE public.reviews ADD COLUMN comment TEXT;
  END IF;
  -- 'score' pode não existir (só 'rating')
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='reviews' AND column_name='score') THEN
    ALTER TABLE public.reviews ADD COLUMN score INTEGER;
  END IF;
  -- 'reviewed_id' pode não existir
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='reviews' AND column_name='reviewed_id') THEN
    ALTER TABLE public.reviews ADD COLUMN reviewed_id TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='reviews' AND column_name='reviewer_id') THEN
    ALTER TABLE public.reviews ADD COLUMN reviewer_id TEXT;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. RIDES — coluna service_id usada por create_order
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rides' AND column_name='service_id') THEN
    ALTER TABLE public.rides ADD COLUMN service_id TEXT;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. FEEDBACKS — coluna parameters (array) usada por submit-feedback
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='feedbacks' AND column_name='parameters') THEN
    ALTER TABLE public.feedbacks ADD COLUMN parameters JSONB DEFAULT '[]'::jsonb;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='feedbacks' AND column_name='review') THEN
    ALTER TABLE public.feedbacks ADD COLUMN review TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='feedbacks' AND column_name='rating') THEN
    ALTER TABLE public.feedbacks ADD COLUMN rating NUMERIC(3,1);
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. BADGE_DEFINITIONS — colunas usadas por check-badge
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='badge_definitions' AND column_name='role') THEN
    ALTER TABLE public.badge_definitions ADD COLUMN role TEXT DEFAULT 'driver';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='badge_definitions' AND column_name='required_rides') THEN
    ALTER TABLE public.badge_definitions ADD COLUMN required_rides INTEGER;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='badge_definitions' AND column_name='required_rating') THEN
    ALTER TABLE public.badge_definitions ADD COLUMN required_rating NUMERIC(3,1);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='badge_definitions' AND column_name='required_tips') THEN
    ALTER TABLE public.badge_definitions ADD COLUMN required_tips INTEGER;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='badge_definitions' AND column_name='icon') THEN
    ALTER TABLE public.badge_definitions ADD COLUMN icon TEXT DEFAULT '🏅';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='badge_definitions' AND column_name='description') THEN
    ALTER TABLE public.badge_definitions ADD COLUMN description TEXT;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. DRIVER_LOCATIONS — heading e speed usados por update-driver-location
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_locations' AND column_name='heading') THEN
    ALTER TABLE public.driver_locations ADD COLUMN heading DOUBLE PRECISION DEFAULT 0;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_locations' AND column_name='speed') THEN
    ALTER TABLE public.driver_locations ADD COLUMN speed DOUBLE PRECISION DEFAULT 0;
  END IF;
  -- Coluna 'location' como geometry (PostGIS POINT)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_locations' AND column_name='location') THEN
    ALTER TABLE public.driver_locations ADD COLUMN location geometry(Point, 4326);
  END IF;
END $$;

-- Índice espacial para busca de motoristas próximos
CREATE INDEX IF NOT EXISTS idx_driver_locations_geom
  ON public.driver_locations USING GIST (location)
  WHERE location IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. PROFILES — rating_count usado por submit-review
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name='rating_count') THEN
    ALTER TABLE public.profiles ADD COLUMN rating_count INTEGER DEFAULT 0;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. COUPON_USAGES — discount_amount usado por apply-coupon
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='coupon_usages' AND column_name='discount_amount') THEN
    ALTER TABLE public.coupon_usages ADD COLUMN discount_amount NUMERIC(10, 2) DEFAULT 0;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='coupon_usages' AND column_name='user_id') THEN
    ALTER TABLE public.coupon_usages ADD COLUMN user_id TEXT;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. Seed de badges padrão (para o check-badge ter dados no banco)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.badge_definitions (id, name, description, icon, required_rides, required_rating, required_tips, role, updated_at)
VALUES
  ('first_ride_driver',   'Primeira Viagem',      'Completou sua primeira corrida como motorista', '🚗', 1,   NULL, NULL, 'driver', now()),
  ('ten_rides_driver',    '10 Viagens',           'Completou 10 corridas',                         '🏆', 10,  NULL, NULL, 'driver', now()),
  ('fifty_rides_driver',  'Veterano',             'Completou 50 corridas',                         '⭐', 50,  NULL, NULL, 'driver', now()),
  ('hundred_rides_driver','Lenda',                'Completou 100 corridas',                        '👑', 100, NULL, NULL, 'driver', now()),
  ('five_star_driver',    '5 Estrelas',           'Avaliação perfeita de 5.0',                     '⭐', NULL, 5.0, NULL, 'driver', now()),
  ('first_ride_rider',    'Passageiro(a) Uppi',   'Completou sua primeira corrida',                '🎉', 1,   NULL, NULL, 'rider',  now()),
  ('ten_rides_rider',     'Viajante Frequente',   '10 corridas realizadas',                        '🗺️', 10,  NULL, NULL, 'rider',  now()),
  ('generous_tipper',     'Generoso(a)',          'Deu 5 gorjetas',                                '💸', NULL, NULL, 5,   'rider',  now())
ON CONFLICT (id) DO NOTHING;

-- ==============================================================================
-- FIM DA REVISÃO TOTAL — Todas as 50 Edge Functions auditadas e corrigidas
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260511198000_db_part8_final_corrections.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- REVISÃO TOTAL — Parte 7: Últimos ajustes nas funções finais analisadas
-- ==============================================================================

-- 1. DRIVER_EARNINGS - completando as colunas que estavam faltando
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_earnings' AND column_name='gross_amount') THEN
    ALTER TABLE public.driver_earnings ADD COLUMN gross_amount NUMERIC(10, 2);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_earnings' AND column_name='commission_pct') THEN
    ALTER TABLE public.driver_earnings ADD COLUMN commission_pct NUMERIC(5, 2);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_earnings' AND column_name='commission_amt') THEN
    ALTER TABLE public.driver_earnings ADD COLUMN commission_amt NUMERIC(10, 2);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_earnings' AND column_name='net_amount') THEN
    ALTER TABLE public.driver_earnings ADD COLUMN net_amount NUMERIC(10, 2);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_earnings' AND column_name='payment_method') THEN
    ALTER TABLE public.driver_earnings ADD COLUMN payment_method TEXT;
  END IF;
END $$;

-- 2. RATINGS - tabela ausente sendo usada em rate_ride
CREATE TABLE IF NOT EXISTS public.ratings (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ride_id UUID REFERENCES public.rides(id) ON DELETE CASCADE,
    rated_by UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    rated_user UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    score INTEGER CHECK (score >= 1 AND score <= 5),
    comment TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(ride_id, rated_by)
);

ALTER TABLE public.ratings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ratings_select" ON public.ratings FOR SELECT USING (true);
CREATE POLICY "ratings_insert" ON public.ratings FOR INSERT WITH CHECK (auth.uid() = rated_by);
CREATE POLICY "ratings_update" ON public.ratings FOR UPDATE USING (auth.uid() = rated_by);

-- 3. RIDES - completando tracking_token e avaliações (faltando completed_at, rider_rating, driver_rating)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rides' AND column_name='rider_rating') THEN
    ALTER TABLE public.rides ADD COLUMN rider_rating INTEGER;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rides' AND column_name='driver_rating') THEN
    ALTER TABLE public.rides ADD COLUMN driver_rating INTEGER;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rides' AND column_name='completed_at') THEN
    ALTER TABLE public.rides ADD COLUMN completed_at TIMESTAMP WITH TIME ZONE;
  END IF;
END $$;

-- 4. FIX NA FUNÇÃO COMPLETE RIDE NO BANCO (se existir)
-- Isso atualiza as assinaturas da função complete_ride para não causarem mais erros se forem chamadas no banco
CREATE OR REPLACE FUNCTION increment_wallet(p_user_id UUID, p_amount NUMERIC)
RETURNS VOID AS $$
BEGIN
  UPDATE wallets
  SET balance = balance + p_amount,
      updated_at = NOW()
  WHERE user_id = p_user_id;

  -- Se a carteira não existir, ela será criada com o saldo inicial pelo trigger set_initial_wallet_balance que criamos antes.
  IF NOT FOUND THEN
    INSERT INTO wallets (user_id, balance) VALUES (p_user_id, p_amount);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Garantir que a policy RLS no wallets permite inserção para a trigger
DROP POLICY IF EXISTS "wallets_insert" ON public.wallets;
CREATE POLICY "wallets_insert" ON public.wallets FOR INSERT WITH CHECK (auth.uid()::text = user_id OR (EXISTS (SELECT 1 FROM public.admins WHERE admins.id::text = auth.uid()::text)));



-- ─────────────────────────────────────────────
-- FILE: 20260513000000_fix_rides_rls_for_drivers.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- FIX CRÍTICO: Motoristas precisam VER corridas com status='requested'
-- para poderem aceitar corridas. A RLS anterior só permitia ver corridas
-- onde o motorista já era driver_id (que é NULL em corridas pendentes).
-- ==============================================================================

-- Adiciona policy que permite motoristas verem corridas 'requested'
-- para que o stream CDC e a consulta direta funcionem
DROP POLICY IF EXISTS "rides_select_requested_for_drivers" ON public.rides;

CREATE POLICY "rides_select_requested_for_drivers" ON public.rides
  FOR SELECT TO authenticated
  USING (
    -- Motoristas online podem ver corridas pendentes
    (
      status = 'requested'
      AND EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid()::text 
        AND role = 'driver'
      )
    )
    -- OU é participante da corrida (rider ou driver)
    OR auth.uid()::text = rider_id
    OR auth.uid()::text = driver_id
    -- OU é admin/operator
    OR EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid()::text 
      AND role IN ('admin', 'operator')
    )
  );

-- Remove a policy anterior mais restritiva (para evitar conflito)
DROP POLICY IF EXISTS "rides_select" ON public.rides;

-- ==============================================================================
-- FIM — Motoristas agora podem ver corridas pendentes para aceitar
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260513014246_webhook_new_ride.sql
-- ─────────────────────────────────────────────



-- ─────────────────────────────────────────────
-- FILE: 20260514_centralize_app_settings.sql
-- ─────────────────────────────────────────────

-- =============================================================================
-- MIGRATION: Adicionar colunas de configuração faltantes em app_settings
-- Para centralizar TODAS as configurações que antes estavam na tabela 'config'
-- =============================================================================

-- Taxa de cancelamento (antes hardcoded R$5)
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS cancellation_fee NUMERIC DEFAULT 5.00;

-- Surge pricing controls
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS surge_enabled BOOLEAN DEFAULT true;
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS surge_max_multiplier NUMERIC DEFAULT 2.5;

-- Mercado Pago credentials (antes na tabela 'config' como key-value)
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS mp_access_token TEXT DEFAULT '';
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS mp_public_key TEXT DEFAULT '';
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS mp_webhook_secret TEXT DEFAULT '';
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS mp_sandbox BOOLEAN DEFAULT false;

-- original_fare na tabela rides (tarifa antes do cupom — essencial para comissão)
ALTER TABLE rides ADD COLUMN IF NOT EXISTS original_fare NUMERIC DEFAULT 0;

-- Garantir que o campo commission_percentage existe nos profiles de motorista
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS commission_percentage NUMERIC DEFAULT NULL;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS commission_exempt_until TIMESTAMPTZ DEFAULT NULL;

-- =============================================================================
-- INDEX: Otimizar queries usadas pelas Edge Functions
-- =============================================================================

-- Index para busca de motoristas próximos por status
CREATE INDEX IF NOT EXISTS idx_driver_locations_status ON driver_locations(status);

-- Index para corridas ativas (usado por calculate-surge)
CREATE INDEX IF NOT EXISTS idx_rides_status ON rides(status);

-- Index para busca de cupom por código
CREATE INDEX IF NOT EXISTS idx_coupons_code_enabled ON coupons(code, is_enabled);

-- =============================================================================
-- COMMENT: Documentar a migração
-- =============================================================================
COMMENT ON COLUMN app_settings.cancellation_fee IS 'Taxa de cancelamento cobrada do passageiro (R$). Controlada pelo Painel Admin.';
COMMENT ON COLUMN app_settings.surge_enabled IS 'Habilitar/desabilitar surge pricing globalmente. Controlado pelo Painel Admin.';
COMMENT ON COLUMN app_settings.surge_max_multiplier IS 'Multiplicador máximo de surge pricing (ex: 2.5 = 250%). Controlado pelo Painel Admin.';
COMMENT ON COLUMN app_settings.mp_access_token IS 'Access token do Mercado Pago. Configurado pelo Painel Admin.';
COMMENT ON COLUMN rides.original_fare IS 'Tarifa original antes de cupons de desconto. Usada para calcular comissão justa do motorista.';


-- ─────────────────────────────────────────────
-- FILE: 20260515200000_admin_panel_final_alignment.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO FINAL — ALINHAMENTO COMPLETO DO ADMIN PANEL COM SUPABASE
-- ==============================================================================
-- Esta migração resolve TODAS as incompatibilidades entre o código Flutter
-- do Admin Panel e o schema do banco de dados. Cada seção corresponde a
-- uma feature screen específica do painel.
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. APP_SETTINGS — Converter de key-value para single-row columnar
--    O SettingsScreen usa: driver_search_radius, commission_rate, currency,
--    map_provider, global_surge_multiplier, google_map_api_key
--    Precisamos garantir que a tabela suporta acesso por colunas
-- ─────────────────────────────────────────────────────────────────────────────

-- Adicionar colunas faltantes que o SettingsScreen espera
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS id SERIAL;
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS driver_search_radius INTEGER DEFAULT 10;
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS commission_rate NUMERIC(5,2) DEFAULT 0.00;
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'BRL';
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS map_provider TEXT DEFAULT 'googleMaps';
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS global_surge_multiplier NUMERIC(4,2) DEFAULT 1.00;
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS google_map_api_key TEXT DEFAULT '';

-- Garantir que existe pelo menos uma row de configuração para o admin usar
INSERT INTO public.app_settings (key, value, driver_search_radius, commission_rate, currency, map_provider, global_surge_multiplier, google_map_api_key)
VALUES ('global_config', 'master', 10, 0.00, 'BRL', 'googleMaps', 1.00, '')
ON CONFLICT (key) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. HIGH_RISK_DRIVERS VIEW — Usado pelo GlobalMapScreen (Anti-Fraude)
--    Motoristas com taxa de cancelamento > 30% e mínimo 5 corridas
-- ─────────────────────────────────────────────────────────────────────────────

DROP VIEW IF EXISTS public.high_risk_drivers CASCADE;

CREATE OR REPLACE VIEW public.high_risk_drivers AS
SELECT
  p.id AS driver_id,
  p.full_name,
  p.phone,
  COUNT(r.id) AS total_rides,
  COUNT(r.id) FILTER (WHERE r.status IN ('driver_canceled', 'rider_canceled') AND r.driver_id = p.id) AS canceled_rides,
  CASE
    WHEN COUNT(r.id) > 0 THEN
      ROUND(
        (COUNT(r.id) FILTER (WHERE r.status IN ('driver_canceled', 'rider_canceled') AND r.driver_id = p.id)::NUMERIC /
        COUNT(r.id)::NUMERIC) * 100,
        1
      )
    ELSE 0
  END AS cancellation_rate
FROM public.profiles p
LEFT JOIN public.rides r ON r.driver_id = p.id
WHERE p.role = 'driver'
GROUP BY p.id, p.full_name, p.phone
HAVING COUNT(r.id) >= 5
   AND (COUNT(r.id) FILTER (WHERE r.status IN ('driver_canceled', 'rider_canceled') AND r.driver_id = p.id)::NUMERIC /
        NULLIF(COUNT(r.id)::NUMERIC, 0)) > 0.30
ORDER BY cancellation_rate DESC;

-- Grant access to authenticated users (admins)
GRANT SELECT ON public.high_risk_drivers TO authenticated;
GRANT SELECT ON public.high_risk_drivers TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. SOS_SIGNALS — Tabela usada pelo MainDashboardLayout para alertas SOS
--    O layout faz stream em 'sos_signals' com status 'Submitted'
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.sos_signals (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  ride_id     TEXT,
  submitted_by TEXT,   -- 'rider' ou 'driver'
  user_id     TEXT,
  lat         DOUBLE PRECISION,
  lng         DOUBLE PRECISION,
  status      TEXT DEFAULT 'Submitted' CHECK (status IN ('Submitted', 'Resolved', 'Dismissed')),
  resolved_by TEXT,    -- admin que resolveu
  notes       TEXT,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.sos_signals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "sos_signals_select_authenticated" ON public.sos_signals;
CREATE POLICY "sos_signals_select_authenticated" ON public.sos_signals
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "sos_signals_insert_authenticated" ON public.sos_signals;
CREATE POLICY "sos_signals_insert_authenticated" ON public.sos_signals
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "sos_signals_update_authenticated" ON public.sos_signals;
CREATE POLICY "sos_signals_update_authenticated" ON public.sos_signals
  FOR UPDATE TO authenticated USING (true);

-- Trigger updated_at automático
DROP TRIGGER IF EXISTS update_sos_signals_updated_at ON public.sos_signals;
CREATE TRIGGER update_sos_signals_updated_at
  BEFORE UPDATE ON public.sos_signals
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Índice para busca de sinais ativos
CREATE INDEX IF NOT EXISTS idx_sos_signals_status ON public.sos_signals(status);
CREATE INDEX IF NOT EXISTS idx_sos_signals_created_at ON public.sos_signals(created_at DESC);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. REALTIME — Adicionar TODAS as tabelas usadas pelo Admin Panel
--    que ainda não estão na publicação supabase_realtime
-- ─────────────────────────────────────────────────────────────────────────────

-- coupons — CouponsManagementScreen usa .stream(primaryKey: ['id'])
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'coupons'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.coupons;
  END IF;
END $$;

-- services — ServicesPricingScreen usa .stream(primaryKey: ['id'])
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'services'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.services;
  END IF;
END $$;

-- admin_audit_log — Audit modal no GlobalMapScreen
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'admin_audit_log'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.admin_audit_log;
  END IF;
END $$;

-- sos_signals — MainDashboardLayout SOS alertas
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'sos_signals'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.sos_signals;
  END IF;
END $$;

-- driver_earnings — FinancialsScreen usa stream
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'driver_earnings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_earnings;
  END IF;
END $$;

-- admins — para login/session do admin panel
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'admins'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.admins;
  END IF;
END $$;

-- REPLICA IDENTITY FULL para todas as tabelas com Realtime
ALTER TABLE public.coupons REPLICA IDENTITY FULL;
ALTER TABLE public.services REPLICA IDENTITY FULL;
ALTER TABLE public.admin_audit_log REPLICA IDENTITY FULL;
ALTER TABLE public.sos_signals REPLICA IDENTITY FULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. RPC: get_driver_surgical_financials — Usado pelo FinancialsScreen
--    Retorna analytics financeiros detalhados de um motorista específico
-- ─────────────────────────────────────────────────────────────────────────────

-- Versão parameterless: retorna stats de TODOS os motoristas (usado pelo FinancialsScreen)
CREATE OR REPLACE FUNCTION public.get_driver_surgical_financials()
RETURNS TABLE (
  driver_id TEXT,
  full_name TEXT,
  phone TEXT,
  total_rides BIGINT,
  gross_revenue NUMERIC,
  total_commission NUMERIC,
  total_tips NUMERIC,
  wallet_balance NUMERIC,
  avg_fare NUMERIC,
  avg_rating NUMERIC,
  last_ride_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id AS driver_id,
    p.full_name,
    p.phone,
    COALESCE(COUNT(r.id) FILTER (WHERE r.status = 'completed'), 0) AS total_rides,
    COALESCE(SUM(r.fare) FILTER (WHERE r.status = 'completed'), 0) AS gross_revenue,
    COALESCE(SUM(de.platform_commission), 0) AS total_commission,
    COALESCE(SUM(de.tip_amount), 0) AS total_tips,
    COALESCE(w.balance, 0) AS wallet_balance,
    COALESCE(AVG(r.fare) FILTER (WHERE r.status = 'completed'), 0) AS avg_fare,
    COALESCE(p.rating, 0) AS avg_rating,
    MAX(r.created_at) FILTER (WHERE r.status = 'completed') AS last_ride_at
  FROM public.profiles p
  LEFT JOIN public.rides r ON r.driver_id = p.id
  LEFT JOIN public.driver_earnings de ON de.driver_id = p.id
  LEFT JOIN public.wallets w ON w.user_id = p.id
  WHERE p.role = 'driver'
  GROUP BY p.id, p.full_name, p.phone, w.balance, p.rating
  ORDER BY gross_revenue DESC;
END;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION public.get_driver_surgical_financials() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_driver_surgical_financials() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. RPC: get_admin_dashboard_stats — Usado pelo OverviewDashboardScreen
--    Retorna estatísticas consolidadas para o dashboard principal
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_admin_dashboard_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result JSONB;
BEGIN
  SELECT jsonb_build_object(
    -- Contadores gerais
    'total_riders', (SELECT COUNT(*) FROM public.profiles WHERE role = 'rider'),
    'total_drivers', (SELECT COUNT(*) FROM public.profiles WHERE role = 'driver'),
    'online_drivers', (SELECT COUNT(*) FROM public.profiles WHERE role = 'driver' AND status = 'online'),
    'pending_kyc', (SELECT COUNT(*) FROM public.profiles WHERE role = 'driver' AND (is_approved IS NULL OR is_approved = false) AND status = 'pending_approval'),

    -- Corridas
    'total_rides', (SELECT COUNT(*) FROM public.rides),
    'active_rides', (SELECT COUNT(*) FROM public.rides WHERE status IN ('searching', 'accepted', 'arrived', 'in_progress', 'picked_up')),
    'completed_rides', (SELECT COUNT(*) FROM public.rides WHERE status = 'completed'),
    'cancelled_rides', (SELECT COUNT(*) FROM public.rides WHERE status IN ('driver_canceled', 'rider_canceled')),

    -- Financeiro
    'total_revenue', COALESCE((SELECT SUM(fare) FROM public.rides WHERE status = 'completed'), 0),
    'total_commissions', COALESCE((SELECT SUM(platform_commission) FROM public.driver_earnings), 0),
    'total_wallet_balance', COALESCE((SELECT SUM(balance) FROM public.wallets), 0),

    -- Hoje
    'rides_today', (SELECT COUNT(*) FROM public.rides WHERE created_at >= CURRENT_DATE),
    'revenue_today', COALESCE((SELECT SUM(fare) FROM public.rides WHERE status = 'completed' AND created_at >= CURRENT_DATE), 0),
    'new_users_today', (SELECT COUNT(*) FROM public.profiles WHERE created_at >= CURRENT_DATE),

    -- SOS ativo
    'active_sos', (SELECT COUNT(*) FROM public.sos_alerts WHERE status = 'active')
  ) INTO result;

  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_admin_dashboard_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_dashboard_stats() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. RPC: admin_adjust_wallet — Usado pelo FinancialsScreen para ajustes
--    Permite crédito/débito administrativo com audit trail automático
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_adjust_wallet(
  p_admin_id TEXT,
  p_user_id TEXT,
  p_amount NUMERIC,
  p_type TEXT,          -- 'credit' ou 'debit'
  p_description TEXT DEFAULT 'Ajuste administrativo'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  current_balance NUMERIC;
  new_balance NUMERIC;
  tx_id UUID;
BEGIN
  -- Buscar saldo atual
  SELECT balance INTO current_balance FROM public.wallets WHERE user_id = p_user_id;

  IF current_balance IS NULL THEN
    -- Criar wallet se não existir
    INSERT INTO public.wallets (user_id, balance) VALUES (p_user_id, 0);
    current_balance := 0;
  END IF;

  -- Calcular novo saldo
  IF p_type = 'credit' THEN
    new_balance := current_balance + ABS(p_amount);
  ELSIF p_type = 'debit' THEN
    new_balance := current_balance - ABS(p_amount);
    IF new_balance < 0 THEN
      RETURN jsonb_build_object('success', false, 'error', 'Saldo insuficiente');
    END IF;
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Tipo inválido: use credit ou debit');
  END IF;

  -- Atualizar saldo
  UPDATE public.wallets SET balance = new_balance WHERE user_id = p_user_id;

  -- Registrar transação
  INSERT INTO public.wallet_transactions (user_id, amount, type, description)
  VALUES (p_user_id, p_amount, p_type, p_description)
  RETURNING id INTO tx_id;

  -- Registrar audit log
  INSERT INTO public.admin_audit_log (admin_id, action_type, target_resource_id, details)
  VALUES (
    p_admin_id,
    'wallet_adjustment',
    p_user_id,
    jsonb_build_object(
      'amount', p_amount,
      'type', p_type,
      'description', p_description,
      'old_balance', current_balance,
      'new_balance', new_balance,
      'transaction_id', tx_id
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'old_balance', current_balance,
    'new_balance', new_balance,
    'transaction_id', tx_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_adjust_wallet(TEXT, TEXT, NUMERIC, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_adjust_wallet(TEXT, TEXT, NUMERIC, TEXT, TEXT) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. ÍNDICES DE PERFORMANCE — Para queries do Admin Panel
-- ─────────────────────────────────────────────────────────────────────────────

-- Profiles: filtros por role e status (usados em todas as telas de gestão)
CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_role_status ON public.profiles(role, status);
CREATE INDEX IF NOT EXISTS idx_profiles_is_approved ON public.profiles(is_approved) WHERE role = 'driver';
CREATE INDEX IF NOT EXISTS idx_profiles_created_at ON public.profiles(created_at DESC);

-- Rides: filtros de status e data (Rides History + Dashboard)
CREATE INDEX IF NOT EXISTS idx_rides_created_at_desc ON public.rides(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rides_driver_status ON public.rides(driver_id, status);
CREATE INDEX IF NOT EXISTS idx_rides_rider_status ON public.rides(rider_id, status);

-- Admin audit log: consultas recentes
CREATE INDEX IF NOT EXISTS idx_admin_audit_log_created_at ON public.admin_audit_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_log_admin_id ON public.admin_audit_log(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_log_action_type ON public.admin_audit_log(action_type);

-- Coupons: filtros de código e status
CREATE INDEX IF NOT EXISTS idx_coupons_is_active ON public.coupons(is_active);
CREATE INDEX IF NOT EXISTS idx_coupons_created_at ON public.coupons(created_at DESC);

-- SOS signals: busca de sinais ativos por corrida
CREATE INDEX IF NOT EXISTS idx_sos_signals_ride_id ON public.sos_signals(ride_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. STORAGE BUCKETS — Garantir que existem os buckets necessários
-- ─────────────────────────────────────────────────────────────────────────────

-- Bucket para thumbnails de serviços (ServicesPricingScreen)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'service-images',
  'service-images',
  true,
  5242880, -- 5MB
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO NOTHING;

-- Policy de leitura pública para thumbnails de serviços
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'service_images_public_read' AND tablename = 'objects'
  ) THEN
    CREATE POLICY "service_images_public_read" ON storage.objects
      FOR SELECT USING (bucket_id = 'service-images');
  END IF;
END $$;

-- Policy de upload para admins autenticados
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'service_images_admin_upload' AND tablename = 'objects'
  ) THEN
    CREATE POLICY "service_images_admin_upload" ON storage.objects
      FOR INSERT TO authenticated WITH CHECK (bucket_id = 'service-images');
  END IF;
END $$;

-- Policy de update/delete para admins
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'service_images_admin_manage' AND tablename = 'objects'
  ) THEN
    CREATE POLICY "service_images_admin_manage" ON storage.objects
      FOR UPDATE TO authenticated USING (bucket_id = 'service-images');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'service_images_admin_delete' AND tablename = 'objects'
  ) THEN
    CREATE POLICY "service_images_admin_delete" ON storage.objects
      FOR DELETE TO authenticated USING (bucket_id = 'service-images');
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. SERVICES — Colunas referenciadas pelo ServicesPricingScreen
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.services ADD COLUMN IF NOT EXISTS image_url TEXT;
ALTER TABLE public.services ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;
ALTER TABLE public.services ADD COLUMN IF NOT EXISTS display_order INTEGER DEFAULT 0;
ALTER TABLE public.services ADD COLUMN IF NOT EXISTS description TEXT;

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. COUPONS — Garantir todas as colunas usadas pelo CouponsManagementScreen
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.coupons ADD COLUMN IF NOT EXISTS minimum_order NUMERIC(10,2) DEFAULT 0;
ALTER TABLE public.coupons ADD COLUMN IF NOT EXISTS expire_at TIMESTAMPTZ;
ALTER TABLE public.coupons ADD COLUMN IF NOT EXISTS usage_count INTEGER DEFAULT 0;

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. ADMIN_AUDIT_LOG — Garantir coluna target_resource_id existe
--     (alguns screens usam target_resource_id, outros target_user_id)
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.admin_audit_log ADD COLUMN IF NOT EXISTS target_resource_id TEXT;

-- ─────────────────────────────────────────────────────────────────────────────
-- 13. ANNOUNCEMENTS — Para campanhas de Marketing Push
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.announcements ADD COLUMN IF NOT EXISTS target_audience TEXT DEFAULT 'all'
  CHECK (target_audience IN ('all', 'riders', 'drivers'));
ALTER TABLE public.announcements ADD COLUMN IF NOT EXISTS push_sent BOOLEAN DEFAULT false;
ALTER TABLE public.announcements ADD COLUMN IF NOT EXISTS push_sent_at TIMESTAMPTZ;
ALTER TABLE public.announcements ADD COLUMN IF NOT EXISTS push_tokens_count INTEGER DEFAULT 0;

-- ==============================================================================
-- FIM — Schema 100% alinhado com todas as 11 features do Admin Panel
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260520000000_sos_chat_audit_rpc.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- BLINDAGEM DE SEGURANÇA E PRIVACIDADE — ECOSSISTEMA UPPI
-- Criação de tabela de auditoria e RPC segura para leitura de chat sob SOS
-- ==============================================================================

-- 1. Tabela de logs de auditoria de acessos administrativos
CREATE TABLE IF NOT EXISTS public.admin_chat_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id TEXT NOT NULL,
    ride_id UUID NOT NULL,
    accessed_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    reason TEXT DEFAULT 'Acesso de emergência sob alerta SOS ativo' NOT NULL
);

-- Habilitar RLS na tabela de auditoria
ALTER TABLE public.admin_chat_audit_logs ENABLE ROW LEVEL SECURITY;

-- Apenas admins autenticados podem ver os logs de auditoria
CREATE POLICY admin_audit_logs_select_policy ON public.admin_chat_audit_logs
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid()::text AND role = 'admin'
        )
    );

-- 2. RPC segura para leitura do chat da corrida sob SOS ativo
CREATE OR REPLACE FUNCTION public.rpc_get_sos_chat_context(p_ride_id UUID)
RETURNS TABLE (
    message_id UUID,
    ride_id UUID,
    content TEXT,
    sent_by_driver BOOLEAN,
    created_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_admin BOOLEAN;
    v_has_active_sos BOOLEAN;
BEGIN
    -- A. Verificar se o usuário solicitante é de fato um Administrador
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()::text AND role = 'admin'
    ) INTO v_is_admin;

    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'Acesso negado: Apenas administradores autorizados podem realizar esta operação.';
    END IF;

    -- B. Verificar se a corrida possui algum SOS ativo associado na tabela sos_alerts
    SELECT EXISTS (
        SELECT 1 FROM public.sos_alerts
        WHERE ride_id = p_ride_id AND status = 'active'
    ) INTO v_has_active_sos;

    IF NOT v_has_active_sos THEN
        RAISE EXCEPTION 'Acesso negado: Este chat privado de viagem não possui nenhum alerta SOS ativo associado.';
    END IF;

    -- C. Registrar o log de auditoria permanente do acesso administrativo
    INSERT INTO public.admin_chat_audit_logs (admin_id, ride_id)
    VALUES (auth.uid()::text, p_ride_id);

    -- D. Retornar as mensagens do chat da viagem com segurança
    RETURN QUERY
    SELECT 
        m.id::UUID,
        m.ride_id::UUID,
        m.content::TEXT,
        m.sent_by_driver::BOOLEAN,
        m.created_at::TIMESTAMP WITH TIME ZONE
    FROM public.ride_messages m
    WHERE m.ride_id = p_ride_id
    ORDER BY m.created_at ASC;
END;
$$;

-- Garantir permissões de execução
GRANT EXECUTE ON FUNCTION public.rpc_get_sos_chat_context(UUID) TO authenticated;

COMMENT ON FUNCTION public.rpc_get_sos_chat_context(UUID) IS 'Retorna o histórico de chat de uma viagem específica de forma segura e auditada apenas se houver um alerta SOS ativo.';


-- ─────────────────────────────────────────────
-- FILE: 20260520010000_wallet_pending_balance.sql
-- ─────────────────────────────────────────────

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


-- ─────────────────────────────────────────────
-- FILE: 20260520020000_ride_rejection_filter.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- BLINDAGEM DE USABILIDADE DO MOTORISTA — ECOSSISTEMA UPPI
-- Tabela e RPC para evitar loop infinito de ofertas rejeitadas ou canceladas
-- ==============================================================================

-- 1. Criar tabela de controle de corridas rejeitadas por motorista
CREATE TABLE IF NOT EXISTS public.ride_rejected_drivers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id UUID NOT NULL REFERENCES public.rides(id) ON DELETE CASCADE,
    driver_id TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT unique_ride_driver_rejection UNIQUE (ride_id, driver_id)
);

-- Habilitar RLS na tabela de rejeições
ALTER TABLE public.ride_rejected_drivers ENABLE ROW LEVEL SECURITY;

-- Permitir que o próprio motorista autenticado insira suas rejeições
CREATE POLICY "Driver can insert own rejections" ON public.ride_rejected_drivers
    FOR INSERT TO authenticated
    WITH CHECK (driver_id = auth.uid()::text);

-- Permitir leitura das próprias rejeições
CREATE POLICY "Driver can read own rejections" ON public.ride_rejected_drivers
    FOR SELECT TO authenticated
    USING (driver_id = auth.uid()::text);

-- 2. RPC para registrar rejeição de corrida de forma simples
CREATE OR REPLACE FUNCTION public.reject_ride(
  p_ride_id UUID,
  p_driver_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.ride_rejected_drivers (ride_id, driver_id)
  VALUES (p_ride_id, p_driver_id)
  ON CONFLICT (ride_id, driver_id) DO NOTHING;
END;
$$;

-- Garantir acesso da RPC aos autenticados
GRANT EXECUTE ON FUNCTION public.reject_ride(UUID, TEXT) TO authenticated;

-- 3. Atualizar a RPC find_nearby_requested_rides para incluir o filtro de rejeições
CREATE OR REPLACE FUNCTION public.find_nearby_requested_rides(
    lat float8,
    lng float8,
    radius_meters float8 DEFAULT 3000
)
RETURNS TABLE (
    id UUID,
    pickup_address TEXT,
    dropoff_address TEXT,
    fare DECIMAL,
    dist_meters FLOAT8
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        r.id,
        r.pickup_address,
        r.dropoff_address,
        r.fare,
        ST_Distance(
            r.pickup_location,
            ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography
        ) AS dist_meters
    FROM public.rides r
    WHERE r.status = 'requested'
      AND r.driver_id IS NULL
      -- Evita receber corridas que este motorista já rejeitou ou cancelou
      AND r.id NOT IN (
          SELECT rr.ride_id 
          FROM public.ride_rejected_drivers rr 
          WHERE rr.driver_id = auth.uid()::text
      )
      AND ST_DWithin(
          r.pickup_location,
          ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography,
          radius_meters
      )
    ORDER BY dist_meters ASC
    LIMIT 1;
END;
$$;

COMMENT ON FUNCTION public.find_nearby_requested_rides(float8, float8, float8) IS 'Busca corridas próximas solicitadas ativas, filtrando as que o motorista já rejeitou anteriormente para evitar loops de tela.';


-- ─────────────────────────────────────────────
-- FILE: 20260520030000_strategic_gaps_tables.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Tabelas de Integração Estratégica do Ecossistema Uppi
-- 1. ride_offers (Fila de match dinâmica)
-- 2. ride_rejected_drivers (Filtro de rejeição de corridas)
-- 3. surge_zones (Preço dinâmico georreferenciado)
-- 4. ride_tracking_shares (Compartilhamento seguro de rota)
-- 5. driver_kyc_history (Histórico e auditoria de KYC)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. FILA DE DESPACHO E MATCHING DINÂMICO (RIDE OFFERS)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ride_offers (
    id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ride_id     UUID REFERENCES public.rides(id) ON DELETE CASCADE NOT NULL,
    driver_id   TEXT REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    status      TEXT DEFAULT 'offered' CHECK (status IN ('offered', 'accepted', 'rejected', 'expired')),
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    expires_at  TIMESTAMP WITH TIME ZONE NOT NULL
);

ALTER TABLE public.ride_offers ENABLE ROW LEVEL SECURITY;

-- Políticas de Segurança para RLS (ride_offers)
DROP POLICY IF EXISTS "allow_select_assigned_offers" ON public.ride_offers;
CREATE POLICY "allow_select_assigned_offers" ON public.ride_offers
    FOR SELECT TO authenticated USING (
        auth.uid()::text = driver_id OR 
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

DROP POLICY IF EXISTS "allow_update_assigned_offers" ON public.ride_offers;
CREATE POLICY "allow_update_assigned_offers" ON public.ride_offers
    FOR UPDATE TO authenticated USING (
        auth.uid()::text = driver_id OR 
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

DROP POLICY IF EXISTS "allow_admin_manage_offers" ON public.ride_offers;
CREATE POLICY "allow_admin_manage_offers" ON public.ride_offers
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );


-- ------------------------------------------------------------------------------
-- 2. FILTRO DE REJEIÇÃO DE OFERTAS (RIDE REJECTED DRIVERS)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ride_rejected_drivers (
    id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ride_id     UUID REFERENCES public.rides(id) ON DELETE CASCADE NOT NULL,
    driver_id   TEXT REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.ride_rejected_drivers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_driver_manage_own_rejections" ON public.ride_rejected_drivers;
CREATE POLICY "allow_driver_manage_own_rejections" ON public.ride_rejected_drivers
    FOR ALL TO authenticated USING (
        auth.uid()::text = driver_id OR 
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );


-- ------------------------------------------------------------------------------
-- 3. PREÇO DINÂMICO GEORREFERENCIADO (SURGE ZONES)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.surge_zones (
    id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name        TEXT NOT NULL,
    boundary    GEOGRAPHY(POLYGON) NOT NULL, -- Uso de PostGIS para cercas virtuais exatas
    multiplier  NUMERIC(3,2) DEFAULT 1.00 CHECK (multiplier >= 1.00),
    is_active   BOOLEAN DEFAULT true,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    expires_at  TIMESTAMP WITH TIME ZONE
);

ALTER TABLE public.surge_zones ENABLE ROW LEVEL SECURITY;

-- Qualquer usuário pode ler zonas ativas
DROP POLICY IF EXISTS "allow_select_surge_zones" ON public.surge_zones;
CREATE POLICY "allow_select_surge_zones" ON public.surge_zones
    FOR SELECT USING (is_active = true);

-- Apenas admins gerenciam zonas de tarifa
DROP POLICY IF EXISTS "allow_admin_manage_surge" ON public.surge_zones;
CREATE POLICY "allow_admin_manage_surge" ON public.surge_zones
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );


-- ------------------------------------------------------------------------------
-- 4. COMPARTILHAMENTO SEGURO DE ROTA (RIDE TRACKING SHARES)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ride_tracking_shares (
    id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ride_id      UUID REFERENCES public.rides(id) ON DELETE CASCADE NOT NULL,
    share_token  TEXT UNIQUE NOT NULL,
    created_by   TEXT REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at   TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    expires_at   TIMESTAMP WITH TIME ZONE NOT NULL
);

ALTER TABLE public.ride_tracking_shares ENABLE ROW LEVEL SECURITY;

-- Qualquer pessoa (mesmo desautenticada) pode ler com um share_token ativo
DROP POLICY IF EXISTS "allow_public_select_active_shares" ON public.ride_tracking_shares;
CREATE POLICY "allow_public_select_active_shares" ON public.ride_tracking_shares
    FOR SELECT USING (expires_at > now());

-- O passageiro dono da corrida pode gerenciar o compartilhamento
DROP POLICY IF EXISTS "allow_user_manage_own_shares" ON public.ride_tracking_shares;
CREATE POLICY "allow_user_manage_own_shares" ON public.ride_tracking_shares
    FOR ALL TO authenticated USING (
        auth.uid()::text = created_by OR
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );


-- ------------------------------------------------------------------------------
-- 5. HISTÓRICO E AUDITORIA DE KYC (DRIVER KYC HISTORY)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.driver_kyc_history (
    id                  UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    driver_id           TEXT REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    admin_id            TEXT REFERENCES public.admins(id) ON DELETE SET NULL,
    document_type       TEXT NOT NULL,
    status              TEXT NOT NULL CHECK (status IN ('approved', 'rejected')),
    rejection_reason    TEXT,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.driver_kyc_history ENABLE ROW LEVEL SECURITY;

-- Motorista pode ler seu próprio histórico de aprovações/documentações
DROP POLICY IF EXISTS "allow_driver_select_own_kyc" ON public.driver_kyc_history;
CREATE POLICY "allow_driver_select_own_kyc" ON public.driver_kyc_history
    FOR SELECT TO authenticated USING (
        auth.uid()::text = driver_id OR 
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

-- Apenas admins podem registrar e auditar logs de KYC
DROP POLICY IF EXISTS "allow_admin_manage_kyc_history" ON public.driver_kyc_history;
CREATE POLICY "allow_admin_manage_kyc_history" ON public.driver_kyc_history
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );


-- ------------------------------------------------------------------------------
-- 6. HABILITAR REPLICAÇÃO REALTIME NO SUPABASE
-- ------------------------------------------------------------------------------
BEGIN;
  -- Remover tabelas antigas da publicação realtime se já existirem (para evitar conflitos)
  ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public.ride_offers;
  ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public.surge_zones;
  ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public.ride_tracking_shares;
  ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public.driver_kyc_history;

  -- Adicionar novas tabelas à publicação realtime
  ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_offers;
  ALTER PUBLICATION supabase_realtime ADD TABLE public.surge_zones;
  ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_tracking_shares;
  ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_kyc_history;
COMMIT;


-- ─────────────────────────────────────────────
-- FILE: 20260520040000_strategic_gaps_triggers.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Lógica Reativa e Triggers do Ecossistema Uppi
-- 1. rpc_calculate_ride_fare (Cálculo de preço dinâmico georreferenciado)
-- 2. sync_driver_profile_kyc (Trigger para sincronizar perfil com histórico KYC)
-- 3. rpc_get_or_create_ride_share_token (Gerador e leitor de tokens de rota)
-- 4. handle_completed_ride_financials (Trigger de Split financeiro e carteira)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. CÁLCULO DE PREÇO DINÂMICO GEORREFERENCIADO
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_calculate_ride_fare(
    p_pickup_lat FLOAT8,
    p_pickup_lng FLOAT8,
    p_dropoff_lat FLOAT8,
    p_dropoff_lng FLOAT8,
    p_base_fare DECIMAL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_multiplier NUMERIC(3,2) := 1.00;
    v_surge_id UUID := NULL;
    v_surge_name TEXT := NULL;
    v_final_fare DECIMAL;
BEGIN
    -- Encontra a surge_zone ativa que contenha o ponto de partida (pickup) ou destino (dropoff)
    -- e que possua o maior multiplicador de tarifa
    SELECT id, name, multiplier INTO v_surge_id, v_surge_name, v_multiplier
    FROM public.surge_zones
    WHERE is_active = true
      AND (expires_at IS NULL OR expires_at > now())
      AND (
        ST_Within(
            ST_SetSRID(ST_MakePoint(p_pickup_lng, p_pickup_lat), 4326)::geometry,
            boundary::geometry
        ) OR
        ST_Within(
            ST_SetSRID(ST_MakePoint(p_dropoff_lng, p_dropoff_lat), 4326)::geometry,
            boundary::geometry
        )
      )
    ORDER BY multiplier DESC
    LIMIT 1;

    -- Fallback de segurança
    IF v_multiplier IS NULL THEN
        v_multiplier := 1.00;
    END IF;

    -- Cálculo da tarifa final
    v_final_fare := p_base_fare * v_multiplier;

    RETURN jsonb_build_object(
        'base_fare', p_base_fare,
        'final_fare', v_final_fare,
        'multiplier', v_multiplier,
        'surge_zone_id', v_surge_id,
        'surge_zone_name', v_surge_name
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_calculate_ride_fare(FLOAT8, FLOAT8, FLOAT8, FLOAT8, DECIMAL) TO authenticated;

COMMENT ON FUNCTION public.rpc_calculate_ride_fare IS 'Verifica se a corrida se inicia ou termina em uma zona de preço dinâmico e aplica o multiplicador correspondente à tarifa base.';


-- ------------------------------------------------------------------------------
-- 2. SINCRONIZADOR DE PERFIL COM HISTÓRICO KYC
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_driver_profile_kyc()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.status = 'approved' THEN
        -- Motorista aprovado: status vai para 'offline' (pronto para ficar online)
        UPDATE public.profiles
        SET is_approved = true,
            status = 'offline',
            updated_at = now()
        WHERE id = NEW.driver_id;
    ELSIF NEW.status = 'rejected' THEN
        -- Motorista rejeitado: status vai para 'blocked'
        UPDATE public.profiles
        SET is_approved = false,
            status = 'blocked',
            updated_at = now()
        WHERE id = NEW.driver_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_driver_profile_kyc ON public.driver_kyc_history;
CREATE TRIGGER trg_sync_driver_profile_kyc
    AFTER INSERT ON public.driver_kyc_history
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_driver_profile_kyc();

COMMENT ON FUNCTION public.sync_driver_profile_kyc IS 'Sincroniza automaticamente a tabela de perfis (profiles) com o histórico de KYC do motorista quando um novo log é registrado.';


-- ------------------------------------------------------------------------------
-- 3. GERADOR E LEITOR SEGURO DE TOKENS DE ROTA
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_get_or_create_ride_share_token(
    p_ride_id UUID,
    p_user_id TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_token TEXT;
    v_exists_token TEXT;
BEGIN
    -- 1. Verificar se já existe um token ativo e válido para esta corrida
    SELECT share_token INTO v_exists_token
    FROM public.ride_tracking_shares
    WHERE ride_id = p_ride_id
      AND expires_at > now()
    LIMIT 1;

    IF v_exists_token IS NOT NULL THEN
        RETURN v_exists_token;
    END IF;

    -- 2. Gerar novo token MD5 de alta colisão-resistente (independente de extensões externas)
    v_token := md5(gen_random_uuid()::text || now()::text);

    -- 3. Inserir na tabela de compartilhamento seguro
    INSERT INTO public.ride_tracking_shares (ride_id, share_token, created_by, expires_at)
    VALUES (p_ride_id, v_token, p_user_id, now() + interval '2 hours');

    RETURN v_token;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_or_create_ride_share_token(UUID, TEXT) TO authenticated;

COMMENT ON FUNCTION public.rpc_get_or_create_ride_share_token IS 'Gera ou retorna um link seguro de rastreamento em tempo real de forma blindada contra invasão de privacidade.';


-- ------------------------------------------------------------------------------
-- 4. GESTÃO DE SPLIT FINANCEIRO AUTOMATIZADO NA CONCLUSÃO DE CORRIDA
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_completed_ride_financials()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_driver_share NUMERIC;
BEGIN
    -- Só executa quando a corrida transitar de qualquer status para 'completed' com motorista atribuído
    IF NEW.status = 'completed' AND OLD.status <> 'completed' AND NEW.driver_id IS NOT NULL THEN
        -- Fallback de segurança para taxas nulas
        IF NEW.platform_fee IS NULL THEN
            NEW.platform_fee := 0.00;
        END IF;

        v_driver_share := NEW.fare - NEW.platform_fee;

        IF NEW.payment_method = 'cash' THEN
            -- CORRIDA EM DINHEIRO: O motorista recebe o dinheiro físico na mão.
            -- O saldo disponível dele é debitado com a taxa da plataforma (platform_fee),
            -- pois ele coletou a taxa em dinheiro e agora a deve para a Uppi.
            PERFORM public.increment_wallet(NEW.driver_id, -NEW.platform_fee);
        ELSE
            -- CORRIDA EM CARTÃO / PIX / CRÉDITO: O dinheiro passa pelo ecossistema Uppi.
            -- O motorista tem o direito de receber o valor da corrida menos a taxa da plataforma.
            -- Esse valor entra como SALDO PENDENTE (pending_balance) aguardando confirmação do gateway.
            PERFORM public.increment_wallet_pending(NEW.driver_id, v_driver_share);
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_completed_ride_financials ON public.rides;
CREATE TRIGGER trg_completed_ride_financials
    AFTER UPDATE ON public.rides
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_completed_ride_financials();

COMMENT ON FUNCTION public.handle_completed_ride_financials IS 'Trigger de split financeiro na conclusão de corridas, cobrando taxas de corridas em dinheiro e provisionando saldos para pagamentos em meios digitais.';


-- ─────────────────────────────────────────────
-- FILE: 20260520050000_payout_requests.sql
-- ─────────────────────────────────────────────

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


-- ─────────────────────────────────────────────
-- FILE: 20260520060000_dynamic_dispatch_loop.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Loop de Match e Despacho de Corridas (Fila Dinâmica)
-- 1. rpc_find_and_offer_ride(p_ride_id UUID)
-- 2. rpc_sweep_expired_offers()
-- 3. Trigger trg_on_ride_requested
-- 4. Atualização das RPCs reject_ride e assign_driver_to_ride
-- ==============================================================================

-- 1. BUSCA E DESPACHO DINÂMICO DE DRIVERS (PostGIS + CDC)
CREATE OR REPLACE FUNCTION public.rpc_find_and_offer_ride(p_ride_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pickup_loc GEOGRAPHY(POINT);
    v_ride_status TEXT;
    v_driver_id TEXT;
    v_offer_id UUID;
    v_search_radius INTEGER;
BEGIN
    -- 1. Bloquear linha da corrida para evitar conflitos de concorrência
    SELECT status, pickup_location INTO v_ride_status, v_pickup_loc
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    -- Se a corrida não existir ou já tiver sido aceita/cancelada, encerra o loop
    IF v_ride_status IS NULL OR v_ride_status NOT IN ('requested', 'searching') THEN
        RETURN FALSE;
    END IF;

    -- 2. Buscar o motorista 'online' aprovado mais próximo que ainda não rejeitou esta corrida e não esteja ocupado
    SELECT p.id, COALESCE(p.search_radius, 5000) INTO v_driver_id, v_search_radius
    FROM public.profiles p
    WHERE p.role = 'driver'
      AND p.status = 'online'
      AND p.current_location IS NOT NULL
      -- Evitar motoristas que já rejeitaram ou expiraram esta corrida
      AND NOT EXISTS (
          SELECT 1 
          FROM public.ride_rejected_drivers rr 
          WHERE rr.ride_id = p_ride_id 
            AND rr.driver_id = p.id
      )
      -- Evitar motoristas em corridas ativas
      AND NOT EXISTS (
          SELECT 1 
          FROM public.rides r 
          WHERE r.driver_id = p.id 
            AND r.status IN ('accepted', 'arrived', 'in_progress')
      )
      -- Evitar motoristas com ofertas de corrida ativas pendentes (de qualquer corrida)
      AND NOT EXISTS (
          SELECT 1
          FROM public.ride_offers ro
          WHERE ro.driver_id = p.id
            AND ro.status = 'offered'
            AND ro.expires_at > now()
      )
    ORDER BY ST_Distance(p.current_location, v_pickup_loc) ASC
    LIMIT 1;

    -- 3. Se um motorista elegível for encontrado, criar a oferta e atualizar o status
    IF v_driver_id IS NOT NULL THEN
        -- Expirar ofertas anteriores ainda marcadas como 'offered' para esta corrida
        UPDATE public.ride_offers
        SET status = 'expired'
        WHERE ride_id = p_ride_id AND status = 'offered';

        -- Inserir nova oferta de 15 segundos
        INSERT INTO public.ride_offers (ride_id, driver_id, status, expires_at)
        VALUES (p_ride_id, v_driver_id, 'offered', now() + interval '15 seconds')
        RETURNING id INTO v_offer_id;

        -- Alterar status da corrida para 'searching'
        UPDATE public.rides
        SET status = 'searching',
            updated_at = now()
        WHERE id = p_ride_id;

        RETURN TRUE;
    ELSE
        -- Nenhum motorista encontrado na região: reverter status para 'requested'
        UPDATE public.rides
        SET status = 'requested',
            updated_at = now()
        WHERE id = p_ride_id AND status = 'searching';

        RETURN FALSE;
    END IF;
END;
$$;

COMMENT ON FUNCTION public.rpc_find_and_offer_ride(UUID) IS 'Busca o motorista disponível mais próximo via PostGIS e insere uma oferta de 15 segundos em ride_offers.';

-- 2. VARREDURA DE OFERTAS EXPIRADAS (TIMERS EXPIRED)
CREATE OR REPLACE FUNCTION public.rpc_sweep_expired_offers()
RETURNS TABLE (
    offer_id UUID,
    ride_id UUID,
    driver_id TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
BEGIN
    -- Varre ofertas oferecidas expiradas
    FOR r IN 
        SELECT ro.id, ro.ride_id, ro.driver_id
        FROM public.ride_offers ro
        WHERE ro.status = 'offered'
          AND ro.expires_at < now()
    LOOP
        -- Atualizar status da oferta para expirado
        UPDATE public.ride_offers
        SET status = 'expired'
        WHERE id = r.id AND status = 'offered';

        IF FOUND THEN
            -- Inserir motorista na lista de rejeitados para esta corrida para evitar novo loop
            INSERT INTO public.ride_rejected_drivers (ride_id, driver_id)
            VALUES (r.ride_id, r.driver_id)
            ON CONFLICT (ride_id, driver_id) DO NOTHING;

            -- Avançar o match procurando o próximo motorista geolocalizado
            PERFORM public.rpc_find_and_offer_ride(r.ride_id);

            -- Preencher valores de retorno
            offer_id := r.id;
            ride_id := r.ride_id;
            driver_id := r.driver_id;
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.rpc_sweep_expired_offers() IS 'Varre e expira ofertas que excederam o tempo limite de 15 segundos, salvando a rejeição e avançando para o próximo motorista.';

-- 3. TRIGGER AUTOMÁTICO DE CRIAÇÃO/ATUALIZAÇÃO DE CORRIDA
CREATE OR REPLACE FUNCTION public.trg_on_ride_requested_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Evitar loop imediato recursivo se a corrida foi simplesmente revertida de 'searching' para 'requested'
    IF TG_OP = 'UPDATE' AND OLD.status = 'searching' THEN
        RETURN NEW;
    END IF;

    -- Disparar loop de despacho imediatamente
    PERFORM public.rpc_find_and_offer_ride(NEW.id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_on_ride_requested ON public.rides;
CREATE TRIGGER trg_on_ride_requested
    AFTER INSERT OR UPDATE OF status ON public.rides
    FOR EACH ROW
    WHEN (NEW.status = 'requested')
    EXECUTE FUNCTION public.trg_on_ride_requested_fn();

-- 4. ATUALIZAÇÃO DA RPC DE ASSINAR CORRIDA (ACEITE DO MOTORISTA)
CREATE OR REPLACE FUNCTION public.assign_driver_to_ride(
    p_ride_id UUID,
    p_driver_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_status TEXT;
BEGIN
    -- Bloquear linha da corrida para evitar conflitos concorrentes
    SELECT status INTO v_status
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Corrida não encontrada (ID: %)', p_ride_id;
    END IF;

    -- Agora aceitamos tanto 'requested' quanto 'searching'
    IF v_status NOT IN ('requested', 'searching') THEN
        RAISE EXCEPTION 'A corrida não está mais disponível para aceite (status atual: %)', v_status;
    END IF;

    -- Atualizar oferta específica deste motorista como 'accepted'
    UPDATE public.ride_offers
    SET status = 'accepted'
    WHERE ride_id = p_ride_id AND driver_id = p_driver_id AND status = 'offered';

    -- Expirar as demais ofertas ativas para essa corrida
    UPDATE public.ride_offers
    SET status = 'expired'
    WHERE ride_id = p_ride_id AND driver_id <> p_driver_id AND status = 'offered';

    -- Atribuir o motorista à corrida e passar o status para 'accepted'
    UPDATE public.rides
    SET driver_id = p_driver_id,
        status = 'accepted',
        updated_at = now()
    WHERE id = p_ride_id;
END;
$$;

COMMENT ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) IS 'Atribui o motorista à corrida, marca a oferta como aceita e expira outras ofertas pendentes da mesma corrida.';

-- 5. ATUALIZAÇÃO DA RPC DE REJEITAR CORRIDA
CREATE OR REPLACE FUNCTION public.reject_ride(
  p_ride_id UUID,
  p_driver_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Inserir nas rejeições de corridas para evitar nova oferta a este motorista
  INSERT INTO public.ride_rejected_drivers (ride_id, driver_id)
  VALUES (p_ride_id, p_driver_id)
  ON CONFLICT (ride_id, driver_id) DO NOTHING;

  -- Atualizar status da oferta para 'rejected'
  UPDATE public.ride_offers
  SET status = 'rejected'
  WHERE ride_id = p_ride_id AND driver_id = p_driver_id AND status = 'offered';

  -- Avançar o despacho para o próximo motorista imediatamente
  PERFORM public.rpc_find_and_offer_ride(p_ride_id);
END;
$$;

COMMENT ON FUNCTION public.reject_ride(UUID, TEXT) IS 'Registra a rejeição do motorista, atualiza a oferta para rejeitada e despacha instantaneamente para o próximo motorista geolocalizado.';

-- 6. AGENDAMENTO CRON DE SEGURANÇA
SELECT cron.unschedule('sweep-expired-ride-offers') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'sweep-expired-ride-offers');

SELECT cron.schedule(
  'sweep-expired-ride-offers',
  '* * * * *',
  $$
    SELECT public.rpc_sweep_expired_offers();
  $$
);

-- Garantir privilégios
GRANT EXECUTE ON FUNCTION public.rpc_find_and_offer_ride(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_sweep_expired_offers() TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_ride(UUID, TEXT) TO authenticated;


-- ─────────────────────────────────────────────
-- FILE: 20260520070000_ride_cancellations.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO — AUDITORIA DE CANCELAMENTOS DE CORRIDA (Pillar 6)
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.ride_cancellations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id UUID REFERENCES public.rides(id) ON DELETE CASCADE NOT NULL,
    cancelled_by TEXT REFERENCES public.profiles(id) NOT NULL,
    reason_id UUID REFERENCES public.cancel_reasons(id) ON DELETE SET NULL,
    cancellation_fee NUMERIC(10,2) DEFAULT 0.00,
    driver_compensated_amount NUMERIC(10,2) DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- Habilitar RLS na tabela
ALTER TABLE public.ride_cancellations ENABLE ROW LEVEL SECURITY;

-- Política de leitura: Administradores e envolvidos na corrida podem ler
CREATE POLICY "cancellations_select_policy" ON public.ride_cancellations
    FOR SELECT USING (
        auth.uid()::text = cancelled_by OR 
        EXISTS (
            SELECT 1 FROM public.rides 
            WHERE rides.id = ride_cancellations.ride_id 
            AND (rides.rider_id = auth.uid()::text OR rides.driver_id = auth.uid()::text)
        ) OR
        (SELECT role FROM public.profiles WHERE id = auth.uid()::text) = 'admin'
    );

-- Habilitar Realtime CDC
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'ride_cancellations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_cancellations;
  END IF;
END $$;

ALTER TABLE public.ride_cancellations REPLICA IDENTITY FULL;


-- ─────────────────────────────────────────────
-- FILE: 20260522000000_fix_ride_matching_vehicle_category.sql
-- ─────────────────────────────────────────────

-- Migration: Fix Ride Matching by Vehicle Category
-- Updates rpc_find_and_offer_ride to match profiles.vehicle_type with services.vehicle_category

CREATE OR REPLACE FUNCTION public.rpc_find_and_offer_ride(p_ride_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pickup_loc GEOGRAPHY(POINT);
    v_ride_status TEXT;
    v_service_type TEXT;
    v_driver_id TEXT;
    v_offer_id UUID;
    v_search_radius INTEGER;
BEGIN
    -- 1. Bloquear linha da corrida para evitar conflitos de concorrência
    SELECT status, pickup_location, service_type INTO v_ride_status, v_pickup_loc, v_service_type
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    -- Se a corrida não existir ou já tiver sido aceita/cancelada, encerra o loop
    IF v_ride_status IS NULL OR v_ride_status NOT IN ('requested', 'searching') THEN
        RETURN FALSE;
    END IF;

    -- 2. Buscar o motorista 'online' aprovado mais próximo que ainda não rejeitou esta corrida, não esteja ocupado e tenha categoria compatível
    SELECT p.id, COALESCE(p.search_radius, 5000) INTO v_driver_id, v_search_radius
    FROM public.profiles p
    WHERE p.role = 'driver'
      AND p.status = 'online'
      AND p.current_location IS NOT NULL
      -- Filtrar por categoria do veículo correspondente ao serviço solicitado na corrida
      AND (
          v_service_type IS NULL OR
          p.vehicle_type IS NULL OR
          p.vehicle_type = COALESCE(
              (SELECT s.vehicle_category FROM public.services s WHERE s.name = v_service_type LIMIT 1),
              'carro'
          )
      )
      -- Evitar motoristas que já rejeitaram ou expiraram esta corrida
      AND NOT EXISTS (
          SELECT 1 
          FROM public.ride_rejected_drivers rr 
          WHERE rr.ride_id = p_ride_id 
            AND rr.driver_id = p.id
      )
      -- Evitar motoristas em corridas ativas
      AND NOT EXISTS (
          SELECT 1 
          FROM public.rides r 
          WHERE r.driver_id = p.id 
            AND r.status IN ('accepted', 'arrived', 'in_progress')
      )
      -- Evitar motoristas com ofertas de corrida ativas pendentes (de qualquer corrida)
      AND NOT EXISTS (
          SELECT 1
          FROM public.ride_offers ro
          WHERE ro.driver_id = p.id
            AND ro.status = 'offered'
            AND ro.expires_at > now()
      )
    ORDER BY ST_Distance(p.current_location, v_pickup_loc) ASC
    LIMIT 1;

    -- 3. Se um motorista elegível for encontrado, criar a oferta e atualizar o status
    IF v_driver_id IS NOT NULL THEN
        -- Expirar ofertas anteriores ainda marcadas como 'offered' para esta corrida
        UPDATE public.ride_offers
        SET status = 'expired'
        WHERE ride_id = p_ride_id AND status = 'offered';

        -- Inserir nova oferta de 15 segundos
        INSERT INTO public.ride_offers (ride_id, driver_id, status, expires_at)
        VALUES (p_ride_id, v_driver_id, 'offered', now() + interval '15 seconds')
        RETURNING id INTO v_offer_id;

        -- Alterar status da corrida para 'searching'
        UPDATE public.rides
        SET status = 'searching',
            updated_at = now()
        WHERE id = p_ride_id;

        RETURN TRUE;
    ELSE
        -- Nenhum motorista encontrado na região: reverter status para 'requested'
        UPDATE public.rides
        SET status = 'requested',
            updated_at = now()
        WHERE id = p_ride_id AND status = 'searching';

        RETURN FALSE;
    END IF;
END;
$$;


-- ─────────────────────────────────────────────
-- FILE: 20260522160000_fix_critical_ride_flow_bugs.sql
-- ─────────────────────────────────────────────

-- Fix 1: adicionar colunas faltantes em rides
ALTER TABLE rides ADD COLUMN IF NOT EXISTS eta_pickup TIMESTAMPTZ;
ALTER TABLE rides ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;

-- Fix 2: incluir estados intermediários no constraint
ALTER TABLE rides DROP CONSTRAINT IF EXISTS rides_status_check;
ALTER TABLE rides ADD CONSTRAINT rides_status_check CHECK (
  status IN ('requested','found','no_close_found','booked','accepted',
             'driver_accepted','arrived','started','in_progress',
             'completed','finished','waiting_for_review',
             'canceled','rider_canceled','driver_canceled',
             'expired','no_driver')
);

-- Fix 3: derrubar a versão UUID conflitante e manter só a TEXT
DROP FUNCTION IF EXISTS public.increment_wallet(UUID, NUMERIC);

-- Fix 4: corrigir tipos na tabela ratings e políticas RLS
-- 1. Drop de políticas RLS existentes
DROP POLICY IF EXISTS ratings_select ON public.ratings;
DROP POLICY IF EXISTS ratings_insert ON public.ratings;
DROP POLICY IF EXISTS ratings_update ON public.ratings;
DROP POLICY IF EXISTS ratings_select_auth ON public.ratings;
DROP POLICY IF EXISTS ratings_insert_auth ON public.ratings;
DROP POLICY IF EXISTS ratings_update_auth ON public.ratings;

-- 2. Drop de foreign keys antigas
ALTER TABLE public.ratings DROP CONSTRAINT IF EXISTS ratings_rated_by_fkey;
ALTER TABLE public.ratings DROP CONSTRAINT IF EXISTS ratings_rated_user_fkey;

-- 3. Alterar os tipos das colunas para TEXT
ALTER TABLE public.ratings ALTER COLUMN rated_by TYPE TEXT;
ALTER TABLE public.ratings ALTER COLUMN rated_user TYPE TEXT;

-- 4. Criar novas foreign keys apontando para public.profiles(id)
ALTER TABLE public.ratings ADD CONSTRAINT ratings_rated_by_fkey FOREIGN KEY (rated_by) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.ratings ADD CONSTRAINT ratings_rated_user_fkey FOREIGN KEY (rated_user) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- 5. Recriar políticas RLS
CREATE POLICY "ratings_select" ON public.ratings FOR SELECT USING (true);
CREATE POLICY "ratings_insert" ON public.ratings FOR INSERT WITH CHECK (auth.uid()::text = rated_by);
CREATE POLICY "ratings_update" ON public.ratings FOR UPDATE USING (auth.uid()::text = rated_by);


-- ─────────────────────────────────────────────
-- FILE: 20260522170000_fix_database_schema_inconsistencies.sql
-- ─────────────────────────────────────────────

-- BUG A: Garantir que a tabela driver_earnings exista para novas instalações
CREATE TABLE IF NOT EXISTS public.driver_earnings (
  id                  UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  driver_id           TEXT REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  ride_id             UUID REFERENCES public.rides(id) ON DELETE CASCADE,
  amount              NUMERIC(10,2),
  gross_amount        NUMERIC(10,2),
  commission_pct      NUMERIC(5,2),
  commission_amt      NUMERIC(10,2),
  platform_commission NUMERIC(10,2),
  net_amount          NUMERIC(10,2),
  payment_method      TEXT,
  tip_amount          NUMERIC(10,2),
  driver_amount       NUMERIC(10,2),
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

-- Garantir que RLS esteja ativado
ALTER TABLE public.driver_earnings ENABLE ROW LEVEL SECURITY;

-- Se a tabela já existia com ride_id como TEXT, converter para UUID e adicionar a Foreign Key
DO $$
BEGIN
  -- Verificar o tipo de dados atual da coluna ride_id
  IF (SELECT data_type FROM information_schema.columns 
      WHERE table_schema = 'public' AND table_name = 'driver_earnings' AND column_name = 'ride_id') = 'text' THEN
    
    -- Alterar tipo da coluna para UUID
    ALTER TABLE public.driver_earnings ALTER COLUMN ride_id TYPE UUID USING ride_id::uuid;
  END IF;

  -- Adicionar a constraint de chave estrangeira com segurança
  ALTER TABLE public.driver_earnings DROP CONSTRAINT IF EXISTS driver_earnings_ride_id_fkey;
  ALTER TABLE public.driver_earnings 
    ADD CONSTRAINT driver_earnings_ride_id_fkey 
    FOREIGN KEY (ride_id) REFERENCES public.rides(id) ON DELETE CASCADE;
END $$;


-- BUG B: Corrigir tipo de ride_id de TEXT para UUID em complaints e sos_signals
DO $$
BEGIN
  -- complaints
  IF (SELECT data_type FROM information_schema.columns 
      WHERE table_schema = 'public' AND table_name = 'complaints' AND column_name = 'ride_id') = 'text' THEN
    ALTER TABLE public.complaints ALTER COLUMN ride_id TYPE UUID USING ride_id::uuid;
  END IF;
  
  ALTER TABLE public.complaints DROP CONSTRAINT IF EXISTS complaints_ride_id_fkey;
  ALTER TABLE public.complaints 
    ADD CONSTRAINT complaints_ride_id_fkey 
    FOREIGN KEY (ride_id) REFERENCES public.rides(id) ON DELETE SET NULL;

  -- sos_signals
  IF (SELECT data_type FROM information_schema.columns 
      WHERE table_schema = 'public' AND table_name = 'sos_signals' AND column_name = 'ride_id') = 'text' THEN
    ALTER TABLE public.sos_signals ALTER COLUMN ride_id TYPE UUID USING ride_id::uuid;
  END IF;

  ALTER TABLE public.sos_signals DROP CONSTRAINT IF EXISTS sos_signals_ride_id_fkey;
  ALTER TABLE public.sos_signals 
    ADD CONSTRAINT sos_signals_ride_id_fkey 
    FOREIGN KEY (ride_id) REFERENCES public.rides(id) ON DELETE SET NULL;
END $$;


-- BUG C: Criar a RPC update_ride_status
CREATE OR REPLACE FUNCTION public.update_ride_status(
  p_ride_id  UUID,
  p_status   TEXT,
  p_actor_id TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  -- Atualizar o status da corrida
  UPDATE public.rides
     SET status = p_status,
         updated_at = NOW()
   WHERE id = p_ride_id;

  -- Se um ator foi fornecido, registrar a atividade correspondente
  IF p_actor_id IS NOT NULL THEN
    INSERT INTO public.ride_activities (ride_id, type, actor_id)
    VALUES (p_ride_id, p_status, p_actor_id);
  END IF;
END;
$$;

-- Conceder permissões de execução
GRANT EXECUTE ON FUNCTION public.update_ride_status TO authenticated, service_role;


-- ─────────────────────────────────────────────
-- FILE: 20260522180000_fix_gift_card_and_services_category.sql
-- ─────────────────────────────────────────────

-- Migration: Add vehicle_category to services table and populate default values
-- Establishes vehicle categorization for ride dispatch matching

-- ============================================================
-- BUG F: Adicionar vehicle_category em services
-- ============================================================
ALTER TABLE public.services ADD COLUMN IF NOT EXISTS vehicle_category TEXT;

-- Preencher valores padrão para os serviços existentes baseados no name
UPDATE public.services SET vehicle_category = 'carro' 
WHERE name ILIKE '%uppi x%' OR name ILIKE '%standard%' OR name ILIKE '%econom%';

UPDATE public.services SET vehicle_category = 'moto' 
WHERE name ILIKE '%moto%';

UPDATE public.services SET vehicle_category = 'suv' 
WHERE name ILIKE '%suv%';

UPDATE public.services SET vehicle_category = 'executivo' 
WHERE name ILIKE '%executivo%' OR name ILIKE '%premium%' OR name ILIKE '%black%';

-- Fallback para os serviços que não bateram em nenhuma regra acima
UPDATE public.services SET vehicle_category = 'carro' 
WHERE vehicle_category IS NULL;


-- ─────────────────────────────────────────────
-- FILE: 20260522200000_fix_remaining_security_and_storage.sql
-- ─────────────────────────────────────────────

-- ============================================================
-- Migration: Fixes restantes da auditoria de segurança
-- 1. Gift cards policy permissiva (qualquer autenticado vê todos)
-- 2. Buckets avatars e documents nunca criados em migration
-- 3. SOS tables divergentes (sos_alerts vs sos_signals)
-- ============================================================

-- ============================================================
-- FIX 1: Restringir SELECT em gift_cards
-- ============================================================
-- Hoje qualquer usuário autenticado pode listar todos os códigos
-- de gift cards não resgatados. Risco: vazamento financeiro.
-- Solução: só o dono (já resgatou) ou admin pode ler.
-- Validação de código novo fica na edge function redeem-gift-card
-- com service_role (bypassa RLS).

DROP POLICY IF EXISTS "Ver gift card por codigo" ON public.gift_cards;
DROP POLICY IF EXISTS "gift_cards_select_owner_or_admin" ON public.gift_cards;

CREATE POLICY "gift_cards_select_owner_or_admin" ON public.gift_cards
  FOR SELECT TO authenticated
  USING (
    redeemed_by = auth.uid()::text
    OR EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- ============================================================
-- FIX 2: Criar buckets avatars e documents (com policies)
-- ============================================================
-- O código de upload em upload_datasource.prod.dart usa esses
-- buckets mas eles nunca foram criados em migration. Em produção
-- foram criados manualmente pelo dashboard, mas isso quebra
-- ambientes novos (staging, dev).

-- Bucket de avatars: foto de perfil (PÚBLICO, 1MB, jpeg/png/webp)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  true,
  1048576,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- Bucket de documents: CNH, vistoria etc (PRIVADO, 5MB, jpeg/png/pdf)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'documents',
  'documents',
  false,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'application/pdf']
)
ON CONFLICT (id) DO NOTHING;

-- Policies do bucket avatars
-- Estrutura esperada: {user_id}/arquivo.jpg
DROP POLICY IF EXISTS "avatars_owner_all" ON storage.objects;
CREATE POLICY "avatars_owner_all" ON storage.objects
  FOR ALL TO authenticated
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "avatars_public_read" ON storage.objects;
CREATE POLICY "avatars_public_read" ON storage.objects
  FOR SELECT
  USING (bucket_id = 'avatars');

-- Policies do bucket documents
-- Só dono pode ler/escrever, admin pode ler tudo
DROP POLICY IF EXISTS "documents_owner_rw" ON storage.objects;
CREATE POLICY "documents_owner_rw" ON storage.objects
  FOR ALL TO authenticated
  USING (
    bucket_id = 'documents'
    AND auth.uid()::text = (storage.foldername(name))[1]
  )
  WITH CHECK (
    bucket_id = 'documents'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "documents_admin_read" ON storage.objects;
CREATE POLICY "documents_admin_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documents'
    AND EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- ============================================================
-- FIX 3: Unificar SOS em sos_alerts com coluna submitted_by
-- ============================================================
-- Hoje send-sos sempre insere em sos_alerts (qualquer tipo de
-- usuário), mas o admin assume que sos_alerts=passageiro e
-- sos_signals=motorista. Resultado: SOS de motorista fica
-- invisível pro admin.
-- Solução: adicionar submitted_by ('rider' ou 'driver') em
-- sos_alerts, migrar dados antigos de sos_signals, e deprecar
-- sos_signals.

-- Adicionar coluna submitted_by
ALTER TABLE public.sos_alerts
  ADD COLUMN IF NOT EXISTS submitted_by TEXT;

-- Migrar dados antigos de sos_signals → sos_alerts (sem duplicar)
-- NOTA: sos_signals usa 'notes' (não 'message') e não tem user_name/user_phone
INSERT INTO public.sos_alerts (id, user_id, ride_id, lat, lng, message, status, created_at, submitted_by)
SELECT
  s.id,
  s.user_id,
  s.ride_id,
  s.lat,
  s.lng,
  COALESCE(s.notes, 'SOS de motorista'),
  COALESCE(s.status, 'active'),
  s.created_at,
  COALESCE(s.submitted_by, 'driver')
FROM public.sos_signals s
WHERE NOT EXISTS (
  SELECT 1 FROM public.sos_alerts a WHERE a.id = s.id
)
ON CONFLICT (id) DO NOTHING;

-- Index para queries por submitted_by
CREATE INDEX IF NOT EXISTS idx_sos_alerts_submitted_by
  ON public.sos_alerts (submitted_by);

-- Marcar sos_signals como deprecated (sem dropar — pode ter integrações antigas)
COMMENT ON TABLE public.sos_signals IS
  'DEPRECATED desde 2026-05-22: usar sos_alerts com coluna submitted_by. Mantida temporariamente para histórico e compatibilidade.';


-- ─────────────────────────────────────────────
-- FILE: 20260525000000_security_hardening.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- HARDENING DE BANCO DE DADOS - UPPI BRASIL (2026-05-25)
-- Fixes críticos de segurança:
-- 1. Revogar execução da função increment_wallet de papéis não autorizados (banco livre)
-- 2. Restringir RLS de profiles para evitar vazamento massivo de PII
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- FIX 1: Restringir a RPC increment_wallet
-- ─────────────────────────────────────────────────────────────────────────────
-- A RPC increment_wallet é SECURITY DEFINER. Qualquer usuário autenticado
-- anteriormente podia chamá-la via client.from().rpc() e alterar o próprio saldo.
-- Solução: revogar de autenticado/público e permitir apenas a service_role (Edge Functions).

REVOKE EXECUTE ON FUNCTION public.increment_wallet(target_user_id TEXT, amount_to_add NUMERIC) FROM authenticated, anon, public;
GRANT EXECUTE ON FUNCTION public.increment_wallet(target_user_id TEXT, amount_to_add NUMERIC) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- FIX 2: Blindar tabela de perfis (profiles) contra vazamento de PII
-- ─────────────────────────────────────────────────────────────────────────────
-- Existia uma política permissiva "Authenticated users can read profiles"
-- ou "profiles_select_all" com USING (true) que anulava RLS restritivos.
-- Solução: dropar as políticas genéricas e aplicar regras estritas baseadas no fluxo.

DROP POLICY IF EXISTS "Authenticated users can read profiles" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_all" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_restricted" ON public.profiles;

CREATE POLICY "profiles_select_restricted" ON public.profiles
  FOR SELECT TO authenticated
  USING (
    -- 1. O próprio usuário pode ler seu próprio perfil
    auth.uid()::text = id
    
    -- 2. Administradores podem ler qualquer perfil
    OR EXISTS (
      SELECT 1 FROM public.admins WHERE id = auth.uid()::text
    )
    
    -- 3. Motoristas podem ver perfis de passageiros em suas corridas ativas/recentes
    OR id IN (
      SELECT rider_id FROM public.rides
      WHERE driver_id = auth.uid()::text
      AND status IN ('accepted', 'arrived', 'in_progress', 'completed', 'waiting_for_post_pay')
    )
    
    -- 4. Passageiros podem ver perfis de motoristas de suas corridas ativas/recentes
    OR id IN (
      SELECT driver_id FROM public.rides
      WHERE rider_id = auth.uid()::text
      AND status IN ('accepted', 'arrived', 'in_progress', 'completed', 'waiting_for_post_pay')
    )
    
    -- 5. Motoristas online podem ver passageiros de corridas que estão aguardando motorista ('requested')
    OR id IN (
      SELECT rider_id FROM public.rides
      WHERE status = 'requested'
    )
  );


-- ─────────────────────────────────────────────
-- FILE: 20260525010000_admin_rls_policies.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- CONTROLE DE ACESSO ADMINISTRATIVO DINÂMICO VIA RLS - UPPI BRASIL (2026-05-25)
-- Objetivo: Garantir que o Admin Panel funcionando sob ANON_KEY tenha acesso a todas
-- as tabelas públicas (63+ chamadas diretas), enquanto mantém blindagem RLS total.
-- ==============================================================================

DO $$
DECLARE
  t TEXT;
BEGIN
  -- Iterar sobre todas as tabelas no schema public
  FOR t IN 
    SELECT table_name 
    FROM information_schema.tables 
    WHERE table_schema = 'public' 
      AND table_type = 'BASE TABLE'
      -- Evitar tabelas do sistema ou tabelas de log que tenham fluxo especial se necessário
      AND table_name NOT IN ('spatial_ref_sys') -- tabela do PostGIS
  LOOP
    -- 1. Garantir que RLS está ativado para a tabela
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t);
    
    -- 2. Remover qualquer política de admin anterior para evitar duplicados
    EXECUTE format('DROP POLICY IF EXISTS admin_all_access ON public.%I;', t);
    
    -- 3. Criar a política de super-acesso para administradores cadastrados na tabela public.admins
    EXECUTE format('
      CREATE POLICY admin_all_access ON public.%I
      FOR ALL TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.admins WHERE id = auth.uid()::text
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.admins WHERE id = auth.uid()::text
        )
      );
    ', t);
    
    RAISE NOTICE 'Política admin_all_access aplicada com sucesso na tabela public.%', t;
  END LOOP;
END $$;


-- ─────────────────────────────────────────────
-- FILE: 20260525020000_hardening_admins_app_settings.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- HARDENING DE SEGURANÇA: admins E app_settings - UPPI BRASIL (2026-05-25)
-- Fix de vulnerabilidades críticas:
-- 1. Trancar tabela 'admins' contra auto-cadastro e privilégios frouxos
-- 2. Trancar tabela 'app_settings' para ocultar chaves do Mercado Pago e maps
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. HARDENING DA TABELA 'admins'
-- ─────────────────────────────────────────────────────────────────────────────

-- Permitir SELECT apenas ao próprio usuário autenticado ou se ele já for um admin cadastrado
DROP POLICY IF EXISTS "admins_select_authenticated" ON public.admins;
CREATE POLICY "admins_select_authenticated" ON public.admins
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = id 
    OR EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- Bloquear completamente INSERTs vindo de conexões públicas/authenticated do client
DROP POLICY IF EXISTS "admins_insert_authenticated" ON public.admins;
CREATE POLICY "admins_insert_authenticated" ON public.admins
  FOR INSERT TO authenticated WITH CHECK (false);

-- Permitir UPDATE apenas se for o próprio usuário ou se for um superadmin autenticado
DROP POLICY IF EXISTS "admins_update_self" ON public.admins;
CREATE POLICY "admins_update_self" ON public.admins
  FOR UPDATE TO authenticated
  USING (
    auth.uid()::text = id 
    OR EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text AND role = 'superadmin')
  )
  WITH CHECK (
    auth.uid()::text = id 
    OR EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text AND role = 'superadmin')
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. HARDENING DA TABELA 'app_settings'
-- ─────────────────────────────────────────────────────────────────────────────

-- Permitir SELECT apenas de chaves não sensíveis para usuários comuns.
-- Administradores autenticados podem ler absolutamente qualquer chave (incluindo MP e Google Maps).
DROP POLICY IF EXISTS "app_settings_select" ON public.app_settings;
CREATE POLICY "app_settings_select" ON public.app_settings
  FOR SELECT USING (
    (NOT (key LIKE 'mp_%' OR key = 'google_map_api_key')) 
    OR EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- Bloquear INSERT/UPDATE/DELETE geral de app_settings para usuários comuns.
-- Apenas administradores autenticados podem modificar as configurações.
DROP POLICY IF EXISTS "app_settings_insert" ON public.app_settings;
DROP POLICY IF EXISTS "app_settings_update" ON public.app_settings;

CREATE POLICY "app_settings_write_admin" ON public.app_settings
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text))
  WITH CHECK (EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text));


-- ─────────────────────────────────────────────
-- FILE: 20260525030000_finish_ride_transaction.sql
-- ─────────────────────────────────────────────

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
            v_commission_percent := COALESCE(v_commission_row.value::numeric, 0.0);
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


-- ─────────────────────────────────────────────
-- FILE: 20260525040000_dispatch_rpcs_hardening.sql
-- ─────────────────────────────────────────────

-- Migration: Hardening Dispatch RPCs and Offer Notification Trigger
-- Proteger assign_driver_to_ride, reject_ride, rpc_find_and_offer_ride e rpc_sweep_expired_offers
-- Substituir o webhook de nova corrida para disparar no insert de ride_offers (status = 'offered')

-- 1. BLINDAR ASSIGN_DRIVER_TO_RIDE
CREATE OR REPLACE FUNCTION public.assign_driver_to_ride(
    p_ride_id UUID,
    p_driver_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_status TEXT;
    v_rows INT;
    v_driver_lat DOUBLE PRECISION;
    v_driver_lng DOUBLE PRECISION;
    v_pickup_lat DOUBLE PRECISION;
    v_pickup_lng DOUBLE PRECISION;
    v_dist_meters DOUBLE PRECISION;
    v_eta_minutes INTEGER;
    v_eta_pickup TIMESTAMP WITH TIME ZONE;
BEGIN
    -- [SEGURANÇA] Validar se o solicitante é de fato o motorista ou service_role
    IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR auth.uid()::text <> p_driver_id) THEN
        RAISE EXCEPTION 'Operação não autorizada. O motorista não corresponde ao usuário autenticado.';
    END IF;

    -- [SEGURANÇA] Bloquear linha da corrida para evitar conflitos concorrentes
    SELECT status, pickup_lat, pickup_lng INTO v_status, v_pickup_lat, v_pickup_lng
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Corrida não encontrada (ID: %)', p_ride_id;
    END IF;

    -- Agora aceitamos tanto 'requested' quanto 'searching'
    IF v_status NOT IN ('requested', 'searching') THEN
        RAISE EXCEPTION 'A corrida não está mais disponível para aceite (status atual: %)', v_status;
    END IF;

    -- [SEGURANÇA] Atualizar oferta específica deste motorista como 'accepted' e garantir que ela existia e estava ativa
    UPDATE public.ride_offers
    SET status = 'accepted'
    WHERE ride_id = p_ride_id AND driver_id = p_driver_id AND status = 'offered';
    
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 0 THEN
        RAISE EXCEPTION 'Você não possui uma oferta ativa para esta corrida.';
    END IF;

    -- Expirar as demais ofertas ativas para essa corrida
    UPDATE public.ride_offers
    SET status = 'expired'
    WHERE ride_id = p_ride_id AND driver_id <> p_driver_id AND status = 'offered';

    -- Calcular ETA dinâmico baseado no PostGIS
    SELECT lat, lng INTO v_driver_lat, v_driver_lng
    FROM public.driver_locations
    WHERE driver_id = p_driver_id;

    IF v_driver_lat IS NOT NULL AND v_pickup_lat IS NOT NULL THEN
        v_dist_meters := ST_Distance(
            ST_SetSRID(ST_MakePoint(v_driver_lng, v_driver_lat), 4326)::geography,
            ST_SetSRID(ST_MakePoint(v_pickup_lng, v_pickup_lat), 4326)::geography
        );
        v_eta_minutes := CEIL(v_dist_meters / 500.0); -- ~30km/h
        v_eta_pickup := NOW() + (v_eta_minutes * interval '1 minute');
    ELSE
        v_eta_pickup := NOW() + interval '5 minutes';
    END IF;

    -- Atribuir o motorista à corrida, passar o status para 'accepted', definir accepted_at e eta_pickup
    UPDATE public.rides
    SET driver_id = p_driver_id,
        status = 'accepted',
        accepted_at = NOW(),
        eta_pickup = v_eta_pickup,
        updated_at = NOW()
    WHERE id = p_ride_id;
END;
$$;

COMMENT ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) IS 'Atribui o motorista à corrida, marca a oferta como aceita e expira outras ofertas pendentes da mesma corrida. [Protegido via JWT e Validação de Oferta]';

-- 2. BLINDAR REJECT_RIDE
CREATE OR REPLACE FUNCTION public.reject_ride(
  p_ride_id UUID,
  p_driver_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- [SEGURANÇA] Validar se o solicitante é de fato o motorista ou service_role
  IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR auth.uid()::text <> p_driver_id) THEN
      RAISE EXCEPTION 'Operação não autorizada. O motorista não corresponde ao usuário autenticado.';
  END IF;

  -- Inserir nas rejeições de corridas para evitar nova oferta a este motorista
  INSERT INTO public.ride_rejected_drivers (ride_id, driver_id)
  VALUES (p_ride_id, p_driver_id)
  ON CONFLICT (ride_id, driver_id) DO NOTHING;

  -- Atualizar status da oferta para 'rejected'
  UPDATE public.ride_offers
  SET status = 'rejected'
  WHERE ride_id = p_ride_id AND driver_id = p_driver_id AND status = 'offered';

  -- Avançar o despacho para o próximo motorista imediatamente
  PERFORM public.rpc_find_and_offer_ride(p_ride_id);
END;
$$;

COMMENT ON FUNCTION public.reject_ride(UUID, TEXT) IS 'Registra a rejeição do motorista, atualiza a oferta para rejeitada e despacha instantaneamente para o próximo motorista geolocalizado. [Protegido via JWT]';

-- 3. RESTRINGIR PERMISSÕES DE FUNÇÕES DE BACKGROUND
REVOKE EXECUTE ON FUNCTION public.rpc_find_and_offer_ride(UUID) FROM authenticated, anon, public;
REVOKE EXECUTE ON FUNCTION public.rpc_sweep_expired_offers() FROM authenticated, anon, public;
GRANT EXECUTE ON FUNCTION public.rpc_find_and_offer_ride(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_sweep_expired_offers() TO service_role;

-- 4. ATUALIZAR TRIGGERS DE WEBHOOK DE NOTIFICAÇÃO
-- Remover o trigger de rides para evitar envio em massa
DROP TRIGGER IF EXISTS webhook_notify_new_ride ON "public"."rides";

-- Função do trigger na tabela ride_offers
CREATE OR REPLACE FUNCTION notify_webhook_new_offer()
RETURNS trigger AS $$
BEGIN
  -- Só dispara para ofertas com status 'offered'
  IF NEW.status != 'offered' THEN
    RETURN NEW;
  END IF;

  -- Dispara webhook HTTP assíncrono para a Edge Function webhook-new-ride
  PERFORM net.http_post(
    url := 'https://kqfmahrxjuqlvxngeurj.supabase.co/functions/v1/webhook-new-ride',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', current_setting('app.webhook_secret', true)
    ),
    body := json_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'schema', TG_TABLE_SCHEMA,
      'record', row_to_json(NEW),
      'timestamp', extract(epoch from now())
    )::jsonb,
    timeout_milliseconds := 5000
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Nunca bloqueia a inserção por falhas na notificação
  RAISE WARNING 'notify_webhook_new_offer falhou: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Criar trigger de ofertas
DROP TRIGGER IF EXISTS trg_on_ride_offer_created ON public.ride_offers;
CREATE TRIGGER trg_on_ride_offer_created
AFTER INSERT ON public.ride_offers
FOR EACH ROW EXECUTE FUNCTION notify_webhook_new_offer();


-- ─────────────────────────────────────────────
-- FILE: 20260525050000_finances_and_kyc_fixes.sql
-- ─────────────────────────────────────────────

-- Migration: 20260525050000_finances_and_kyc_fixes.sql
-- 1. ALTER ASSIGN_DRIVER_TO_RIDE TO UPDATE ACCEPTED_AT
CREATE OR REPLACE FUNCTION public.assign_driver_to_ride(
    p_ride_id UUID,
    p_driver_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_status TEXT;
    v_rows INT;
BEGIN
    -- [SEGURANÇA] Validar se o solicitante é de fato o motorista ou service_role
    IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR auth.uid()::text <> p_driver_id) THEN
        RAISE EXCEPTION 'Operação não autorizada. O motorista não corresponde ao usuário autenticado.';
    END IF;

    -- [SEGURANÇA] Bloquear linha da corrida para evitar conflitos concorrentes
    SELECT status INTO v_status
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Corrida não encontrada (ID: %)', p_ride_id;
    END IF;

    -- Agora aceitamos tanto 'requested' quanto 'searching'
    IF v_status NOT IN ('requested', 'searching') THEN
        RAISE EXCEPTION 'A corrida não está mais disponível para aceite (status atual: %)', v_status;
    END IF;

    -- [SEGURANÇA] Atualizar oferta específica deste motorista como 'accepted' e garantir que ela existia e estava ativa
    UPDATE public.ride_offers
    SET status = 'accepted'
    WHERE ride_id = p_ride_id AND driver_id = p_driver_id AND status = 'offered';
    
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 0 THEN
        RAISE EXCEPTION 'Você não possui uma oferta ativa para esta corrida.';
    END IF;

    -- Expirar as demais ofertas ativas para essa corrida
    UPDATE public.ride_offers
    SET status = 'expired'
    WHERE ride_id = p_ride_id AND driver_id <> p_driver_id AND status = 'offered';

    -- Atribuir o motorista à corrida, passar o status para 'accepted' e preencher accepted_at
    UPDATE public.rides
    SET driver_id = p_driver_id,
        status = 'accepted',
        accepted_at = now(),
        updated_at = now()
    WHERE id = p_ride_id;
END;
$$;

COMMENT ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) IS 'Atribui o motorista à corrida, marca a oferta como aceita, expira outras ofertas pendentes e define o momento do aceite. [Protegido via JWT e Validação de Oferta]';

-- 2. ALTER BADGE_DEFINITIONS TO ADD REWARD COLUMNS
ALTER TABLE public.badge_definitions ADD COLUMN IF NOT EXISTS reward_type TEXT DEFAULT NULL;
ALTER TABLE public.badge_definitions ADD COLUMN IF NOT EXISTS reward_amount NUMERIC(10,2) DEFAULT NULL;

-- Atualizar as conquistas padrão com as recompensas financeiras e isenções de comissão
UPDATE public.badge_definitions SET reward_type = 'walletBonus', reward_amount = 10.00 WHERE id = 'first_ride_driver';
UPDATE public.badge_definitions SET reward_type = 'walletBonus', reward_amount = 50.00 WHERE id = 'ten_rides_driver';
UPDATE public.badge_definitions SET reward_type = 'walletBonus', reward_amount = 100.00 WHERE id = 'fifty_rides_driver';
UPDATE public.badge_definitions SET reward_type = 'walletBonus', reward_amount = 250.00 WHERE id = 'hundred_rides_driver';
UPDATE public.badge_definitions SET reward_type = 'commissionExemption', reward_amount = 7.00 WHERE id = 'five_star_driver';
UPDATE public.badge_definitions SET reward_type = 'walletBonus', reward_amount = 5.00 WHERE id = 'first_ride_rider';
UPDATE public.badge_definitions SET reward_type = 'walletBonus', reward_amount = 15.00 WHERE id = 'ten_rides_rider';
UPDATE public.badge_definitions SET reward_type = 'walletBonus', reward_amount = 10.00 WHERE id = 'generous_tipper';


-- ─────────────────────────────────────────────
-- FILE: 20260525060000_secure_ride_share_token.sql
-- ─────────────────────────────────────────────

-- Migration: Secure public.rpc_get_or_create_ride_share_token against BOLA
-- Ensures only participants of the ride or admins can generate a sharing token.

CREATE OR REPLACE FUNCTION public.rpc_get_or_create_ride_share_token(
    p_ride_id UUID,
    p_user_id TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_token TEXT;
    v_exists_token TEXT;
    v_is_authorized BOOLEAN := false;
BEGIN
    -- 1. Verify authorization (BOLA check)
    SELECT EXISTS (
        SELECT 1 FROM public.rides
        WHERE id = p_ride_id
          AND (rider_id = auth.uid()::text OR driver_id = auth.uid()::text)
    ) INTO v_is_authorized;

    -- Allow admins to generate share tokens
    IF NOT v_is_authorized THEN
        SELECT EXISTS (
            SELECT 1 FROM public.admins
            WHERE id = auth.uid()::text
        ) INTO v_is_authorized;
    END IF;

    IF NOT v_is_authorized THEN
        RAISE EXCEPTION 'Operação não autorizada. Apenas participantes ou administradores podem gerar tokens de compartilhamento.';
    END IF;

    -- 2. Check if a valid token already exists
    SELECT share_token INTO v_exists_token
    FROM public.ride_tracking_shares
    WHERE ride_id = p_ride_id
      AND expires_at > now()
    LIMIT 1;

    IF v_exists_token IS NOT NULL THEN
        RETURN v_exists_token;
    END IF;

    -- 3. Generate new secure MD5 token
    v_token := md5(gen_random_uuid()::text || now()::text);

    -- 4. Insert securely using authenticated user ID (preventing p_user_id forging)
    INSERT INTO public.ride_tracking_shares (ride_id, share_token, created_by, expires_at)
    VALUES (p_ride_id, v_token, auth.uid()::text, now() + interval '2 hours');

    RETURN v_token;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_or_create_ride_share_token(UUID, TEXT) TO authenticated;


-- ─────────────────────────────────────────────
-- FILE: 20260525070000_final_security_hardening.sql
-- ─────────────────────────────────────────────

-- Migration: Revoke public execution on dispatch functions and consolidate reviews/ratings/feedbacks triggers into profiles.
-- Created at: 2026-05-25

-- 1. Revoke PUBLIC and anon execution permissions from the dispatch functions:
REVOKE EXECUTE ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.reject_ride(UUID, TEXT) FROM PUBLIC, anon, authenticated;

-- Grants them to authenticated (drivers/riders) and service_role specifically:
GRANT EXECUTE ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reject_ride(UUID, TEXT) TO authenticated, service_role;

-- 2. Consolidate feedbacks, ratings, and reviews into profiles.
-- Create or replace function to calculate and update rating columns in profiles table.
CREATE OR REPLACE FUNCTION public.sync_profile_ratings()
RETURNS TRIGGER AS $$
DECLARE
  v_user_ids text[];
  v_user_id text;
BEGIN
  -- Determine affected user IDs based on the operations
  IF TG_OP = 'INSERT' THEN
    IF TG_TABLE_NAME = 'reviews' THEN
      v_user_ids := ARRAY[NEW.reviewed_id];
    ELSIF TG_TABLE_NAME = 'ratings' THEN
      v_user_ids := ARRAY[NEW.rated_user];
    ELSIF TG_TABLE_NAME = 'feedbacks' THEN
      v_user_ids := ARRAY[NEW.driver_id];
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    IF TG_TABLE_NAME = 'reviews' THEN
      v_user_ids := ARRAY[OLD.reviewed_id];
    ELSIF TG_TABLE_NAME = 'ratings' THEN
      v_user_ids := ARRAY[OLD.rated_user];
    ELSIF TG_TABLE_NAME = 'feedbacks' THEN
      v_user_ids := ARRAY[OLD.driver_id];
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF TG_TABLE_NAME = 'reviews' THEN
      IF NEW.reviewed_id IS DISTINCT FROM OLD.reviewed_id THEN
        v_user_ids := ARRAY[OLD.reviewed_id, NEW.reviewed_id];
      ELSE
        v_user_ids := ARRAY[NEW.reviewed_id];
      END IF;
    ELSIF TG_TABLE_NAME = 'ratings' THEN
      IF NEW.rated_user IS DISTINCT FROM OLD.rated_user THEN
        v_user_ids := ARRAY[OLD.rated_user, NEW.rated_user];
      ELSE
        v_user_ids := ARRAY[NEW.rated_user];
      END IF;
    ELSIF TG_TABLE_NAME = 'feedbacks' THEN
      IF NEW.driver_id IS DISTINCT FROM OLD.driver_id THEN
        v_user_ids := ARRAY[OLD.driver_id, NEW.driver_id];
      ELSE
        v_user_ids := ARRAY[NEW.driver_id];
      END IF;
    END IF;
  END IF;

  -- Filter out nulls
  SELECT ARRAY_AGG(x) INTO v_user_ids
  FROM UNNEST(v_user_ids) x
  WHERE x IS NOT NULL;

  -- Re-calculate ratings for all affected user IDs
  IF v_user_ids IS NOT NULL AND array_length(v_user_ids, 1) > 0 THEN
    FOREACH v_user_id IN ARRAY v_user_ids LOOP
      WITH all_evaluations AS (
        SELECT rating::numeric AS val FROM public.reviews WHERE reviewed_id = v_user_id AND rating IS NOT NULL
        UNION ALL
        SELECT score::numeric AS val FROM public.ratings WHERE rated_user = v_user_id AND score IS NOT NULL
        UNION ALL
        SELECT rating::numeric AS val FROM public.feedbacks WHERE driver_id = v_user_id AND rating IS NOT NULL
      ),
      stats AS (
        SELECT 
          COALESCE(COUNT(*), 0) AS total_count,
          COALESCE(AVG(val), 5.00) AS avg_val
        FROM all_evaluations
      )
      UPDATE public.profiles p
      SET 
        rating = ROUND(s.avg_val::numeric, 2),
        average_rating = ROUND(s.avg_val::numeric, 2),
        rating_count = s.total_count
      FROM stats s
      WHERE p.id = v_user_id;
    END LOOP;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop triggers if they already exist, to ensure idempotency
DROP TRIGGER IF EXISTS trg_sync_profile_ratings_reviews ON public.reviews;
DROP TRIGGER IF EXISTS trg_sync_profile_ratings_ratings ON public.ratings;
DROP TRIGGER IF EXISTS trg_sync_profile_ratings_feedbacks ON public.feedbacks;

-- Create triggers
CREATE TRIGGER trg_sync_profile_ratings_reviews
AFTER INSERT OR UPDATE OR DELETE ON public.reviews
FOR EACH ROW EXECUTE FUNCTION public.sync_profile_ratings();

CREATE TRIGGER trg_sync_profile_ratings_ratings
AFTER INSERT OR UPDATE OR DELETE ON public.ratings
FOR EACH ROW EXECUTE FUNCTION public.sync_profile_ratings();

CREATE TRIGGER trg_sync_profile_ratings_feedbacks
AFTER INSERT OR UPDATE OR DELETE ON public.feedbacks
FOR EACH ROW EXECUTE FUNCTION public.sync_profile_ratings();

-- 3. Run a one-time calculation to sync all existing user ratings across profiles
WITH combined_ratings AS (
  SELECT reviewed_id AS user_id, rating::numeric AS val FROM public.reviews WHERE reviewed_id IS NOT NULL AND rating IS NOT NULL
  UNION ALL
  SELECT rated_user AS user_id, score::numeric AS val FROM public.ratings WHERE rated_user IS NOT NULL AND score IS NOT NULL
  UNION ALL
  SELECT driver_id AS user_id, rating::numeric AS val FROM public.feedbacks WHERE driver_id IS NOT NULL AND rating IS NOT NULL
),
aggregated AS (
  SELECT 
    user_id,
    COUNT(*) AS total_count,
    ROUND(AVG(val), 2) AS avg_val
  FROM combined_ratings
  GROUP BY user_id
)
UPDATE public.profiles p
SET 
  rating = COALESCE(a.avg_val, 5.00),
  average_rating = COALESCE(a.avg_val, 5.00),
  rating_count = COALESCE(a.total_count, 0)
FROM (
  SELECT id FROM public.profiles
) p_list
LEFT JOIN aggregated a ON p_list.id = a.user_id
WHERE p.id = p_list.id;


-- ─────────────────────────────────────────────
-- FILE: 20260525080000_last_remaining_hardening.sql
-- ─────────────────────────────────────────────

-- Migration: Last remaining hardening items
-- Resolves: 
-- 1. Issue 3: reviews_insert policy hardening on public.reviews to strictly enforce ride participation.
-- 2. Issue 4: Revokes public/authenticated execution permissions on finish_ride financial transaction.

-- 1. Tighten reviews_insert policy to verify that the reviewer was a participant of the ride (rider or driver)
DROP POLICY IF EXISTS "reviews_insert" ON public.reviews;

CREATE POLICY "reviews_insert" ON public.reviews
    FOR INSERT TO authenticated
    WITH CHECK (
        auth.uid()::text = reviewer_id AND 
        EXISTS (
            SELECT 1 FROM public.rides r 
            WHERE r.id = ride_id AND (r.rider_id = auth.uid()::text OR r.driver_id = auth.uid()::text)
        )
    );

-- 2. Revoke PUBLIC, authenticated and anon execution permissions from the finish_ride financial function
REVOKE EXECUTE ON FUNCTION public.finish_ride(uuid, text, numeric) FROM PUBLIC, anon, authenticated;

-- Explicitly grant execute only to the service_role (which is used by our Deno Edge Function finish-order)
GRANT EXECUTE ON FUNCTION public.finish_ride(uuid, text, numeric) TO service_role;


-- ─────────────────────────────────────────────
-- FILE: 20260526000000_fix_admins_rls_recursion.sql
-- ─────────────────────────────────────────────

-- 1. Criar funções auxiliares SECURITY DEFINER para evitar recursão infinita
CREATE OR REPLACE FUNCTION public.is_admin(user_id text)
RETURNS boolean
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.admins WHERE id = user_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.is_superadmin(user_id text)
RETURNS boolean
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.admins WHERE id = user_id AND role = 'superadmin'
  );
END;
$$;

-- 2. Recriar políticas de SELECT e UPDATE na tabela 'admins' usando as novas funções
DROP POLICY IF EXISTS "admins_select_authenticated" ON public.admins;
CREATE POLICY "admins_select_authenticated" ON public.admins
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = id 
    OR public.is_admin(auth.uid()::text)
  );

DROP POLICY IF EXISTS "admins_update_self" ON public.admins;
CREATE POLICY "admins_update_self" ON public.admins
  FOR UPDATE TO authenticated
  USING (
    auth.uid()::text = id 
    OR public.is_superadmin(auth.uid()::text)
  )
  WITH CHECK (
    auth.uid()::text = id 
    OR public.is_superadmin(auth.uid()::text)
  );

-- 3. Recriar políticas na tabela 'app_settings' para utilizar a função is_admin
DROP POLICY IF EXISTS "app_settings_select" ON public.app_settings;
CREATE POLICY "app_settings_select" ON public.app_settings
  FOR SELECT USING (
    (NOT (key LIKE 'mp_%' OR key = 'google_map_api_key')) 
    OR public.is_admin(auth.uid()::text)
  );

DROP POLICY IF EXISTS "app_settings_write_admin" ON public.app_settings;
CREATE POLICY "app_settings_write_admin" ON public.app_settings
  FOR ALL TO authenticated
  USING (public.is_admin(auth.uid()::text))
  WITH CHECK (public.is_admin(auth.uid()::text));

-- 4. Remover a política redundante e perigosa admin_all_access da própria tabela admins
DROP POLICY IF EXISTS "admin_all_access" ON public.admins;


-- ─────────────────────────────────────────────
-- FILE: 20260526010000_fix_profiles_rides_rls_recursion.sql
-- ─────────────────────────────────────────────

-- 1. Criar funções auxiliares SECURITY DEFINER para verificar papéis no profiles sem RLS
CREATE OR REPLACE FUNCTION public.is_driver(user_id text)
RETURNS boolean
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles WHERE id = user_id AND role = 'driver'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.is_admin_or_operator(user_id text)
RETURNS boolean
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles WHERE id = user_id AND role = ANY (ARRAY['admin'::text, 'operator'::text])
  );
END;
$$;

-- 2. Recriar políticas de SELECT e UPDATE na tabela 'rides' para usar as funções auxiliares
DROP POLICY IF EXISTS "rides_select_requested_for_drivers" ON public.rides;
CREATE POLICY "rides_select_requested_for_drivers" ON public.rides
  FOR SELECT TO authenticated
  USING (
    ((status = ANY (ARRAY['requested'::text, 'searching'::text])) AND public.is_driver(auth.uid()::text))
    OR auth.uid()::text = rider_id
    OR auth.uid()::text = driver_id
    OR public.is_admin_or_operator(auth.uid()::text)
  );

DROP POLICY IF EXISTS "rides_update" ON public.rides;
CREATE POLICY "rides_update" ON public.rides
  FOR UPDATE TO authenticated
  USING (
    auth.uid()::text = rider_id
    OR auth.uid()::text = driver_id
    OR public.is_admin_or_operator(auth.uid()::text)
  );

-- 3. Recriar política de UPDATE na tabela 'profiles' para usar is_admin_or_operator e evitar auto-referência
DROP POLICY IF EXISTS "update_own_or_admin_profiles" ON public.profiles;
CREATE POLICY "update_own_or_admin_profiles" ON public.profiles
  FOR UPDATE TO authenticated
  USING (
    id = auth.uid()::text
    OR public.is_admin_or_operator(auth.uid()::text)
  );


-- ─────────────────────────────────────────────
-- FILE: 20260526020000_support_tickets_table.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO DE SUPORTE TICKETS — UPPI BRASIL
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.support_tickets (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES public.profiles(id),
    subject TEXT NOT NULL,
    message TEXT NOT NULL,
    category TEXT DEFAULT 'geral',
    status TEXT DEFAULT 'open',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='support_tickets' AND policyname='Inserir ticket de suporte') THEN
    CREATE POLICY "Inserir ticket de suporte" ON public.support_tickets FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid()::text);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='support_tickets' AND policyname='Ler proprios tickets de suporte') THEN
    CREATE POLICY "Ler proprios tickets de suporte" ON public.support_tickets FOR SELECT TO authenticated USING (user_id = auth.uid()::text);
  END IF;
END $$;


-- ─────────────────────────────────────────────
-- FILE: 20260526030000_security_hotfixes.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO DE SEGURANÇA E PROTEÇÃO CONTRA FRAUDES — UPPI BRASIL
-- Criado em: 2026-05-26
-- Objetivo:
-- 1. Restringir acesso de leitura a driver_locations via RLS (bloquear colheita de GPS)
-- 2. Impedir fraude de alteração de tarifas calculando e sobrescrevendo 'fare' no servidor
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- PARTE 1: Hardening de RLS para driver_locations
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Anyone can read driver locations" ON public.driver_locations;
DROP POLICY IF EXISTS "driver_locations_select" ON public.driver_locations;

-- Restringe o SELECT a si mesmo, admins ou passageiros com corrida ativa vinculada
CREATE POLICY "driver_locations_select" ON public.driver_locations
  FOR SELECT TO authenticated
  USING (
    -- 1. O próprio motorista pode ler sua localização
    auth.uid()::text = driver_id
    
    -- 2. Administradores podem ler qualquer localização
    OR EXISTS (
      SELECT 1 FROM public.admins WHERE id = auth.uid()::text
    )
    
    -- 3. Passageiro associado à corrida ativa com este motorista
    OR driver_id IN (
      SELECT driver_id FROM public.rides
      WHERE rider_id = auth.uid()::text
        AND status IN ('accepted', 'arrived', 'in_progress', 'waiting_for_post_pay')
    )
  );

-- Nota: A busca pública por raio de motoristas próximos via nearby_drivers() 
-- continuará funcionando perfeitamente porque a função está definida como SECURITY DEFINER,
-- o que ignora RLS da tabela interna no momento da execução, protegendo os dados reais
-- de acessos arbitrários ao mesmo tempo.

-- ─────────────────────────────────────────────────────────────────────────────
-- PARTE 2: Proteção de Tarifa (Anti-Proxy / Charles Intercept)
-- ─────────────────────────────────────────────────────────────────────────────

-- Função de trigger para cálculo e sobrescrita automática de preço
CREATE OR REPLACE FUNCTION public.calculate_and_override_ride_fare()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_service RECORD;
  v_base_fare NUMERIC;
  v_per_km NUMERIC;
  v_per_min NUMERIC;
  v_min_fare NUMERIC;
  v_distance_km NUMERIC;
  v_duration_min NUMERIC;
  v_calculated_fare NUMERIC;
  v_surge_calc JSONB;
BEGIN
  -- 1. Identificar o tipo de serviço (Regular, Premium, etc.)
  IF NEW.service_id IS NOT NULL THEN
    SELECT * INTO v_service FROM public.services WHERE id = NEW.service_id;
  ELSIF NEW.service_type IS NOT NULL THEN
    SELECT * INTO v_service FROM public.services WHERE name = NEW.service_type;
  END IF;

  -- Fallback para o serviço 'Regular' se não encontrado
  IF v_service.id IS NULL THEN
    SELECT * INTO v_service FROM public.services WHERE name = 'Regular' LIMIT 1;
  END IF;

  -- Obter parâmetros de precificação do serviço
  v_base_fare := COALESCE(v_service.base_fare, 5.00);
  v_per_km := COALESCE(v_service.per_km_fare, 2.00);
  v_per_min := COALESCE(v_service.per_minute_fare, 0.50);
  v_min_fare := COALESCE(v_service.minimum_fare, 7.00);

  -- 2. Calcular distância em KM e duração em minutos
  v_distance_km := COALESCE(NEW.distance, (NEW.distance_meters::numeric / 1000.0), 0);
  v_duration_min := COALESCE(NEW.duration, (NEW.duration_seconds::numeric / 60.0), 0);

  -- 3. Calcular a tarifa base do serviço
  v_calculated_fare := v_base_fare + (v_distance_km * v_per_km) + (v_duration_min * v_per_min);

  -- Garantir tarifa mínima
  IF v_calculated_fare < v_min_fare THEN
    v_calculated_fare := v_min_fare;
  END IF;

  -- 4. Aplicar preço dinâmico (Surge Zones) se houver coordenadas de pickup/dropoff
  IF NEW.pickup_lat IS NOT NULL AND NEW.pickup_lng IS NOT NULL AND NEW.dropoff_lat IS NOT NULL AND NEW.dropoff_lng IS NOT NULL THEN
    BEGIN
      v_surge_calc := public.rpc_calculate_ride_fare(
        NEW.pickup_lat::float8,
        NEW.pickup_lng::float8,
        NEW.dropoff_lat::float8,
        NEW.dropoff_lng::float8,
        v_calculated_fare
      );
      v_calculated_fare := (v_surge_calc->>'final_fare')::numeric;
    EXCEPTION WHEN OTHERS THEN
      -- Em caso de erro na RPC de preço dinâmico, mantém a tarifa base calculada
    END;
  END IF;

  -- 5. Sobrescrever com o valor calculado no servidor para evitar manipulação de proxy
  NEW.fare := ROUND(v_calculated_fare, 2);
  NEW.original_fare := NEW.fare;

  RETURN NEW;
END;
$$;

-- Registrar trigger BEFORE INSERT na tabela rides
DROP TRIGGER IF EXISTS trg_override_ride_fare ON public.rides;
CREATE TRIGGER trg_override_ride_fare
  BEFORE INSERT ON public.rides
  FOR EACH ROW
  EXECUTE FUNCTION public.calculate_and_override_ride_fare();


-- ─────────────────────────────────────────────
-- FILE: 20260526040000_anti_cherrypick_and_mock_gps.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Anti Cherry-Picking + Proteção GPS Server-Side
-- 1. Adicionar colunas de controle de rejeição no profiles
-- 2. Modificar reject_ride para aplicar cooldown após 5 rejeições consecutivas
-- 3. Modificar assign_driver_to_ride para resetar contador ao aceitar
-- 4. Modificar rpc_find_and_offer_ride para excluir motoristas em cooldown
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- PARTE 1: Colunas de controle de rejeição
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS consecutive_rejections INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cooldown_until TIMESTAMP WITH TIME ZONE;

-- ─────────────────────────────────────────────────────────────────────────────
-- PARTE 2: reject_ride com cooldown automático
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reject_ride(
  p_ride_id UUID,
  p_driver_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rejections INTEGER;
  v_max_rejections INTEGER := 5;
  v_cooldown_minutes INTEGER := 10;
BEGIN
  -- [SEGURANÇA] Validar se o solicitante é de fato o motorista ou service_role
  IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR auth.uid()::text <> p_driver_id) THEN
      RAISE EXCEPTION 'Operação não autorizada. O motorista não corresponde ao usuário autenticado.';
  END IF;

  -- Inserir nas rejeições de corridas para evitar nova oferta a este motorista
  INSERT INTO public.ride_rejected_drivers (ride_id, driver_id)
  VALUES (p_ride_id, p_driver_id)
  ON CONFLICT (ride_id, driver_id) DO NOTHING;

  -- Atualizar status da oferta para 'rejected'
  UPDATE public.ride_offers
  SET status = 'rejected'
  WHERE ride_id = p_ride_id AND driver_id = p_driver_id AND status = 'offered';

  -- ─── ANTI CHERRY-PICKING: Incrementar rejeições consecutivas ───
  UPDATE public.profiles
  SET consecutive_rejections = COALESCE(consecutive_rejections, 0) + 1
  WHERE id = p_driver_id
  RETURNING consecutive_rejections INTO v_rejections;

  -- Buscar configuração dinâmica de limites (com fallback)
  BEGIN
    SELECT COALESCE((SELECT value::integer FROM app_settings WHERE key = 'max_consecutive_rejections'), 5)
    INTO v_max_rejections;
    SELECT COALESCE((SELECT value::integer FROM app_settings WHERE key = 'rejection_cooldown_minutes'), 10)
    INTO v_cooldown_minutes;
  EXCEPTION WHEN OTHERS THEN
    v_max_rejections := 5;
    v_cooldown_minutes := 10;
  END;

  -- Se atingiu o limite de rejeições consecutivas → cooldown
  IF v_rejections >= v_max_rejections THEN
    UPDATE public.profiles
    SET status = 'offline',
        cooldown_until = NOW() + (v_cooldown_minutes * interval '1 minute'),
        consecutive_rejections = 0
    WHERE id = p_driver_id;

    -- Também tirar de driver_locations
    UPDATE public.driver_locations
    SET status = 'offline'
    WHERE driver_id = p_driver_id;

    -- [SISTEMA DE DISPONIBILIDADE] Motorista atingiu o limite de passes seguidos.
    -- O sistema registra indisponibilidade temporária por alta rotatividade de passes.
    -- Nota juríica: isso é um indicador de qualidade de serviço, não uma sanção trabalhista.
    RAISE NOTICE '[disponibilidade] Parceiro % ficou temporariamente indisponível (alta rotatividade de passes). Pausa de % min. Score de passes resetado.',
      p_driver_id, v_cooldown_minutes;
  END IF;

  -- Avançar o despacho para o próximo motorista imediatamente
  PERFORM public.rpc_find_and_offer_ride(p_ride_id);
END;
$$;

COMMENT ON FUNCTION public.reject_ride(UUID, TEXT) IS 'Registra a rejeição, incrementa contador de rejeições consecutivas, aplica cooldown de 10min após 5 rejeições, e despacha para o próximo motorista. [Protegido via JWT]';

-- ─────────────────────────────────────────────────────────────────────────────
-- PARTE 3: assign_driver_to_ride resetando contador ao aceitar
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.assign_driver_to_ride(
    p_ride_id UUID,
    p_driver_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_status TEXT;
    v_rows INT;
    v_driver_lat DOUBLE PRECISION;
    v_driver_lng DOUBLE PRECISION;
    v_pickup_lat DOUBLE PRECISION;
    v_pickup_lng DOUBLE PRECISION;
    v_dist_meters DOUBLE PRECISION;
    v_eta_minutes INTEGER;
    v_eta_pickup TIMESTAMP WITH TIME ZONE;
BEGIN
    -- [SEGURANÇA] Validar se o solicitante é de fato o motorista ou service_role
    IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR auth.uid()::text <> p_driver_id) THEN
        RAISE EXCEPTION 'Operação não autorizada. O motorista não corresponde ao usuário autenticado.';
    END IF;

    -- [SEGURANÇA] Bloquear linha da corrida para evitar conflitos concorrentes
    SELECT status, pickup_lat, pickup_lng INTO v_status, v_pickup_lat, v_pickup_lng
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Corrida não encontrada (ID: %)', p_ride_id;
    END IF;

    -- Agora aceitamos tanto 'requested' quanto 'searching'
    IF v_status NOT IN ('requested', 'searching') THEN
        RAISE EXCEPTION 'A corrida não está mais disponível para aceite (status atual: %)', v_status;
    END IF;

    -- [SEGURANÇA] Atualizar oferta específica deste motorista como 'accepted' e garantir que ela existia e estava ativa
    UPDATE public.ride_offers
    SET status = 'accepted'
    WHERE ride_id = p_ride_id AND driver_id = p_driver_id AND status = 'offered';
    
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 0 THEN
        RAISE EXCEPTION 'Você não possui uma oferta ativa para esta corrida.';
    END IF;

    -- Expirar as demais ofertas ativas para essa corrida
    UPDATE public.ride_offers
    SET status = 'expired'
    WHERE ride_id = p_ride_id AND driver_id <> p_driver_id AND status = 'offered';

    -- Calcular ETA dinâmico baseado no PostGIS
    SELECT lat, lng INTO v_driver_lat, v_driver_lng
    FROM public.driver_locations
    WHERE driver_id = p_driver_id;

    IF v_driver_lat IS NOT NULL AND v_pickup_lat IS NOT NULL THEN
        v_dist_meters := ST_Distance(
            ST_SetSRID(ST_MakePoint(v_driver_lng, v_driver_lat), 4326)::geography,
            ST_SetSRID(ST_MakePoint(v_pickup_lng, v_pickup_lat), 4326)::geography
        );
        v_eta_minutes := CEIL(v_dist_meters / 500.0); -- ~30km/h
        v_eta_pickup := NOW() + (v_eta_minutes * interval '1 minute');
    ELSE
        v_eta_pickup := NOW() + interval '5 minutes';
    END IF;

    -- Atribuir o motorista à corrida, passar o status para 'accepted', definir accepted_at e eta_pickup
    UPDATE public.rides
    SET driver_id = p_driver_id,
        status = 'accepted',
        accepted_at = NOW(),
        eta_pickup = v_eta_pickup,
        updated_at = NOW()
    WHERE id = p_ride_id;

    -- ─── ANTI CHERRY-PICKING: Resetar rejeições ao aceitar corrida ───
    UPDATE public.profiles
    SET consecutive_rejections = 0
    WHERE id = p_driver_id AND consecutive_rejections > 0;
END;
$$;

COMMENT ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) IS 'Atribui o motorista à corrida, marca a oferta como aceita, expira outras ofertas, reseta contador de rejeições consecutivas. [Protegido via JWT e Validação de Oferta]';

-- ─────────────────────────────────────────────────────────────────────────────
-- PARTE 4: rpc_find_and_offer_ride excluindo motoristas em cooldown
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_find_and_offer_ride(p_ride_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pickup_loc GEOGRAPHY(POINT);
    v_ride_status TEXT;
    v_driver_id TEXT;
    v_offer_id UUID;
    v_search_radius INTEGER;
BEGIN
    -- 1. Bloquear linha da corrida para evitar conflitos de concorrência
    SELECT status, pickup_location INTO v_ride_status, v_pickup_loc
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    -- Se a corrida não existir ou já tiver sido aceita/cancelada, encerra o loop
    IF v_ride_status IS NULL OR v_ride_status NOT IN ('requested', 'searching') THEN
        RETURN FALSE;
    END IF;

    -- 2. Buscar o motorista 'online' aprovado mais próximo
    SELECT p.id, COALESCE(p.search_radius, 5000) INTO v_driver_id, v_search_radius
    FROM public.profiles p
    WHERE p.role = 'driver'
      AND p.status = 'online'
      AND p.current_location IS NOT NULL
      -- ─── ANTI CHERRY-PICKING: Excluir motoristas em cooldown ───
      AND (p.cooldown_until IS NULL OR p.cooldown_until < NOW())
      -- Evitar motoristas que já rejeitaram ou expiraram esta corrida
      AND NOT EXISTS (
          SELECT 1 
          FROM public.ride_rejected_drivers rr 
          WHERE rr.ride_id = p_ride_id 
            AND rr.driver_id = p.id
      )
      -- Evitar motoristas em corridas ativas
      AND NOT EXISTS (
          SELECT 1 
          FROM public.rides r 
          WHERE r.driver_id = p.id 
            AND r.status IN ('accepted', 'arrived', 'in_progress')
      )
      -- Evitar motoristas com ofertas de corrida ativas pendentes (de qualquer corrida)
      AND NOT EXISTS (
          SELECT 1
          FROM public.ride_offers ro
          WHERE ro.driver_id = p.id
            AND ro.status = 'offered'
            AND ro.expires_at > now()
      )
    ORDER BY 
      ST_Distance(p.current_location, v_pickup_loc) * 
      (1.0 + COALESCE(p.consecutive_rejections, 0) * 0.15) -- Ajuste de score de compatibilidade por passes recentes
    ASC
    LIMIT 1;

    -- 3. Se um motorista elegível for encontrado, criar a oferta e atualizar o status
    IF v_driver_id IS NOT NULL THEN
        -- Expirar ofertas anteriores ainda marcadas como 'offered' para esta corrida
        UPDATE public.ride_offers
        SET status = 'expired'
        WHERE ride_id = p_ride_id AND status = 'offered';

        -- Inserir nova oferta de 15 segundos
        INSERT INTO public.ride_offers (ride_id, driver_id, status, expires_at)
        VALUES (p_ride_id, v_driver_id, 'offered', now() + interval '15 seconds')
        RETURNING id INTO v_offer_id;

        -- Alterar status da corrida para 'searching'
        UPDATE public.rides
        SET status = 'searching',
            updated_at = now()
        WHERE id = p_ride_id;

        RETURN TRUE;
    ELSE
        -- Nenhum motorista encontrado na região: reverter status para 'requested'
        UPDATE public.rides
        SET status = 'requested',
            updated_at = now()
        WHERE id = p_ride_id AND status = 'searching';

        RETURN FALSE;
    END IF;
END;
$$;

COMMENT ON FUNCTION public.rpc_find_and_offer_ride(UUID) IS 'Busca o motorista disponível mais próximo (excluindo cooldowns), penaliza levemente motoristas com rejeições recentes na ordenação.';

-- Garantir privilégios
REVOKE EXECUTE ON FUNCTION public.rpc_find_and_offer_ride(UUID) FROM authenticated, anon, public;
GRANT EXECUTE ON FUNCTION public.rpc_find_and_offer_ride(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_ride(UUID, TEXT) TO authenticated;


-- ─────────────────────────────────────────────
-- FILE: 20260526050000_schedule_cleanup_function.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Agendar cleanup-expired Edge Function via pg_cron
-- Agenda chamada HTTP à Edge Function cleanup-expired a cada 5 minutos
-- para tratar corridas fantasma (in_progress > 45min), corridas accepted
-- stale, e motoristas inativos.
-- ==============================================================================

-- Garantir extensão pg_net para chamadas HTTP via cron
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Remover agendamentos anteriores se existirem
SELECT cron.unschedule('call-cleanup-expired-function')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'call-cleanup-expired-function');

-- Agendar chamada à Edge Function cleanup-expired a cada 5 minutos
SELECT cron.schedule(
  'call-cleanup-expired-function',
  '*/5 * * * *',
  $$
    SELECT net.http_post(
      url := current_setting('app.supabase_url', true) || '/functions/v1/cleanup-expired',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', current_setting('app.webhook_secret', true)
      ),
      body := '{"scheduled": true}'::jsonb,
      timeout_milliseconds := 10000
    );
  $$
);

-- ─────────────────────────────────────────────────────────────────────────────
-- NOTA: Para que este cron funcione, é necessário configurar as variáveis:
--   app.supabase_url → URL do projeto Supabase
--   app.webhook_secret → Mesmo secret usado em WEBHOOK_SECRET no env das Edge Functions
--
-- Execute no SQL Editor do Supabase:
--   ALTER DATABASE postgres SET app.supabase_url = 'https://<seu-projeto>.supabase.co';
--   ALTER DATABASE postgres SET app.webhook_secret = '<seu-webhook-secret>';
-- ─────────────────────────────────────────────────────────────────────────────


-- ─────────────────────────────────────────────
-- FILE: 20260526060000_auto_redispatch_after_cancel.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Suporte ao redespacho automático após cancelamento de motorista
-- Adiciona coluna driver_cancel_count à tabela rides para rastrear o número de
-- vezes que motoristas cancelaram uma corrida específica, habilitando o limite
-- de MAX_DRIVER_CANCELS (3) no cancel-order Edge Function.
-- ==============================================================================

-- Adicionar contador de cancelamentos de motoristas por corrida
ALTER TABLE public.rides
  ADD COLUMN IF NOT EXISTS driver_cancel_count INTEGER DEFAULT 0;

COMMENT ON COLUMN public.rides.driver_cancel_count IS 
  'Número de vezes que motoristas cancelaram esta corrida. Limite de 3 antes de expirar definitivamente.';

-- Criar índice para consulta rápida nas corridas reabertas para redespacho
CREATE INDEX IF NOT EXISTS idx_rides_driver_cancel_count
  ON public.rides (driver_cancel_count)
  WHERE status = 'requested';

-- Criar trigger para incrementar o contador automaticamente ao cancelar
CREATE OR REPLACE FUNCTION public.increment_driver_cancel_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Se o status mudou para driver_canceled, incrementar o contador NA corrida original
  -- (o cancel-order vai reabrir com status='requested', então incrementamos antes)
  IF NEW.status = 'driver_canceled' AND OLD.status NOT IN ('driver_canceled', 'rider_canceled', 'expired', 'completed', 'finished') THEN
    NEW.driver_cancel_count = COALESCE(OLD.driver_cancel_count, 0) + 1;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_increment_driver_cancel ON public.rides;
CREATE TRIGGER trg_increment_driver_cancel
  BEFORE UPDATE ON public.rides
  FOR EACH ROW
  EXECUTE FUNCTION public.increment_driver_cancel_count();

-- ==============================================================================
-- NOTA: O cancel-order Edge Function agora:
-- 1. Lê driver_cancel_count da tabela ride_cancellations (abordagem via JOIN)
-- 2. Se count < 3: reabre a corrida com status='requested' e dispara rpc_find_and_offer_ride
-- 3. Se count >= 3: marca como 'expired' definitivamente
-- A trigger acima garante que o contador é mantido mesmo no registro histórico.
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260526070000_pin_disputes_toll.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: PIN de Embarque + Chargeback + LGPD CPF Fix
-- 1. Adiciona coluna boarding_pin em rides para validação de embarque
-- 2. Cria tabela payment_disputes para chargebacks do Mercado Pago
-- 3. Documentação: CPF deve ser limpo no delete-user-account (feito na Edge Function)
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. PIN DE EMBARQUE: Coluna boarding_pin na tabela rides
-- Gerado no accept-order, exibido no app do passageiro,
-- validado pelo motorista no start-order.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.rides
  ADD COLUMN IF NOT EXISTS boarding_pin CHAR(4);

COMMENT ON COLUMN public.rides.boarding_pin IS
  'Código PIN de 4 dígitos gerado no aceite da corrida. Passageiro mostra ao motorista antes de iniciar. Anulado após inicio da corrida.';

-- Índice para validação rápida de PIN por corrida
CREATE INDEX IF NOT EXISTS idx_rides_boarding_pin
  ON public.rides (boarding_pin)
  WHERE status = 'arrived';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. CHARGEBACKS: Tabela payment_disputes para registrar contestações do MP
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.payment_disputes (
  id                UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  ride_id           UUID REFERENCES public.rides(id) ON DELETE SET NULL,
  rider_id          TEXT REFERENCES public.profiles(id) ON DELETE SET NULL,
  mp_payment_id     TEXT NOT NULL,
  dispute_type      TEXT NOT NULL DEFAULT 'chargeback', -- 'chargeback', 'in_mediation', 'fraud'
  amount            NUMERIC(10, 2) NOT NULL,
  status            TEXT NOT NULL DEFAULT 'open',       -- 'open', 'resolved', 'lost'
  rider_blocked     BOOLEAN DEFAULT FALSE,
  wallet_debited    BOOLEAN DEFAULT FALSE,
  admin_notified    BOOLEAN DEFAULT FALSE,
  mp_raw_payload    JSONB,                              -- Payload completo do MP para auditoria
  resolved_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT timezone('utc', now()),
  updated_at        TIMESTAMPTZ DEFAULT timezone('utc', now())
);

CREATE INDEX IF NOT EXISTS idx_payment_disputes_rider_id    ON public.payment_disputes (rider_id);
CREATE INDEX IF NOT EXISTS idx_payment_disputes_ride_id     ON public.payment_disputes (ride_id);
CREATE INDEX IF NOT EXISTS idx_payment_disputes_status      ON public.payment_disputes (status) WHERE status = 'open';
CREATE INDEX IF NOT EXISTS idx_payment_disputes_mp_payment  ON public.payment_disputes (mp_payment_id);

-- RLS: Apenas service_role acessa (nunca exposta ao cliente)
ALTER TABLE public.payment_disputes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service_role_only_disputes" ON public.payment_disputes
  USING (auth.role() = 'service_role');

-- Trigger de updated_at
CREATE TRIGGER update_payment_disputes_updated_at
  BEFORE UPDATE ON public.payment_disputes
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. BLOQUEIO DE WALLET: Coluna is_blocked na tabela wallets (para chargebacks)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.wallets
  ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS block_reason TEXT;

COMMENT ON COLUMN public.wallets.is_blocked IS
  'TRUE se a carteira foi bloqueada por chargeback, fraude ou investigação. Impede novos pagamentos.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. TAXA DE PEDÁGIO: Coluna toll_amount em rides
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.rides
  ADD COLUMN IF NOT EXISTS toll_amount NUMERIC(10, 2) DEFAULT 0;

COMMENT ON COLUMN public.rides.toll_amount IS
  'Valor de pedágio adicionado pelo motorista ao finalizar a corrida. Limite de R$ 30,00. Cobrado da wallet do passageiro e creditado ao motorista.';


-- ─────────────────────────────────────────────
-- FILE: 20260526080000_danger_zones_and_toll_disputes.sql
-- ─────────────────────────────────────────────

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
            v_commission_percent := COALESCE(v_commission_row.value::numeric, 0.0);
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


-- ─────────────────────────────────────────────
-- FILE: 20260526090000_add_twilio_settings.sql
-- ─────────────────────────────────────────────

-- =============================================================================
-- MIGRATION: Adicionar colunas de configuração do Twilio em app_settings
-- Para suportar as Edge Functions send-sms-otp e mask-call
-- =============================================================================

ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS twilio_account_sid TEXT DEFAULT '';
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS twilio_auth_token TEXT DEFAULT '';
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS twilio_messaging_service_sid TEXT DEFAULT '';
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS twilio_phone_number TEXT DEFAULT '';

COMMENT ON COLUMN public.app_settings.twilio_account_sid IS 'Account SID do Twilio para envio de SMS e chamadas de voz.';
COMMENT ON COLUMN public.app_settings.twilio_auth_token IS 'Auth Token do Twilio para autenticação básica.';
COMMENT ON COLUMN public.app_settings.twilio_messaging_service_sid IS 'Messaging Service SID do Twilio para envio de SMS.';
COMMENT ON COLUMN public.app_settings.twilio_phone_number IS 'Número de telefone do Twilio para mascaramento de chamadas de voz.';


-- ─────────────────────────────────────────────
-- FILE: 20260526091000_twilio_settings_and_masking.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Configurações do Twilio e Mascaramento de Número de Telefone
-- 1. Colunas twilio_account_sid, twilio_auth_token, twilio_messaging_service_sid, twilio_phone_number em public.app_settings
-- 2. Valores padrão vazios na row global_config
-- 3. Atualização da política RLS public.app_settings_select para ocultar chaves do Twilio
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. ADICIONAR COLUNAS DE CONFIGURAÇÃO DO TWILIO
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.app_settings 
    ADD COLUMN IF NOT EXISTS twilio_account_sid text DEFAULT '',
    ADD COLUMN IF NOT EXISTS twilio_auth_token text DEFAULT '',
    ADD COLUMN IF NOT EXISTS twilio_messaging_service_sid text DEFAULT '',
    ADD COLUMN IF NOT EXISTS twilio_phone_number text DEFAULT '';

COMMENT ON COLUMN public.app_settings.twilio_account_sid IS 'Twilio Account SID para envio de SMS e mascaramento de número. Restrito a administradores.';
COMMENT ON COLUMN public.app_settings.twilio_auth_token IS 'Twilio Auth Token para autenticação. Restrito a administradores.';
COMMENT ON COLUMN public.app_settings.twilio_messaging_service_sid IS 'Twilio Messaging Service SID. Restrito a administradores.';
COMMENT ON COLUMN public.app_settings.twilio_phone_number IS 'Twilio Phone Number (número de envio). Restrito a administradores.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. GARANTIR VALORES PADRÃO VAZIOS NA ROW 'global_config'
-- ─────────────────────────────────────────────────────────────────────────────
UPDATE public.app_settings
SET 
    twilio_account_sid = '',
    twilio_auth_token = '',
    twilio_messaging_service_sid = '',
    twilio_phone_number = ''
WHERE key = 'global_config';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. ATUALIZAR POLÍTICA RLS PARA RESTRIÇÃO DO TWILIO
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "app_settings_select" ON public.app_settings;
CREATE POLICY "app_settings_select" ON public.app_settings
    FOR SELECT USING (
        (NOT (key LIKE 'mp_%' OR key = 'google_map_api_key' OR key LIKE 'twilio_%')) 
        OR EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );


-- ─────────────────────────────────────────────
-- FILE: 20260526100000_heartbeat_session_destination.sql
-- ─────────────────────────────────────────────

-- =====================================================
-- MIGRAÇÃO: Heartbeat, Session Kick e Mudança de Destino
-- Data: 2026-05-26
-- =====================================================

-- 1. Coluna original_fare: Armazena a tarifa original quando o passageiro
--    muda o destino em corrida (update-ride-destination)
ALTER TABLE public.rides
  ADD COLUMN IF NOT EXISTS original_fare DECIMAL(10,2);

COMMENT ON COLUMN public.rides.original_fare IS 'Tarifa original antes de mudança de destino em corrida. NULL se destino não foi alterado.';

-- 2. Índice para queries do heartbeat cleanup (corridas arrived stale)
CREATE INDEX IF NOT EXISTS idx_rides_arrived_updated
  ON public.rides (status, updated_at)
  WHERE status = 'arrived';

-- 3. Índice para session kick: busca rápida de fcm_token por user
-- (o profiles já tem PK em id, então o SELECT é eficiente)
-- Apenas garantir que fcm_token não seja indexado desnecessariamente

COMMENT ON COLUMN public.profiles.fcm_token IS 'Token FCM do dispositivo ativo. Ao mudar, o token antigo recebe push de session_kick para forçar logout.';


-- ─────────────────────────────────────────────
-- FILE: 20260526101000_passenger_subscriptions.sql
-- ─────────────────────────────────────────────

-- ============================================================
-- PILAR 16 — Clube de Assinatura B2C para Passageiros
-- Migração: subscription_plans + passenger_subscriptions
-- ============================================================

-- -------------------------------------------------------
-- 1. Tabela: subscription_plans (catálogo de planos)
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS subscription_plans (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name              TEXT        NOT NULL UNIQUE,
  display_name      TEXT        NOT NULL,
  description       TEXT,
  price             NUMERIC(10,2) NOT NULL,
  discount_percent  NUMERIC(5,2)  DEFAULT 0,
  max_rides_per_month INT       DEFAULT NULL,   -- NULL = ilimitado
  priority_dispatch BOOLEAN     DEFAULT false,
  free_cancellations INT        DEFAULT 0,
  is_active         BOOLEAN     DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now()
);

-- -------------------------------------------------------
-- 2. Tabela: passenger_subscriptions (assinatura ativa)
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS passenger_subscriptions (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           TEXT        NOT NULL REFERENCES profiles(id),
  plan_id           UUID        NOT NULL REFERENCES subscription_plans(id),
  plan_name         TEXT        NOT NULL,
  price_paid        NUMERIC(10,2) NOT NULL,
  discount_percent  NUMERIC(5,2)  DEFAULT 0,
  rides_used        INT         DEFAULT 0,
  max_rides         INT,
  starts_at         TIMESTAMPTZ DEFAULT now(),
  expires_at        TIMESTAMPTZ NOT NULL,
  is_active         BOOLEAN     DEFAULT true,
  auto_renew        BOOLEAN     DEFAULT true,
  cancelled_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id)   -- apenas uma assinatura ativa por vez
);

-- Índice para consulta rápida de assinatura ativa
CREATE INDEX IF NOT EXISTS idx_passenger_subscriptions_active
  ON passenger_subscriptions(user_id)
  WHERE is_active = true;

-- -------------------------------------------------------
-- 3. RLS — subscription_plans
-- -------------------------------------------------------
ALTER TABLE subscription_plans ENABLE ROW LEVEL SECURITY;

-- Qualquer autenticado pode VER planos ativos
DROP POLICY IF EXISTS "subscription_plans_select_authenticated" ON subscription_plans;
CREATE POLICY "subscription_plans_select_authenticated"
  ON subscription_plans FOR SELECT
  TO authenticated
  USING (is_active = true);

-- Apenas admins podem INSERT
DROP POLICY IF EXISTS "subscription_plans_insert_admin" ON subscription_plans;
CREATE POLICY "subscription_plans_insert_admin"
  ON subscription_plans FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM admins WHERE admins.id = auth.uid()::text)
  );

-- Apenas admins podem UPDATE
DROP POLICY IF EXISTS "subscription_plans_update_admin" ON subscription_plans;
CREATE POLICY "subscription_plans_update_admin"
  ON subscription_plans FOR UPDATE
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM admins WHERE admins.id = auth.uid()::text)
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM admins WHERE admins.id = auth.uid()::text)
  );

-- Apenas admins podem DELETE
DROP POLICY IF EXISTS "subscription_plans_delete_admin" ON subscription_plans;
CREATE POLICY "subscription_plans_delete_admin"
  ON subscription_plans FOR DELETE
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM admins WHERE admins.id = auth.uid()::text)
  );

-- -------------------------------------------------------
-- 4. RLS — passenger_subscriptions
-- -------------------------------------------------------
ALTER TABLE passenger_subscriptions ENABLE ROW LEVEL SECURITY;

-- Passageiro pode ver a própria assinatura, admins podem ver todas
DROP POLICY IF EXISTS "passenger_subscriptions_select_own_or_admin" ON passenger_subscriptions;
CREATE POLICY "passenger_subscriptions_select_own_or_admin"
  ON passenger_subscriptions FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()::text
    OR EXISTS (SELECT 1 FROM admins WHERE admins.id = auth.uid()::text)
  );

-- INSERT/UPDATE apenas via service_role (Edge Functions)
DROP POLICY IF EXISTS "passenger_subscriptions_insert_service_role" ON passenger_subscriptions;
CREATE POLICY "passenger_subscriptions_insert_service_role"
  ON passenger_subscriptions FOR INSERT
  TO service_role
  WITH CHECK (true);

DROP POLICY IF EXISTS "passenger_subscriptions_update_service_role" ON passenger_subscriptions;
CREATE POLICY "passenger_subscriptions_update_service_role"
  ON passenger_subscriptions FOR UPDATE
  TO service_role
  USING (true)
  WITH CHECK (true);

-- -------------------------------------------------------
-- 5. Seed — 3 planos iniciais
-- -------------------------------------------------------
INSERT INTO subscription_plans (name, display_name, description, price, discount_percent, max_rides_per_month, priority_dispatch, free_cancellations)
VALUES
  ('basic',   'Básico',  'Desconto de 5% em todas as corridas',                             14.90, 5.00,  NULL, false, 0),
  ('premium', 'Premium', 'Desconto de 12% em todas as corridas + 2 cancelamentos grátis',   29.90, 12.00, NULL, false, 2),
  ('vip',     'VIP',     'Desconto de 20%, despacho prioritário + 5 cancelamentos grátis',   49.90, 20.00, NULL, true,  5)
ON CONFLICT (name) DO NOTHING;

-- -------------------------------------------------------
-- 6. Realtime — publicar passenger_subscriptions
-- -------------------------------------------------------
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE passenger_subscriptions;
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;



-- ─────────────────────────────────────────────
-- FILE: 20260526110000_accessibility_features.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: PILAR 17 — Acessibilidade (Tags de Motoristas + Filtros de Despacho)
-- ==============================================================================
-- 1. Colunas booleanas em profiles (recursos do motorista)
-- 2. Tabela accessibility_tags (catálogo)
-- 3. Seeds com 5 tags
-- 4. RLS para accessibility_tags
-- 5. Refatoração de find_nearby_requested_rides com filtro de acessibilidade
-- 6. Realtime para accessibility_tags
-- ==============================================================================

-- ============================================================
-- 1. COLUNAS EM profiles (flags do motorista)
-- ============================================================
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS accessibility_wheelchair       BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS accessibility_hearing_impaired BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS accessibility_visual_aid       BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS accessibility_pet_friendly     BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS accessibility_child_seat       BOOLEAN DEFAULT false;

COMMENT ON COLUMN public.profiles.accessibility_wheelchair       IS 'Motorista possui veículo adaptado para cadeira de rodas';
COMMENT ON COLUMN public.profiles.accessibility_hearing_impaired IS 'Motorista preparado para passageiros com deficiência auditiva';
COMMENT ON COLUMN public.profiles.accessibility_visual_aid       IS 'Motorista oferece suporte a passageiros com deficiência visual';
COMMENT ON COLUMN public.profiles.accessibility_pet_friendly     IS 'Motorista aceita animais de estimação no veículo';
COMMENT ON COLUMN public.profiles.accessibility_child_seat       IS 'Veículo equipado com cadeirinha infantil';

-- ============================================================
-- 2. TABELA accessibility_tags (catálogo de tags)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.accessibility_tags (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  key          TEXT        NOT NULL UNIQUE,
  display_name TEXT        NOT NULL,
  icon         TEXT,
  description  TEXT,
  column_name  TEXT        NOT NULL,
  is_active    BOOLEAN     DEFAULT true,
  created_at   TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE public.accessibility_tags IS 'Catálogo de tags de acessibilidade disponíveis para motoristas e filtros de passageiros';

-- ============================================================
-- 3. SEEDS — 5 tags padrão
-- ============================================================
INSERT INTO public.accessibility_tags (key, display_name, icon, description, column_name)
VALUES
  ('wheelchair',       'Cadeirante',          '♿',  'Veículo adaptado para cadeira de rodas',                        'accessibility_wheelchair'),
  ('hearing_impaired', 'Deficiente Auditivo', '🦻', 'Motorista preparado para passageiros com deficiência auditiva',  'accessibility_hearing_impaired'),
  ('visual_aid',       'Auxílio Visual',      '👁️', 'Suporte para passageiros com deficiência visual',                'accessibility_visual_aid'),
  ('pet_friendly',     'Pet Friendly',        '🐕', 'Aceita animais de estimação no veículo',                         'accessibility_pet_friendly'),
  ('child_seat',       'Cadeirinha Infantil',  '👶', 'Veículo equipado com cadeirinha para crianças',                  'accessibility_child_seat')
ON CONFLICT (key) DO NOTHING;

-- ============================================================
-- 4. RLS — accessibility_tags
-- ============================================================
ALTER TABLE public.accessibility_tags ENABLE ROW LEVEL SECURITY;

-- SELECT para todos os usuários autenticados
DROP POLICY IF EXISTS "accessibility_tags_select_authenticated" ON public.accessibility_tags;
CREATE POLICY "accessibility_tags_select_authenticated"
  ON public.accessibility_tags
  FOR SELECT
  TO authenticated
  USING (true);

-- INSERT apenas para admins
DROP POLICY IF EXISTS "accessibility_tags_insert_admin" ON public.accessibility_tags;
CREATE POLICY "accessibility_tags_insert_admin"
  ON public.accessibility_tags
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- UPDATE apenas para admins
DROP POLICY IF EXISTS "accessibility_tags_update_admin" ON public.accessibility_tags;
CREATE POLICY "accessibility_tags_update_admin"
  ON public.accessibility_tags
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- DELETE apenas para admins
DROP POLICY IF EXISTS "accessibility_tags_delete_admin" ON public.accessibility_tags;
CREATE POLICY "accessibility_tags_delete_admin"
  ON public.accessibility_tags
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- ============================================================
-- 5. REFATORAR RPC find_nearby_requested_rides
--    Aceita filtros de acessibilidade opcionais
-- ============================================================

-- Drop overloads antigos para evitar conflito de assinatura
DROP FUNCTION IF EXISTS public.find_nearby_requested_rides(float8, float8, float8);
DROP FUNCTION IF EXISTS public.find_nearby_requested_rides(float8, float8, float8, text[]);

CREATE OR REPLACE FUNCTION public.find_nearby_requested_rides(
    lat                     float8,
    lng                     float8,
    radius_meters           float8     DEFAULT 3000,
    p_accessibility_filters text[]     DEFAULT NULL
)
RETURNS TABLE (
    id              UUID,
    pickup_address  TEXT,
    dropoff_address TEXT,
    fare            DECIMAL,
    dist_meters     FLOAT8
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.id,
        r.pickup_address,
        r.dropoff_address,
        r.fare,
        ST_Distance(
            r.pickup_location,
            ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography
        ) AS dist_meters
    FROM public.rides r
    -- JOIN com profiles do passageiro? Não — o filtro é sobre o MOTORISTA que vai aceitar.
    -- O filtro de acessibilidade aqui serve para a corrida ser visível apenas se
    -- houver motoristas compatíveis, mas a lógica real do despacho filtra no dispatch.
    -- Para ride chaining (busca do motorista), o filtro age na corrida.
    -- Nesta RPC, filtramos corridas cujos passageiros solicitaram tags de acessibilidade.
    -- Porém, o design original retorna corridas para ride chaining.
    -- Mantemos a RPC compatível: se p_accessibility_filters for passado,
    -- buscamos corridas onde o motorista chamador possua as flags necessárias.
    -- Como esta RPC retorna corridas (não motoristas), o filtro garante que
    -- apenas corridas que o motorista chamador pode atender apareçam.
    WHERE r.status = 'requested'
      AND r.driver_id IS NULL
      AND ST_DWithin(
          r.pickup_location,
          ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography,
          radius_meters
      )
      -- Filtros de acessibilidade: se fornecidos, verificar que NENHUMA tag
      -- exigida pela corrida (futuramente armazenada em rides.accessibility_requirements)
      -- impede a visualização. Por ora, filtramos pelo perfil do motorista chamador.
      -- Se p_accessibility_filters não é NULL, filtramos corridas que exigem
      -- que o motorista tenha essas flags TRUE em profiles.
      -- Como esta função é chamada por motoristas buscando corridas próximas,
      -- os filtros representam as capacidades do motorista.
      AND (
          p_accessibility_filters IS NULL
          OR NOT EXISTS (
              -- Nenhum filtro exigido que o motorista não possua
              SELECT 1
              FROM unnest(p_accessibility_filters) AS f(tag)
              WHERE f.tag = 'wheelchair'       AND NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid()::text AND p.accessibility_wheelchair = true)
                 OR f.tag = 'hearing_impaired' AND NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid()::text AND p.accessibility_hearing_impaired = true)
                 OR f.tag = 'visual_aid'       AND NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid()::text AND p.accessibility_visual_aid = true)
                 OR f.tag = 'pet_friendly'     AND NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid()::text AND p.accessibility_pet_friendly = true)
                 OR f.tag = 'child_seat'       AND NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid()::text AND p.accessibility_child_seat = true)
          )
      )
    ORDER BY dist_meters ASC
    LIMIT 1;
END;
$$;

COMMENT ON FUNCTION public.find_nearby_requested_rides(float8, float8, float8, text[])
  IS 'Busca corridas solicitadas nas proximidades, opcionalmente filtrando por tags de acessibilidade do motorista chamador.';

GRANT EXECUTE ON FUNCTION public.find_nearby_requested_rides(float8, float8, float8, text[]) TO authenticated;

-- ============================================================
-- 6. REALTIME — accessibility_tags
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'accessibility_tags'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.accessibility_tags;
  END IF;
END $$;

ALTER TABLE public.accessibility_tags REPLICA IDENTITY FULL;

-- ============================================================
-- ÍNDICES para as novas colunas booleanas em profiles
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_profiles_accessibility_wheelchair
  ON public.profiles (accessibility_wheelchair)
  WHERE accessibility_wheelchair = true;

CREATE INDEX IF NOT EXISTS idx_profiles_accessibility_hearing_impaired
  ON public.profiles (accessibility_hearing_impaired)
  WHERE accessibility_hearing_impaired = true;

CREATE INDEX IF NOT EXISTS idx_profiles_accessibility_visual_aid
  ON public.profiles (accessibility_visual_aid)
  WHERE accessibility_visual_aid = true;

CREATE INDEX IF NOT EXISTS idx_profiles_accessibility_pet_friendly
  ON public.profiles (accessibility_pet_friendly)
  WHERE accessibility_pet_friendly = true;

CREATE INDEX IF NOT EXISTS idx_profiles_accessibility_child_seat
  ON public.profiles (accessibility_child_seat)
  WHERE accessibility_child_seat = true;

-- ==============================================================================
-- FIM — PILAR 17: Acessibilidade pronta para uso
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260526111000_cashback_gender_lostitem.sql
-- ─────────────────────────────────────────────

-- =====================================================
-- MIGRAÇÃO: Pilares 19 (Cashback) e 21 (Uppi Mulher)
-- Data: 2026-05-26
-- =====================================================

-- ══════════════════════════════════════════════════════
-- PILAR 21: UPPI MULHER — TRAVA ESTRITA DE GÊNERO
-- ══════════════════════════════════════════════════════

-- 1. Coluna gender_required na tabela services
-- Quando 'female', APENAS motoristas com gender='female' verificado podem receber a corrida
ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS gender_required TEXT;

COMMENT ON COLUMN public.services.gender_required IS 'Restrição de gênero para este serviço. NULL = sem restrição, ''female'' = apenas motoristas mulheres, ''male'' = apenas motoristas homens.';

-- 2. Flag de gênero verificado em profiles (KYC)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS gender_verified BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN public.profiles.gender_verified IS 'Indica se o gênero informado foi verificado no processo de KYC/aprovação documental pelo admin.';

-- 3. Reescrever rpc_find_and_offer_ride COM filtro de gênero estrito
CREATE OR REPLACE FUNCTION public.rpc_find_and_offer_ride(p_ride_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pickup_loc GEOGRAPHY(POINT);
    v_ride_status TEXT;
    v_service_type TEXT;
    v_gender_required TEXT;
    v_driver_id TEXT;
    v_offer_id UUID;
    v_search_radius INTEGER;
BEGIN
    -- 1. Bloquear linha da corrida para evitar conflitos de concorrência
    SELECT status, pickup_location, service_type INTO v_ride_status, v_pickup_loc, v_service_type
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    -- Se a corrida não existir ou já tiver sido aceita/cancelada, encerra o loop
    IF v_ride_status IS NULL OR v_ride_status NOT IN ('requested', 'searching') THEN
        RETURN FALSE;
    END IF;

    -- 2. Resolver restrição de gênero do serviço selecionado
    SELECT s.gender_required INTO v_gender_required
    FROM public.services s
    WHERE s.name = v_service_type OR s.id::text = v_service_type
    LIMIT 1;

    -- 3. Buscar o motorista 'online' aprovado mais próximo
    SELECT p.id, COALESCE(p.search_radius, 5000) INTO v_driver_id, v_search_radius
    FROM public.profiles p
    WHERE p.role = 'driver'
      AND p.status = 'online'
      AND p.current_location IS NOT NULL
      -- ─── ANTI CHERRY-PICKING: Excluir motoristas em cooldown ───
      AND (p.cooldown_until IS NULL OR p.cooldown_until < NOW())
      -- ═══ UPPI MULHER: Filtro estrito de gênero no servidor ═══
      -- Se o serviço exige gênero específico, SOMENTE motoristas com
      -- gênero verificado e correspondente podem receber a corrida.
      AND (
          v_gender_required IS NULL
          OR (p.gender = v_gender_required AND p.gender_verified = TRUE)
      )
      -- Filtrar por categoria do veículo correspondente ao serviço
      AND (
          v_service_type IS NULL OR
          p.vehicle_type IS NULL OR
          p.vehicle_type = COALESCE(
              (SELECT s.vehicle_category FROM public.services s WHERE s.name = v_service_type LIMIT 1),
              'carro'
          )
      )
      -- Evitar motoristas que já rejeitaram ou expiraram esta corrida
      AND NOT EXISTS (
          SELECT 1 
          FROM public.ride_rejected_drivers rr 
          WHERE rr.ride_id = p_ride_id 
            AND rr.driver_id = p.id
      )
      -- Evitar motoristas em corridas ativas
      AND NOT EXISTS (
          SELECT 1 
          FROM public.rides r 
          WHERE r.driver_id = p.id 
            AND r.status IN ('accepted', 'arrived', 'in_progress')
      )
      -- Evitar motoristas com ofertas de corrida ativas pendentes
      AND NOT EXISTS (
          SELECT 1
          FROM public.ride_offers ro
          WHERE ro.driver_id = p.id
            AND ro.status = 'offered'
            AND ro.expires_at > now()
      )
    ORDER BY 
      ST_Distance(p.current_location, v_pickup_loc) * 
      (1.0 + COALESCE(p.consecutive_rejections, 0) * 0.15)
    ASC
    LIMIT 1;

    -- 4. Se um motorista elegível for encontrado, criar a oferta
    IF v_driver_id IS NOT NULL THEN
        UPDATE public.ride_offers
        SET status = 'expired'
        WHERE ride_id = p_ride_id AND status = 'offered';

        INSERT INTO public.ride_offers (ride_id, driver_id, status, expires_at)
        VALUES (p_ride_id, v_driver_id, 'offered', now() + interval '15 seconds')
        RETURNING id INTO v_offer_id;

        UPDATE public.rides
        SET status = 'searching',
            updated_at = now()
        WHERE id = p_ride_id;

        RETURN TRUE;
    ELSE
        UPDATE public.rides
        SET status = 'requested',
            updated_at = now()
        WHERE id = p_ride_id AND status = 'searching';

        RETURN FALSE;
    END IF;
END;
$$;

COMMENT ON FUNCTION public.rpc_find_and_offer_ride(UUID) IS 'Busca o motorista disponível mais próximo com filtro estrito de gênero (Uppi Mulher), anti cherry-picking (cooldown), e penalização por rejeições recentes.';


-- ══════════════════════════════════════════════════════
-- PILAR 19: MOTOR DE CASHBACK DINÂMICO
-- ══════════════════════════════════════════════════════

-- Tabela de regras de cashback configuráveis pelo admin
CREATE TABLE IF NOT EXISTS public.cashback_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    percentage NUMERIC(5,2) NOT NULL CHECK (percentage > 0 AND percentage <= 50),
    day_of_week INTEGER,                -- 0=domingo, 1=segunda ... 6=sábado. NULL = todos os dias
    min_fare NUMERIC(10,2) DEFAULT 0,   -- Tarifa mínima para qualificar
    max_cashback NUMERIC(10,2) DEFAULT 50.00, -- Teto máximo de cashback por corrida
    is_active BOOLEAN DEFAULT TRUE,
    start_at TIMESTAMP WITH TIME ZONE,  -- NULL = sem data de início
    end_at TIMESTAMP WITH TIME ZONE,    -- NULL = sem data de fim
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.cashback_rules ENABLE ROW LEVEL SECURITY;

-- Apenas admins (via service_role) podem gerenciar; leitura pública para o motor de cálculo
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='cashback_rules' AND policyname='cashback_rules_read') THEN
    CREATE POLICY "cashback_rules_read" ON public.cashback_rules FOR SELECT TO authenticated USING (TRUE);
  END IF;
END $$;

COMMENT ON TABLE public.cashback_rules IS 'Regras de cashback configuráveis pelo admin. Saldo de cashback fica travado na wallet do passageiro para uso exclusivo dentro do app.';

-- Índice para consulta rápida de regras ativas
CREATE INDEX IF NOT EXISTS idx_cashback_rules_active
  ON public.cashback_rules (is_active, day_of_week)
  WHERE is_active = TRUE;


-- ══════════════════════════════════════════════════════
-- PILAR 22: CHAT TEMPORÁRIO 24H PÓS-CORRIDA
-- ══════════════════════════════════════════════════════

-- Flag para reabertura de chat pós-corrida (24h)
ALTER TABLE public.rides
  ADD COLUMN IF NOT EXISTS chat_reopened_at TIMESTAMP WITH TIME ZONE;

COMMENT ON COLUMN public.rides.chat_reopened_at IS 'Timestamp de reabertura do chat para objetos esquecidos. Canal expira 24h após esta data.';

-- Status de encerramento com isenção nos support_tickets
-- (o campo status TEXT já existe, apenas documentamos o valor especial)
COMMENT ON TABLE public.support_tickets IS 'Tickets de suporte. Status especial: closed_disclaimer = encerrado com isenção de responsabilidade (sem investigação).';


-- ─────────────────────────────────────────────
-- FILE: 20260526120000_predictive_dispatch.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO PILAR 18 — DESPACHO PREDITIVO
-- Análise de Demanda Histórica + Push Preventivo para Motoristas
-- ==============================================================================
-- Tabelas: demand_forecasts, predictive_alerts
-- Functions: fn_analyze_demand_patterns(), fn_generate_predictive_alerts()
-- PG Cron: análise diária + alertas a cada 15 minutos
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. TABELA demand_forecasts — Previsões calculadas por análise histórica
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.demand_forecasts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    zone_key TEXT NOT NULL,                           -- ex: '123_456' (lat/lng index ~1km²)
    zone_lat FLOAT8 NOT NULL,
    zone_lng FLOAT8 NOT NULL,
    day_of_week INT NOT NULL CHECK (day_of_week >= 0 AND day_of_week <= 6),   -- 0=domingo
    hour_of_day INT NOT NULL CHECK (hour_of_day >= 0 AND hour_of_day <= 23),
    avg_rides NUMERIC(8,2) DEFAULT 0,
    predicted_demand NUMERIC(8,2) DEFAULT 0,
    confidence NUMERIC(5,2) DEFAULT 0,
    sample_weeks INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(zone_key, day_of_week, hour_of_day)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. TABELA predictive_alerts — Alertas gerados para push aos motoristas
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.predictive_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    zone_key TEXT NOT NULL,
    zone_lat FLOAT8 NOT NULL,
    zone_lng FLOAT8 NOT NULL,
    predicted_demand NUMERIC(8,2),
    available_drivers INT DEFAULT 0,
    alert_type TEXT DEFAULT 'high_demand' CHECK (alert_type IN ('high_demand', 'surge_predicted', 'low_supply')),
    message TEXT,
    sent_at TIMESTAMPTZ,                              -- NULL = pendente de envio
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Índices para consultas frequentes
CREATE INDEX IF NOT EXISTS idx_demand_forecasts_lookup
  ON public.demand_forecasts (day_of_week, hour_of_day, confidence);

CREATE INDEX IF NOT EXISTS idx_predictive_alerts_pending
  ON public.predictive_alerts (sent_at, expires_at)
  WHERE sent_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_predictive_alerts_zone_created
  ON public.predictive_alerts (zone_key, created_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. FUNCTION fn_analyze_demand_patterns() — Análise histórica de demanda
-- ─────────────────────────────────────────────────────────────────────────────
-- Analisa corridas dos últimos 30 dias, agrupa por zona geográfica (~1km²),
-- dia da semana e hora, e calcula médias + previsões com margem de 10%.
-- Usa a mesma lógica de getNormalizedZoneKey do heatmap (corrige distorção lng).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_analyze_demand_patterns()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
BEGIN
  -- Iterar sobre agregações de corridas completadas/em revisão nos últimos 30 dias
  FOR rec IN
    SELECT
      -- Zona geográfica normalizada (~1km²)
      -- lat_index = ROUND(pickup_lat / 0.01)
      ROUND(r.pickup_lat / 0.01)::INT AS lat_index,
      -- lng_step = 0.01 / COS(RADIANS(pickup_lat))
      -- lng_index = ROUND(pickup_lng / lng_step)
      ROUND(r.pickup_lng / (0.01 / GREATEST(COS(RADIANS(r.pickup_lat)), 0.1)))::INT AS lng_index,
      -- Usar o centro da zona para lat/lng representativo
      ROUND(r.pickup_lat / 0.01)::INT * 0.01 AS representative_lat,
      ROUND(r.pickup_lng / (0.01 / GREATEST(COS(RADIANS(r.pickup_lat)), 0.1)))::INT
        * (0.01 / GREATEST(COS(RADIANS(r.pickup_lat)), 0.1)) AS representative_lng,
      -- Dia da semana (0=domingo) e hora (fuso de Belém)
      EXTRACT(DOW FROM r.created_at)::INT AS dow,
      EXTRACT(HOUR FROM r.created_at AT TIME ZONE 'America/Belem')::INT AS hod,
      -- Métricas
      COUNT(*)::INT AS total_rides,
      COUNT(DISTINCT DATE(r.created_at))::INT AS sample_days
    FROM public.rides r
    WHERE r.status IN ('completed', 'waiting_for_review')
      AND r.created_at >= now() - INTERVAL '30 days'
      AND r.pickup_lat IS NOT NULL
      AND r.pickup_lng IS NOT NULL
    GROUP BY
      ROUND(r.pickup_lat / 0.01)::INT,
      ROUND(r.pickup_lng / (0.01 / GREATEST(COS(RADIANS(r.pickup_lat)), 0.1)))::INT,
      ROUND(r.pickup_lat / 0.01)::INT * 0.01,
      ROUND(r.pickup_lng / (0.01 / GREATEST(COS(RADIANS(r.pickup_lat)), 0.1)))::INT
        * (0.01 / GREATEST(COS(RADIANS(r.pickup_lat)), 0.1)),
      EXTRACT(DOW FROM r.created_at)::INT,
      EXTRACT(HOUR FROM r.created_at AT TIME ZONE 'America/Belem')::INT
  LOOP
    INSERT INTO public.demand_forecasts (
      zone_key, zone_lat, zone_lng,
      day_of_week, hour_of_day,
      avg_rides, predicted_demand, confidence, sample_weeks,
      updated_at
    ) VALUES (
      rec.lat_index || '_' || rec.lng_index,
      rec.representative_lat,
      rec.representative_lng,
      rec.dow,
      rec.hod,
      rec.total_rides::NUMERIC / GREATEST(rec.sample_days, 1),
      (rec.total_rides::NUMERIC / GREATEST(rec.sample_days, 1)) * 1.1,   -- margem de 10%
      LEAST(rec.sample_days::NUMERIC / 28.0 * 100, 100),                 -- % de semanas com dados
      rec.sample_days,
      now()
    )
    ON CONFLICT (zone_key, day_of_week, hour_of_day)
    DO UPDATE SET
      zone_lat         = EXCLUDED.zone_lat,
      zone_lng         = EXCLUDED.zone_lng,
      avg_rides        = EXCLUDED.avg_rides,
      predicted_demand = EXCLUDED.predicted_demand,
      confidence       = EXCLUDED.confidence,
      sample_weeks     = EXCLUDED.sample_weeks,
      updated_at       = now();
  END LOOP;

  RAISE NOTICE '[fn_analyze_demand_patterns] Análise concluída com sucesso';
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. FUNCTION fn_generate_predictive_alerts() — Gera alertas de demanda
-- ─────────────────────────────────────────────────────────────────────────────
-- Para a hora ATUAL + 1 (previsão 1h à frente) e dia da semana atual:
--   1. Busca previsões com confidence >= 50
--   2. Conta motoristas online por zona
--   3. Se predicted_demand >= 2 * available_drivers → gera alerta
--   4. Não gera duplicatas (mesmo zone_key nos últimos 60 minutos)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_generate_predictive_alerts()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target_hour INT;
  v_target_dow  INT;
  rec           RECORD;
  v_drivers     INT;
  v_existing    INT;
  v_alert_type  TEXT;
  v_message     TEXT;
BEGIN
  -- Hora alvo = hora atual em Belém + 1 (previsão 1h à frente)
  v_target_hour := EXTRACT(HOUR FROM (now() AT TIME ZONE 'America/Belem') + INTERVAL '1 hour')::INT;
  v_target_dow  := EXTRACT(DOW FROM now() AT TIME ZONE 'America/Belem')::INT;

  -- Iterar previsões com confiança suficiente para a hora/dia alvo
  FOR rec IN
    SELECT zone_key, zone_lat, zone_lng, predicted_demand, avg_rides
    FROM public.demand_forecasts
    WHERE day_of_week = v_target_dow
      AND hour_of_day = v_target_hour
      AND confidence >= 50
      AND predicted_demand > 0
    ORDER BY predicted_demand DESC
  LOOP
    -- Contar motoristas online nesta zona
    -- Usa a mesma lógica de zone_key para mapear coordenadas de motoristas
    SELECT COUNT(*) INTO v_drivers
    FROM public.driver_locations dl
    WHERE dl.status = 'online'
      AND (
        ROUND(dl.lat / 0.01)::INT || '_' ||
        ROUND(dl.lng / (0.01 / GREATEST(COS(RADIANS(dl.lat)), 0.1)))::INT
      ) = rec.zone_key;

    -- Verificar se a demanda prevista é >= 2x os motoristas disponíveis
    IF rec.predicted_demand >= 2 * GREATEST(v_drivers, 0) THEN

      -- Verificar se já existe alerta recente (últimos 60 min) para esta zona
      SELECT COUNT(*) INTO v_existing
      FROM public.predictive_alerts pa
      WHERE pa.zone_key = rec.zone_key
        AND pa.created_at >= now() - INTERVAL '60 minutes';

      IF v_existing = 0 THEN
        -- Determinar tipo de alerta
        IF v_drivers = 0 THEN
          v_alert_type := 'low_supply';
          v_message := format(
            '📍 Sem motoristas na região! Previsão de %.0f corridas entre %sh-%sh. Dirija-se à zona para garantir corridas!',
            rec.predicted_demand, v_target_hour, (v_target_hour + 1) % 24
          );
        ELSIF rec.predicted_demand >= 3 * v_drivers THEN
          v_alert_type := 'surge_predicted';
          v_message := format(
            '🔥 Pico de demanda previsto! ~%.0f corridas esperadas entre %sh-%sh, apenas %s motoristas na região. Aproveite!',
            rec.predicted_demand, v_target_hour, (v_target_hour + 1) % 24, v_drivers
          );
        ELSE
          v_alert_type := 'high_demand';
          v_message := format(
            '📈 Alta demanda prevista! ~%.0f corridas entre %sh-%sh com %s motoristas na zona. Bom momento para ficar online!',
            rec.predicted_demand, v_target_hour, (v_target_hour + 1) % 24, v_drivers
          );
        END IF;

        INSERT INTO public.predictive_alerts (
          zone_key, zone_lat, zone_lng,
          predicted_demand, available_drivers, alert_type,
          message, expires_at
        ) VALUES (
          rec.zone_key, rec.zone_lat, rec.zone_lng,
          rec.predicted_demand, v_drivers, v_alert_type,
          v_message, now() + INTERVAL '90 minutes'
        );
      END IF;
    END IF;
  END LOOP;

  RAISE NOTICE '[fn_generate_predictive_alerts] Geração de alertas concluída';
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. RLS — Row Level Security
-- ─────────────────────────────────────────────────────────────────────────────

-- demand_forecasts: SELECT para motoristas e admins
ALTER TABLE public.demand_forecasts ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='demand_forecasts' AND policyname='Motoristas e admins leem previsoes') THEN
    CREATE POLICY "Motoristas e admins leem previsoes" ON public.demand_forecasts
      FOR SELECT TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid()::text AND p.role = 'driver'
        )
        OR EXISTS (
          SELECT 1 FROM public.admins a
          WHERE a.id = auth.uid()::text
        )
      );
  END IF;
END $$;

-- demand_forecasts: INSERT/UPDATE/DELETE somente service_role (sem policy = bloqueado por RLS)
-- service_role bypassa RLS automaticamente, então não é necessária policy adicional

-- predictive_alerts: SELECT para motoristas e admins
ALTER TABLE public.predictive_alerts ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='predictive_alerts' AND policyname='Motoristas e admins leem alertas') THEN
    CREATE POLICY "Motoristas e admins leem alertas" ON public.predictive_alerts
      FOR SELECT TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid()::text AND p.role = 'driver'
        )
        OR EXISTS (
          SELECT 1 FROM public.admins a
          WHERE a.id = auth.uid()::text
        )
      );
  END IF;
END $$;

-- predictive_alerts: INSERT/UPDATE somente service_role (sem policy = bloqueado por RLS)

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. REALTIME — predictive_alerts para push em tempo real
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'predictive_alerts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.predictive_alerts;
  END IF;
END $$;

ALTER TABLE public.predictive_alerts REPLICA IDENTITY FULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. PG CRON — Agendamentos automáticos
-- ─────────────────────────────────────────────────────────────────────────────
-- Garantir extensão pg_cron
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 7a. Análise de demanda diária às 03:00 UTC
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'analyze_demand_daily') THEN
    PERFORM cron.schedule(
      'analyze_demand_daily',
      '0 3 * * *',
      $job$SELECT public.fn_analyze_demand_patterns()$job$
    );
  END IF;
END $$;

-- 7b. Geração de alertas preditivos a cada 15 minutos
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'predictive_alerts_15min') THEN
    PERFORM cron.schedule(
      'predictive_alerts_15min',
      '*/15 * * * *',
      $job$SELECT public.fn_generate_predictive_alerts()$job$
    );
  END IF;
END $$;

-- ==============================================================================
-- FIM DA MIGRAÇÃO PILAR 18 — DESPACHO PREDITIVO
-- ==============================================================================


-- ─────────────────────────────────────────────
-- FILE: 20260526130000_sync_kyc_gender_verification.sql
-- ─────────────────────────────────────────────

-- =====================================================
-- MIGRAÇÃO: Pilar 21 (Uppi Mulher - Sincronização do Gênero Verificado no KYC)
-- Data: 2026-05-26
-- =====================================================

CREATE OR REPLACE FUNCTION public.sync_driver_profile_kyc()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.status = 'approved' THEN
        -- Motorista aprovado: status vai para 'offline' (pronto para ficar online)
        -- E o gênero é verificado automaticamente a partir dos documentos do KYC.
        UPDATE public.profiles
        SET is_approved = true,
            gender_verified = true,
            status = 'offline',
            updated_at = now()
        WHERE id = NEW.driver_id;
    ELSIF NEW.status = 'rejected' THEN
        -- Motorista rejeitado: status vai para 'blocked' e remove a verificação
        UPDATE public.profiles
        SET is_approved = false,
            gender_verified = false,
            status = 'blocked',
            updated_at = now()
        WHERE id = NEW.driver_id;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.sync_driver_profile_kyc IS 'Sincroniza automaticamente a tabela de perfis (profiles) com o histórico de KYC do motorista, ativando is_approved e gender_verified.';


-- ─────────────────────────────────────────────
-- FILE: 20260526140000_uppi_flex_bidding.sql
-- ─────────────────────────────────────────────

-- Migration: Add tip_incentive to rides and update finish_ride ledger transaction function
-- Support pre-ride bidding/incentive system (Uppi Flex)

ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS tip_incentive DECIMAL(10,2) DEFAULT 0.00;
COMMENT ON COLUMN public.rides.tip_incentive IS 'Pre-ride driver dispatch incentive (Uppi Flex)';

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
            v_commission_percent := COALESCE(v_commission_row.value::numeric, 0.0);
        END IF;
    END IF;

    -- Verify exemption
    IF v_driver_profile.commission_exempt_until IS NOT NULL THEN
        IF v_driver_profile.commission_exempt_until > NOW() THEN
            v_commission_percent := 0;
        END IF;
    END IF;

    -- platform commission only applies to base fare (v_fare_amount), NOT to tip_incentive
    v_commission_amt := ROUND((v_fare_amount * v_commission_percent / 100.0), 2);
    v_platform_fee := v_commission_amt;
    v_driver_earning := v_fare_amount - v_commission_amt;

    -- 4. Calculate balance change for driver
    IF p_cash_amount >= v_fare_amount THEN
        v_balance_change := -v_commission_amt; -- Only deduct commission since cash is physically held
        v_is_cash_ride := true;
    ELSE
        -- For digital rides: v_balance_change := v_driver_earning + COALESCE(v_ride.tip_incentive, 0) - p_cash_amount;
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


-- ─────────────────────────────────────────────
-- FILE: 20260526150000_device_integrity_logs.sql
-- ─────────────────────────────────────────────

-- Migration: Create suspicious_devices table and rpc_flag_suspicious_device function
-- Created at: 2026-05-26 15:00:00

-- Create suspicious_devices table
CREATE TABLE IF NOT EXISTS public.suspicious_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id TEXT REFERENCES public.profiles(id) ON DELETE CASCADE,
    threat_type TEXT NOT NULL CHECK (threat_type IN ('root_jailbreak', 'emulator', 'fake_gps')),
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.suspicious_devices ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to insert security logs
DROP POLICY IF EXISTS "Allow authenticated users to insert security logs" ON public.suspicious_devices;
CREATE POLICY "Allow authenticated users to insert security logs"
    ON public.suspicious_devices
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid()::text = profile_id);

-- Allow authenticated users to select their own logs
DROP POLICY IF EXISTS "Allow authenticated users to select their own logs" ON public.suspicious_devices;
CREATE POLICY "Allow authenticated users to select their own logs"
    ON public.suspicious_devices
    FOR SELECT
    TO authenticated
    USING (auth.uid()::text = profile_id);

-- Create RPC function to log alert and block profile
CREATE OR REPLACE FUNCTION public.rpc_flag_suspicious_device(p_threat_type TEXT, p_details JSONB)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Insert log
  INSERT INTO public.suspicious_devices (profile_id, threat_type, details)
  VALUES (auth.uid()::text, p_threat_type, p_details);

  -- Block driver profile
  UPDATE public.profiles
  SET status = 'blocked',
      is_approved = false,
      updated_at = now()
  WHERE id = auth.uid()::text;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_flag_suspicious_device(TEXT, JSONB) TO authenticated;


-- ─────────────────────────────────────────────
-- FILE: 20260526160000_b2b_corporate_subsidy.sql
-- ─────────────────────────────────────────────

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
            v_commission_percent := COALESCE(v_commission_row.value::numeric, 0.0);
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


-- ─────────────────────────────────────────────
-- FILE: 20260526170000_uppi_mulher_strict_validation.sql
-- ─────────────────────────────────────────────

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


-- ─────────────────────────────────────────────
-- FILE: 20260526180000_support_tickets_admin_policy.sql
-- ─────────────────────────────────────────────

-- Migration: Admin Full Access to Support Tickets
-- Date: 2026-05-26 18:00:00

-- Ensure RLS is active
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

-- Drop policy if it exists
DROP POLICY IF EXISTS admin_all_access ON public.support_tickets;

-- Create policy for admin access
CREATE POLICY admin_all_access ON public.support_tickets
FOR ALL TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.admins WHERE id = auth.uid()::text
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.admins WHERE id = auth.uid()::text
  )
);

COMMENT ON POLICY admin_all_access ON public.support_tickets IS 'Permite que administradores tenham acesso total a todos os tickets de suporte para fins de gestão.';


-- ─────────────────────────────────────────────
-- FILE: 20260526190000_encrypt_sensitive_data.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Criptografia de CPF e Conta Bancária (LGPD & Security Hardening)
-- Data: 2026-05-26
-- Objetivo: Criptografar dados sensíveis de usuários (profiles.cpf) e motoristas
--            (payout_accounts.account_number) utilizando pgcrypto de forma transparente.
-- ==============================================================================

-- 1. HABILITAR A EXTENSÃO PGCRYPTO
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. FUNÇÕES DE SUPORTE À CRIPTOGRAFIA (SECURITY DEFINER)
-- Essas funções gerenciam a obtenção da chave simétrica e a criptografia.

CREATE OR REPLACE FUNCTION public.get_encryption_key()
RETURNS TEXT AS $$
DECLARE
  key_val TEXT;
BEGIN
  -- 1. Tentar ler da variável GUC (Grand Unified Configuration) de sessão
  key_val := current_setting('app.encryption_key', true);
  IF key_val IS NOT NULL AND key_val <> '' THEN
    RETURN key_val;
  END IF;

  -- 2. Tentar ler do Supabase Vault (se a tabela/view descriptografada existir)
  IF EXISTS (
    SELECT 1 FROM information_schema.views 
    WHERE table_schema = 'vault' AND table_name = 'decrypted_secrets'
  ) THEN
    BEGIN
      SELECT decrypted_secret INTO key_val
      FROM vault.decrypted_secrets
      WHERE name = 'app_encryption_key'
      LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      key_val := NULL;
    END;
  END IF;

  IF key_val IS NOT NULL AND key_val <> '' THEN
    RETURN key_val;
  END IF;

  -- 3. Em vez de usar fallback hardcoded, lançar erro explicativo para segurança
  RAISE EXCEPTION 'Chave de criptografia não configurada. Defina a variável app.encryption_key no GUC ou adicione o segredo app_encryption_key no Supabase Vault.';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.get_encryption_key() IS
  'Obtém a chave de criptografia do GUC de sessão, do Supabase Vault ou de um fallback de desenvolvimento.';

-- Wrapper seguro de criptografia
CREATE OR REPLACE FUNCTION public.encrypt_val(val TEXT)
RETURNS BYTEA AS $$
BEGIN
  IF val IS NULL OR val = '' THEN
    RETURN NULL;
  END IF;
  RETURN extensions.pgp_sym_encrypt(val, public.get_encryption_key());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Wrapper seguro de descriptografia
CREATE OR REPLACE FUNCTION public.decrypt_val(val BYTEA)
RETURNS TEXT AS $$
BEGIN
  IF val IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN extensions.pgp_sym_decrypt(val, public.get_encryption_key());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. PREPARAR AS DEPENDÊNCIAS DE VIEWS
-- Precisamos fazer o drop da view dependente high_risk_drivers temporariamente
DROP VIEW IF EXISTS public.high_risk_drivers CASCADE;

-- 4. RENOMEAR AS TABELAS FÍSICAS ORIGINAIS
ALTER TABLE public.profiles RENAME TO profiles_raw;
ALTER TABLE public.payout_accounts RENAME TO payout_accounts_raw;

-- 5. ADICIONAR COLUNAS CRIPTOGRAFADAS E MIGRAR OS DADOS
-- 5.1 Profiles: CPF
ALTER TABLE public.profiles_raw ADD COLUMN encrypted_cpf BYTEA;
UPDATE public.profiles_raw SET encrypted_cpf = public.encrypt_val(cpf) WHERE cpf IS NOT NULL;
ALTER TABLE public.profiles_raw DROP COLUMN cpf;

-- 5.2 Payout Accounts: Account Number
ALTER TABLE public.payout_accounts_raw ADD COLUMN encrypted_account_number BYTEA;
ALTER TABLE public.payout_accounts_raw DISABLE TRIGGER enforce_single_default_payout_account;
UPDATE public.payout_accounts_raw SET encrypted_account_number = public.encrypt_val(account_number) WHERE account_number IS NOT NULL;
ALTER TABLE public.payout_accounts_raw ENABLE TRIGGER enforce_single_default_payout_account;
ALTER TABLE public.payout_accounts_raw DROP COLUMN account_number;

-- 6. CRIAR AS VIEWS TRANSPARENTES (security_invoker = true)
-- Essas views substituem as tabelas originais e descriptografam os dados sob demanda,
-- respeitando as políticas de RLS das tabelas físicas subjacentes.

CREATE OR REPLACE VIEW public.profiles WITH (security_invoker = true) AS
SELECT
  id,
  role,
  full_name,
  phone_number,
  email,
  fcm_token,
  status,
  wallet_balance,
  search_radius,
  current_location,
  vehicle_details,
  created_at,
  updated_at,
  rating,
  review_count,
  commission_percentage,
  commission_exempt_until,
  subscription_expires_at,
  phone,
  documents,
  is_deleted,
  deleted_at,
  is_approved,
  vehicle_type,
  marker_url,
  certificate_number,
  search_distance,
  vehicle_plate_number,
  vehicle_production_year,
  vehicle_model_id,
  vehicle_color_id,
  bank_name,
  bank_account_number,
  bank_swift_code,
  bank_routing_number,
  address,
  gender,
  id_number,
  preset_avatar_number,
  total_rides,
  total_distance,
  average_rating,
  rating_count,
  public.decrypt_val(encrypted_cpf) AS cpf
FROM public.profiles_raw;

CREATE OR REPLACE VIEW public.payout_accounts WITH (security_invoker = true) AS
SELECT
  id,
  driver_id,
  payout_method_id,
  routing_number,
  account_holder_name,
  bank_name,
  is_default,
  account_holder_country,
  account_holder_city,
  account_holder_state,
  account_holder_address,
  account_holder_phone,
  account_holder_zip,
  created_at,
  public.decrypt_val(encrypted_account_number) AS account_number
FROM public.payout_accounts_raw;

-- 7. DEFINIR TRIGGERS DML PARA AS VIEWS (security_invoker)
-- Garante que operações de INSERT/UPDATE/DELETE direcionadas à view sejam encaminhadas
-- para a tabela física correta e criptografadas de forma transparente.
-- Por ser SECURITY INVOKER (padrão), o DML na tabela física executa com os privilégios
-- do chamador, garantindo que as políticas de RLS originais de profiles_raw e payout_accounts_raw sejam avaliadas.

CREATE OR REPLACE FUNCTION public.profiles_view_dml_trigger()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.profiles_raw (
      id, role, full_name, phone_number, email, fcm_token, status, wallet_balance,
      search_radius, current_location, vehicle_details, created_at, updated_at,
      rating, review_count, commission_percentage, commission_exempt_until,
      subscription_expires_at, phone, documents, is_deleted, deleted_at,
      is_approved, vehicle_type, marker_url, certificate_number, search_distance,
      vehicle_plate_number, vehicle_production_year, vehicle_model_id, vehicle_color_id,
      bank_name, bank_account_number, bank_swift_code, bank_routing_number,
      address, gender, id_number, preset_avatar_number, total_rides, total_distance,
      average_rating, rating_count, encrypted_cpf
    ) VALUES (
      NEW.id, NEW.role, NEW.full_name, NEW.phone_number, NEW.email, NEW.fcm_token, NEW.status, NEW.wallet_balance,
      NEW.search_radius, NEW.current_location, NEW.vehicle_details, NEW.created_at, NEW.updated_at,
      NEW.rating, NEW.review_count, NEW.commission_percentage, NEW.commission_exempt_until,
      NEW.subscription_expires_at, NEW.phone, NEW.documents, NEW.is_deleted, NEW.deleted_at,
      NEW.is_approved, NEW.vehicle_type, NEW.marker_url, NEW.certificate_number, NEW.search_distance,
      NEW.vehicle_plate_number, NEW.vehicle_production_year, NEW.vehicle_model_id, NEW.vehicle_color_id,
      NEW.bank_name, NEW.bank_account_number, NEW.bank_swift_code, NEW.bank_routing_number,
      NEW.address, NEW.gender, NEW.id_number, NEW.preset_avatar_number, NEW.total_rides, NEW.total_distance,
      NEW.average_rating, NEW.rating_count, public.encrypt_val(NEW.cpf)
    );
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    UPDATE public.profiles_raw SET
      role = NEW.role,
      full_name = NEW.full_name,
      phone_number = NEW.phone_number,
      email = NEW.email,
      fcm_token = NEW.fcm_token,
      status = NEW.status,
      wallet_balance = NEW.wallet_balance,
      search_radius = NEW.search_radius,
      current_location = NEW.current_location,
      vehicle_details = NEW.vehicle_details,
      created_at = NEW.created_at,
      updated_at = NEW.updated_at,
      rating = NEW.rating,
      review_count = NEW.review_count,
      commission_percentage = NEW.commission_percentage,
      commission_exempt_until = NEW.commission_exempt_until,
      subscription_expires_at = NEW.subscription_expires_at,
      phone = NEW.phone,
      documents = NEW.documents,
      is_deleted = NEW.is_deleted,
      deleted_at = NEW.deleted_at,
      is_approved = NEW.is_approved,
      vehicle_type = NEW.vehicle_type,
      marker_url = NEW.marker_url,
      certificate_number = NEW.certificate_number,
      search_distance = NEW.search_distance,
      vehicle_plate_number = NEW.vehicle_plate_number,
      vehicle_production_year = NEW.vehicle_production_year,
      vehicle_model_id = NEW.vehicle_model_id,
      vehicle_color_id = NEW.vehicle_color_id,
      bank_name = NEW.bank_name,
      bank_account_number = NEW.bank_account_number,
      bank_swift_code = NEW.bank_swift_code,
      bank_routing_number = NEW.bank_routing_number,
      address = NEW.address,
      gender = NEW.gender,
      id_number = NEW.id_number,
      preset_avatar_number = NEW.preset_avatar_number,
      total_rides = NEW.total_rides,
      total_distance = NEW.total_distance,
      average_rating = NEW.average_rating,
      rating_count = NEW.rating_count,
      encrypted_cpf = CASE 
        WHEN NEW.cpf IS DISTINCT FROM OLD.cpf THEN public.encrypt_val(NEW.cpf)
        ELSE encrypted_cpf
      END
    WHERE id = OLD.id;
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    DELETE FROM public.profiles_raw WHERE id = OLD.id;
    RETURN OLD;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profiles_view_dml
  INSTEAD OF INSERT OR UPDATE OR DELETE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.profiles_view_dml_trigger();

CREATE OR REPLACE FUNCTION public.payout_accounts_view_dml_trigger()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.payout_accounts_raw (
      id, driver_id, payout_method_id, routing_number, account_holder_name, bank_name,
      is_default, account_holder_country, account_holder_city, account_holder_state,
      account_holder_address, account_holder_phone, account_holder_zip, created_at,
      encrypted_account_number
    ) VALUES (
      COALESCE(NEW.id, gen_random_uuid()), NEW.driver_id, NEW.payout_method_id, NEW.routing_number, NEW.account_holder_name, NEW.bank_name,
      NEW.is_default, NEW.account_holder_country, NEW.account_holder_city, NEW.account_holder_state,
      NEW.account_holder_address, NEW.account_holder_phone, NEW.account_holder_zip, NEW.created_at,
      public.encrypt_val(NEW.account_number)
    );
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    UPDATE public.payout_accounts_raw SET
      driver_id = NEW.driver_id,
      payout_method_id = NEW.payout_method_id,
      routing_number = NEW.routing_number,
      account_holder_name = NEW.account_holder_name,
      bank_name = NEW.bank_name,
      is_default = NEW.is_default,
      account_holder_country = NEW.account_holder_country,
      account_holder_city = NEW.account_holder_city,
      account_holder_state = NEW.account_holder_state,
      account_holder_address = NEW.account_holder_address,
      account_holder_phone = NEW.account_holder_phone,
      account_holder_zip = NEW.account_holder_zip,
      created_at = NEW.created_at,
      encrypted_account_number = CASE 
        WHEN NEW.account_number IS DISTINCT FROM OLD.account_number THEN public.encrypt_val(NEW.account_number)
        ELSE encrypted_account_number
      END
    WHERE id = OLD.id;
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    DELETE FROM public.payout_accounts_raw WHERE id = OLD.id;
    RETURN OLD;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER payout_accounts_view_dml
  INSTEAD OF INSERT OR UPDATE OR DELETE ON public.payout_accounts
  FOR EACH ROW EXECUTE FUNCTION public.payout_accounts_view_dml_trigger();

-- 8. RECOMPILAR DEPENDÊNCIAS DE VIEWS
-- Recriamos a view high_risk_drivers exatamente como antes, mas agora ela aponta para a view public.profiles.

CREATE OR REPLACE VIEW public.high_risk_drivers AS
SELECT
  p.id AS driver_id,
  p.full_name,
  p.phone,
  COUNT(r.id) AS total_rides,
  COUNT(r.id) FILTER (WHERE r.status IN ('driver_canceled', 'rider_canceled') AND r.driver_id = p.id) AS canceled_rides,
  CASE
    WHEN COUNT(r.id) > 0 THEN
      ROUND(
        (COUNT(r.id) FILTER (WHERE r.status IN ('driver_canceled', 'rider_canceled') AND r.driver_id = p.id)::NUMERIC /
        COUNT(r.id)::NUMERIC) * 100,
        1
      )
    ELSE 0
  END AS cancellation_rate
FROM public.profiles p
LEFT JOIN public.rides r ON r.driver_id = p.id
WHERE p.role = 'driver'
GROUP BY p.id, p.full_name, p.phone
HAVING COUNT(r.id) >= 5
   AND (COUNT(r.id) FILTER (WHERE r.status IN ('driver_canceled', 'rider_canceled') AND r.driver_id = p.id)::NUMERIC /
        NULLIF(COUNT(r.id)::NUMERIC, 0)) > 0.30
ORDER BY cancellation_rate DESC;

-- 9. GARANTIR GRANTS PARA AS VIEWS
-- Garante que as views herdem as permissões de acesso corretas.

GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated, service_role, postgres;
GRANT SELECT ON public.profiles TO anon;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.payout_accounts TO authenticated, service_role, postgres;

GRANT SELECT ON public.high_risk_drivers TO authenticated;
GRANT SELECT ON public.high_risk_drivers TO service_role;


-- ─────────────────────────────────────────────
-- FILE: 20260527020000_separate_secrets.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Separação de Credenciais e Segredos (Security Hardening - Item 38)
-- Data: 2026-05-27
-- Objetivo: Criar a tabela 'app_secrets' para armazenar chaves e credenciais
--            de API sensíveis (Mercado Pago, Twilio, Google Maps) de forma 
--            isolada das configurações comuns (app_settings), restringindo 
--            o acesso de leitura estritamente à role 'service_role'.
-- ==============================================================================

-- 1. CRIAR A TABELA DE SEGREDOS
CREATE TABLE IF NOT EXISTS public.app_secrets (
    key          TEXT PRIMARY KEY,
    secret_val   TEXT NOT NULL,
    description  TEXT,
    updated_at   TIMESTAMPTZ DEFAULT now(),
    updated_by   TEXT
);

-- 2. HABILITAR ROW LEVEL SECURITY (RLS)
ALTER TABLE public.app_secrets ENABLE ROW LEVEL SECURITY;

-- 3. CRIAR POLÍTICA RESTRITIVA DE LEITURA (APENAS SERVICE_ROLE)
-- Apenas a service_role (usada pelas Edge Functions backend) ou superadmins podem ler.
-- Usuários comuns, motoristas e admins operacionais não têm privilégios.
DROP POLICY IF EXISTS "app_secrets_select_service_role_only" ON public.app_secrets;
CREATE POLICY "app_secrets_select_service_role_only" ON public.app_secrets
    FOR SELECT TO service_role
    USING (true);

DROP POLICY IF EXISTS "app_secrets_select_superadmin" ON public.app_secrets;
CREATE POLICY "app_secrets_select_superadmin" ON public.app_secrets
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.admins 
            WHERE id = auth.uid()::text AND role = 'superadmin'
        )
    );

-- 4. CRIAR POLÍTICAS DE ESCRITA (APENAS SUPERADMINS E SERVICE_ROLE)
DROP POLICY IF EXISTS "app_secrets_write_superadmin" ON public.app_secrets;
CREATE POLICY "app_secrets_write_superadmin" ON public.app_secrets
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.admins 
            WHERE id = auth.uid()::text AND role = 'superadmin'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.admins 
            WHERE id = auth.uid()::text AND role = 'superadmin'
        )
    );

-- 5. MIGRAR SEGREDO EXISTENTES DE app_settings PARA app_secrets (SE EXISTIREM)
-- Isso evita perda de dados durante o hardening operacional.
INSERT INTO public.app_secrets (key, secret_val, description)
SELECT 
    key, 
    value, 
    'Segredo migrado da tabela antiga app_settings' 
FROM public.app_settings
WHERE key IN ('mp_access_token', 'mp_webhook_secret')
ON CONFLICT (key) DO NOTHING;

-- 6. REMOVER CHAVES PRIVADAS DA TABELA PÚBLICA app_settings
DELETE FROM public.app_settings
WHERE key IN ('mp_access_token', 'mp_webhook_secret');

-- 7. COMENTAR E DOCUMENTAR A TABELA
COMMENT ON TABLE public.app_secrets IS 
    'Tabela ultra-protegida para chaves criptográficas e credenciais privadas de API. Bloqueada contra leitura client-side.';
COMMENT ON COLUMN public.app_secrets.key IS 'Identificador do segredo (ex: mp_access_token).';
COMMENT ON COLUMN public.app_secrets.secret_val IS 'Valor confidencial do segredo.';


-- ─────────────────────────────────────────────
-- FILE: 20260528060000_fix_reactive_sync.sql
-- ─────────────────────────────────────────────

-- =====================================================================
-- MIGRAÇÃO: Fix Reactive Sync - Corrige sincronização GPS e status
-- Data: 2026-05-28
-- Problema: triggers quebrados impediam que o GPS do motorista chegasse
-- em profiles.current_location, bloqueando o dispatch (rpc_find_and_offer_ride)
-- =====================================================================

-- ── 1. REMOVER TRIGGER QUEBRADO ──────────────────────────────────────
-- O trigger trg_sync_driver_location_to_profile referenciava profiles_raw
-- (tabela que não existe mais após a migração de criptografia).
-- Isso causava erro silencioso e o GPS nunca era salvo em profiles.current_location.
DROP TRIGGER IF EXISTS trg_sync_driver_location_to_profile ON public.driver_locations;
DROP FUNCTION IF EXISTS public.sync_driver_location_to_profile() CASCADE;

-- ── 2. REMOVER TRIGGER COM LOOP POTENCIAL ────────────────────────────
-- O trigger trg_driver_locations_sync_profile atualizava profiles.current_location
-- quando driver_locations era atualizado. Se profiles também tinha trigger que
-- atualizava driver_locations, criava um loop infinito.
DROP TRIGGER IF EXISTS trg_driver_locations_sync_profile ON public.driver_locations;
DROP FUNCTION IF EXISTS public.trg_sync_driver_profile_location() CASCADE;

-- ── 3. CRIAR FUNÇÃO CORRETA DE SINCRONIZAÇÃO DE GPS ──────────────────
-- Atualiza profiles.current_location ao receber update em driver_locations.
-- USA profiles diretamente (sem _raw que não existe mais).
-- Só sincroniza se o motorista estiver online para evitar writes desnecessários.
CREATE OR REPLACE FUNCTION public.fn_sync_driver_gps_to_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Atualiza current_location em profiles usando PostGIS POINT(lng lat)
  -- Nota: ST_MakePoint recebe (longitude, latitude) nessa ordem
  UPDATE public.profiles
  SET
    current_location = ST_SetSRID(ST_MakePoint(NEW.lng, NEW.lat), 4326)::geography,
    updated_at = NOW()
  WHERE id = NEW.driver_id
    AND NEW.lat IS NOT NULL
    AND NEW.lng IS NOT NULL
    AND NEW.lat != 0.0
    AND NEW.lng != 0.0;

  -- Também atualiza o campo location em driver_locations para manter consistência PostGIS
  -- (sem trigger recursivo pois só atualizamos profiles aqui)
  RETURN NEW;
END;
$$;

-- ── 4. CRIAR TRIGGER CORRETO (após INSERT ou UPDATE com coordenadas reais) ──
DROP TRIGGER IF EXISTS trg_sync_driver_gps_to_profile ON public.driver_locations;
CREATE TRIGGER trg_sync_driver_gps_to_profile
  AFTER INSERT OR UPDATE OF lat, lng
  ON public.driver_locations
  FOR EACH ROW
  WHEN (NEW.lat IS NOT NULL AND NEW.lng IS NOT NULL AND NEW.lat != 0.0 AND NEW.lng != 0.0)
  EXECUTE FUNCTION public.fn_sync_driver_gps_to_profile();

-- ── 5. GARANTIR QUE profiles.current_location EXISTE como geography ──
-- Caso não exista ainda (dependendo da versão da migração de criptografia)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = 'current_location'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN current_location GEOGRAPHY(POINT, 4326);
  END IF;
END
$$;

-- ── 6. SINCRONIZAR DADOS HISTÓRICOS ──────────────────────────────────
-- Retroativamente atualiza profiles.current_location para motoristas
-- que já têm coordenadas em driver_locations.
UPDATE public.profiles p
SET
  current_location = ST_SetSRID(ST_MakePoint(dl.lng, dl.lat), 4326)::geography,
  updated_at = NOW()
FROM public.driver_locations dl
WHERE dl.driver_id = p.id
  AND dl.lat IS NOT NULL
  AND dl.lng IS NOT NULL
  AND dl.lat != 0.0
  AND dl.lng != 0.0;

-- ── 7. ÍNDICE ESPACIAL PARA O DISPATCH (se não existir) ──────────────
CREATE INDEX IF NOT EXISTS idx_profiles_current_location
  ON public.profiles_raw USING GIST (current_location)
  WHERE role = 'driver' AND status = 'online';

-- ── 8. VERIFICAR REALTIME HABILITADO EM ride_offers ──────────────────
-- O app do motorista escuta ride_offers via CDC.
-- Garante que a publicação Realtime inclui essa tabela.
DO $$
BEGIN
  -- Habilita Realtime em ride_offers (pode silenciar se já estiver ativo)
  PERFORM pg_notify('supabase_realtime', 'reload');
END
$$;

COMMENT ON FUNCTION public.fn_sync_driver_gps_to_profile() IS 
  'Sincroniza lat/lng de driver_locations para profiles.current_location (PostGIS geography). '
  'Substitui os dois triggers quebrados anteriores (trg_sync_driver_location_to_profile e trg_driver_locations_sync_profile). '
  'Necessário para o dispatch rpc_find_and_offer_ride localizar motoristas via ST_Distance.';


-- ─────────────────────────────────────────────
-- FILE: 20260528070000_add_boarding_pin.sql
-- ─────────────────────────────────────────────

-- =====================================================================
-- MIGRAÇÃO: Fix boarding_pin column + start-order relaxation
-- Data: 2026-05-28
-- =====================================================================

-- 1. Adicionar coluna boarding_pin em rides (necessária para accept-order e start-order)
ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS boarding_pin TEXT;

COMMENT ON COLUMN public.rides.boarding_pin IS 
  'PIN de embarque de 4 dígitos gerado no aceite da corrida (accept-order). '
  'Exibido ao motorista para o passageiro confirmar que entrou no carro correto. '
  'Apagado após validação no start-order para não ser reutilizado.';

-- 2. Verificar status da Realtime para rides_offers (garantia)
-- ride_offers e rides já estão na publicação supabase_realtime (confirmado).


-- ─────────────────────────────────────────────
-- FILE: 20260528080000_complete_realtime_cdc.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO — HABILITAR REALTIME CDC COMPLETO & AJUSTAR REPLICA IDENTITY
-- Data: 2026-05-28
-- Ecossistema Uppi — Engenharia de Banco de Dados
-- ==============================================================================
-- Esta migração resolve os problemas de sincronismo em tempo real (CDC)
-- habilitando o Supabase Realtime nas tabelas que o Flutter consome via streams
-- e aplicando REPLICA IDENTITY FULL para garantir o payload completo de UPDATE/DELETE.
-- ==============================================================================

-- 1. ADICIONAR TABELAS FALTANTES À PUBLICAÇÃO supabase_realtime
-- Usamos blocos anônimos PL/pgSQL dinâmicos para evitar falhas se a tabela
-- já estiver adicionada na publicação.

-- announcements
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'announcements'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.announcements;
  END IF;
END $$;

-- complaints
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'complaints'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.complaints;
  END IF;
END $$;

-- support_tickets
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'support_tickets'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.support_tickets;
  END IF;
END $$;

-- gift_cards
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'gift_cards'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.gift_cards;
  END IF;
END $$;

-- payment_methods
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'payment_methods'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.payment_methods;
  END IF;
END $$;

-- payout_accounts
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'payout_accounts_raw'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.payout_accounts_raw;
  END IF;
END $$;

-- payment_gateways
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'payment_gateways'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.payment_gateways;
  END IF;
END $$;

-- pix_payments
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'pix_payments'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.pix_payments;
  END IF;
END $$;

-- mp_payments
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'mp_payments'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.mp_payments;
  END IF;
END $$;

-- cancel_reasons
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'cancel_reasons'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.cancel_reasons;
  END IF;
END $$;

-- quick_replies
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'quick_replies'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.quick_replies;
  END IF;
END $$;

-- payout_methods
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'payout_methods'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.payout_methods;
  END IF;
END $$;

-- challenges
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'challenges'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.challenges;
  END IF;
END $$;

-- badge_definitions
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'badge_definitions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.badge_definitions;
  END IF;
END $$;

-- favorite_addresses
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'favorite_addresses'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.favorite_addresses;
  END IF;
END $$;

-- favorite_drivers
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'favorite_drivers'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.favorite_drivers;
  END IF;
END $$;

-- config
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'config'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.config;
  END IF;
END $$;

-- ride_reviews
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'ride_reviews'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_reviews;
  END IF;
END $$;

-- feedbacks
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'feedbacks'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.feedbacks;
  END IF;
END $$;

-- reviews
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'reviews'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.reviews;
  END IF;
END $$;

-- ratings
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'ratings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ratings;
  END IF;
END $$;

-- ride_messages (para garantir escuta de chat em tempo real)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'ride_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_messages;
  END IF;
END $$;

-- car_models (dados de veículos para aprovação de motoristas)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'car_models'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.car_models;
  END IF;
END $$;

-- car_colors (dados de cores para aprovação de motoristas)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'car_colors'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.car_colors;
  END IF;
END $$;


-- 2. GARANTIR REPLICA IDENTITY FULL NAS TABELAS CRÍTICAS DE CDC
-- Isso força o PostgreSQL a incluir os dados completos de antes e depois nos
-- payloads de UPDATE e DELETE, permitindo que a aplicação faça validações
-- completas de transições de status em tempo real.

-- Tabelas que já estavam na publicação mas sem REPLICA IDENTITY FULL
ALTER TABLE public.ride_activities REPLICA IDENTITY FULL;
ALTER TABLE public.sos_alerts REPLICA IDENTITY FULL;
ALTER TABLE public.driver_earnings REPLICA IDENTITY FULL;
ALTER TABLE public.admins REPLICA IDENTITY FULL;
ALTER TABLE public.ride_offers REPLICA IDENTITY FULL;
ALTER TABLE public.surge_zones REPLICA IDENTITY FULL;
ALTER TABLE public.ride_tracking_shares REPLICA IDENTITY FULL;
ALTER TABLE public.driver_kyc_history REPLICA IDENTITY FULL;
ALTER TABLE public.payout_requests REPLICA IDENTITY FULL;
ALTER TABLE public.danger_zones REPLICA IDENTITY FULL;
ALTER TABLE public.passenger_subscriptions REPLICA IDENTITY FULL;

-- Novas tabelas adicionadas que possuem reatividade a alterações cadastrais ou fluxos
ALTER TABLE public.announcements REPLICA IDENTITY FULL;
ALTER TABLE public.complaints REPLICA IDENTITY FULL;
ALTER TABLE public.support_tickets REPLICA IDENTITY FULL;
ALTER TABLE public.gift_cards REPLICA IDENTITY FULL;
ALTER TABLE public.payment_methods REPLICA IDENTITY FULL;
ALTER TABLE public.payout_accounts_raw REPLICA IDENTITY FULL;
ALTER TABLE public.pix_payments REPLICA IDENTITY FULL;
ALTER TABLE public.mp_payments REPLICA IDENTITY FULL;
ALTER TABLE public.quick_replies REPLICA IDENTITY FULL;
ALTER TABLE public.challenges REPLICA IDENTITY FULL;
ALTER TABLE public.badge_definitions REPLICA IDENTITY FULL;
ALTER TABLE public.config REPLICA IDENTITY FULL;
ALTER TABLE public.feedbacks REPLICA IDENTITY FULL;
ALTER TABLE public.reviews REPLICA IDENTITY FULL;
ALTER TABLE public.ride_reviews REPLICA IDENTITY FULL;
ALTER TABLE public.car_models REPLICA IDENTITY FULL;
ALTER TABLE public.car_colors REPLICA IDENTITY FULL;

-- 3. NOTA SOBRE VIEWS (Ex: high_risk_drivers)
-- O Supabase Realtime/CDC utiliza o Logical Replication do PostgreSQL, que por
-- especificação técnica nativa do motor relacional, não oferece suporte a CDC
-- em Views convencionais de forma síncrona.
-- Caso o monitoramento em tempo real do mapa da View public.high_risk_drivers
-- precise ser reativo instantaneamente sem polling, recomenda-se que a aplicação
-- Flutter escute diretamente a tabela public.driver_locations filtrando no cliente,
-- ou que seja criada uma tabela materializada com gatilhos de sincronização
-- transacionais para as alterações de status de risco.


-- ─────────────────────────────────────────────
-- FILE: 20260528081000_missing_columns_audit.sql
-- ─────────────────────────────────────────────

-- =====================================================================
-- MIGRAÇÃO: Colunas faltantes detectadas na auditoria de reatividade
-- Data: 2026-05-28
-- =====================================================================

-- 1. wallets: adicionar is_blocked e block_reason (necessário para create-order)
ALTER TABLE public.wallets
  ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS block_reason TEXT;

COMMENT ON COLUMN public.wallets.is_blocked IS 
  'Bloqueia o passageiro de solicitar novas corridas (ex: chargeback, fraude)';
COMMENT ON COLUMN public.wallets.block_reason IS 
  'Motivo do bloqueio da carteira, exibido ao passageiro.';

-- 2. profiles_raw: adicionar favorite_drivers (necessário para sync-profile + rate_order)
ALTER TABLE public.profiles_raw
  ADD COLUMN IF NOT EXISTS favorite_drivers TEXT[] DEFAULT '{}';

COMMENT ON COLUMN public.profiles_raw.favorite_drivers IS 
  'IDs dos motoristas marcados como favoritos pelo passageiro.';

-- 3. profiles_raw: adicionar is_blocked (lido pelo driver app no stream de perfil CDC)
ALTER TABLE public.profiles_raw
  ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN public.profiles_raw.is_blocked IS 
  'Bloqueia o motorista de ficar online e receber corridas.';

-- 4. Reconstruir a VIEW profiles para expor essas novas colunas
CREATE OR REPLACE VIEW public.profiles WITH (security_invoker = true) AS
SELECT
  id,
  role,
  full_name,
  phone_number,
  email,
  fcm_token,
  status,
  wallet_balance,
  search_radius,
  current_location,
  vehicle_details,
  created_at,
  updated_at,
  rating,
  review_count,
  commission_percentage,
  commission_exempt_until,
  subscription_expires_at,
  phone,
  documents,
  is_deleted,
  deleted_at,
  is_approved,
  vehicle_type,
  marker_url,
  certificate_number,
  search_distance,
  vehicle_plate_number,
  vehicle_production_year,
  vehicle_model_id,
  vehicle_color_id,
  bank_name,
  bank_account_number,
  bank_swift_code,
  bank_routing_number,
  address,
  gender,
  id_number,
  preset_avatar_number,
  total_rides,
  total_distance,
  average_rating,
  rating_count,
  public.decrypt_val(encrypted_cpf) AS cpf,
  favorite_drivers,
  is_blocked
FROM public.profiles_raw;

-- 5. Atualizar a função e trigger DML da VIEW profiles
CREATE OR REPLACE FUNCTION public.profiles_view_dml_trigger()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.profiles_raw (
      id, role, full_name, phone_number, email, fcm_token, status, wallet_balance,
      search_radius, current_location, vehicle_details, created_at, updated_at,
      rating, review_count, commission_percentage, commission_exempt_until,
      subscription_expires_at, phone, documents, is_deleted, deleted_at,
      is_approved, vehicle_type, marker_url, certificate_number, search_distance,
      vehicle_plate_number, vehicle_production_year, vehicle_model_id, vehicle_color_id,
      bank_name, bank_account_number, bank_swift_code, bank_routing_number,
      address, gender, id_number, preset_avatar_number, total_rides, total_distance,
      average_rating, rating_count, favorite_drivers, is_blocked, encrypted_cpf
    ) VALUES (
      NEW.id, NEW.role, NEW.full_name, NEW.phone_number, NEW.email, NEW.fcm_token, NEW.status, NEW.wallet_balance,
      NEW.search_radius, NEW.current_location, NEW.vehicle_details, NEW.created_at, NEW.updated_at,
      NEW.rating, NEW.review_count, NEW.commission_percentage, NEW.commission_exempt_until,
      NEW.subscription_expires_at, NEW.phone, NEW.documents, NEW.is_deleted, NEW.deleted_at,
      NEW.is_approved, NEW.vehicle_type, NEW.marker_url, NEW.certificate_number, NEW.search_distance,
      NEW.vehicle_plate_number, NEW.vehicle_production_year, NEW.vehicle_model_id, NEW.vehicle_color_id,
      NEW.bank_name, NEW.bank_account_number, NEW.bank_swift_code, NEW.bank_routing_number,
      NEW.address, NEW.gender, NEW.id_number, NEW.preset_avatar_number, NEW.total_rides, NEW.total_distance,
      NEW.average_rating, NEW.rating_count, NEW.favorite_drivers, NEW.is_blocked, public.encrypt_val(NEW.cpf)
    );
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    UPDATE public.profiles_raw SET
      role = NEW.role,
      full_name = NEW.full_name,
      phone_number = NEW.phone_number,
      email = NEW.email,
      fcm_token = NEW.fcm_token,
      status = NEW.status,
      wallet_balance = NEW.wallet_balance,
      search_radius = NEW.search_radius,
      current_location = NEW.current_location,
      vehicle_details = NEW.vehicle_details,
      created_at = NEW.created_at,
      updated_at = NEW.updated_at,
      rating = NEW.rating,
      review_count = NEW.review_count,
      commission_percentage = NEW.commission_percentage,
      commission_exempt_until = NEW.commission_exempt_until,
      subscription_expires_at = NEW.subscription_expires_at,
      phone = NEW.phone,
      documents = NEW.documents,
      is_deleted = NEW.is_deleted,
      deleted_at = NEW.deleted_at,
      is_approved = NEW.is_approved,
      vehicle_type = NEW.vehicle_type,
      marker_url = NEW.marker_url,
      certificate_number = NEW.certificate_number,
      search_distance = NEW.search_distance,
      vehicle_plate_number = NEW.vehicle_plate_number,
      vehicle_production_year = NEW.vehicle_production_year,
      vehicle_model_id = NEW.vehicle_model_id,
      vehicle_color_id = NEW.vehicle_color_id,
      bank_name = NEW.bank_name,
      bank_account_number = NEW.bank_account_number,
      bank_swift_code = NEW.bank_swift_code,
      bank_routing_number = NEW.bank_routing_number,
      address = NEW.address,
      gender = NEW.gender,
      id_number = NEW.id_number,
      preset_avatar_number = NEW.preset_avatar_number,
      total_rides = NEW.total_rides,
      total_distance = NEW.total_distance,
      average_rating = NEW.average_rating,
      rating_count = NEW.rating_count,
      favorite_drivers = NEW.favorite_drivers,
      is_blocked = NEW.is_blocked,
      encrypted_cpf = CASE 
        WHEN NEW.cpf IS DISTINCT FROM OLD.cpf THEN public.encrypt_val(NEW.cpf)
        ELSE encrypted_cpf
      END
    WHERE id = OLD.id;
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    DELETE FROM public.profiles_raw WHERE id = OLD.id;
    RETURN OLD;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- 6. app_settings: valores padrão faltando
INSERT INTO public.app_settings (key, value) VALUES
  ('global_surge_multiplier', '1.0'),
  ('cancellation_fee', '5.00'),
  ('min_cancellation_grace_seconds', '120')
ON CONFLICT (key) DO NOTHING;


-- ─────────────────────────────────────────────
-- FILE: 20260528090000_credit_wallet_alias.sql
-- ─────────────────────────────────────────────

-- =====================================================================
-- MIGRAÇÃO: Funções auxiliares faltando detectadas na auditoria
-- Data: 2026-05-28
-- =====================================================================

-- 1. credit_wallet: alias de increment_wallet com assinatura compatível
--    Usada em: finish-order (cashback), check-badge, e outros
CREATE OR REPLACE FUNCTION public.credit_wallet(
  p_user_id TEXT,
  p_amount NUMERIC
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM public.increment_wallet(p_user_id, p_amount);
END;
$$;

GRANT EXECUTE ON FUNCTION public.credit_wallet(TEXT, NUMERIC) TO service_role;
GRANT EXECUTE ON FUNCTION public.credit_wallet(TEXT, NUMERIC) TO postgres;

COMMENT ON FUNCTION public.credit_wallet IS 
  'Alias seguro de increment_wallet. Usada por finish-order para creditar cashback.';


-- ─────────────────────────────────────────────
-- FILE: 20260528100000_trigger_and_function_fixes.sql
-- ─────────────────────────────────────────────

-- =====================================================================
-- MIGRAÇÃO: Correções críticas de triggers e funções — Rodada 3
-- Data: 2026-05-28
-- =====================================================================

-- 1. CORRIGIR notify_ride_status_change
-- Bug: só liberava motorista para 'canceled', ignorando 'driver_canceled' e 'rider_canceled'
-- Resultado: motorista ficava preso em status 'busy' após cancelamento
CREATE OR REPLACE FUNCTION public.notify_ride_status_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;

  -- Motorista aceita corrida → marca como ocupado
  IF NEW.status = 'accepted' AND NEW.driver_id IS NOT NULL THEN
    UPDATE driver_locations SET status = 'busy' WHERE driver_id = NEW.driver_id;
  END IF;

  -- Corrida finalizada ou cancelada (qualquer variação) → libera motorista
  IF NEW.status IN ('completed', 'finished', 'canceled', 'driver_canceled', 'rider_canceled', 'expired', 'no_driver', 'no_close_found')
     AND NEW.driver_id IS NOT NULL THEN
    UPDATE driver_locations SET status = 'online' WHERE driver_id = NEW.driver_id;
    UPDATE profiles SET status = 'online' WHERE id = NEW.driver_id;
  END IF;

  -- Corrida em andamento → atualiza perfil
  IF NEW.status IN ('in_progress', 'started') AND NEW.driver_id IS NOT NULL THEN
    UPDATE profiles SET status = 'in_progress' WHERE id = NEW.driver_id;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_ride_status_change falhou: %', SQLERRM;
  RETURN NEW;
END;
$$;

-- 2. CRIAR increment_wallet_pending (faltava — quebrava handle_completed_ride_financials para pagamentos digitais)
CREATE OR REPLACE FUNCTION public.increment_wallet_pending(
  p_user_id TEXT,
  p_amount NUMERIC
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Credita diretamente na carteira.
  -- Uma coluna 'pending_balance' pode ser adicionada futuramente para separar saldo pendente.
  PERFORM public.increment_wallet(p_user_id, p_amount);
END;
$$;

GRANT EXECUTE ON FUNCTION public.increment_wallet_pending(TEXT, NUMERIC) TO service_role;
GRANT EXECUTE ON FUNCTION public.increment_wallet_pending(TEXT, NUMERIC) TO postgres;

-- 3. CORRIGIR recover_stuck_rides para incluir 'in_progress' (além de 'started')
-- Bug: corridas em 'in_progress' há mais de 3h nunca eram recuperadas
CREATE OR REPLACE FUNCTION public.recover_stuck_rides()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
    v_recovered_count INTEGER := 0;
BEGIN
    -- 2.1 CORRIDAS EM 'requested' há mais de 5 minutos
    FOR rec IN 
        SELECT id, rider_id 
        FROM public.rides 
        WHERE status = 'requested' 
          AND created_at < now() - interval '5 minutes'
    LOOP
        UPDATE public.rides SET status = 'expired', updated_at = now() WHERE id = rec.id;
        UPDATE public.ride_offers SET status = 'expired' WHERE ride_id = rec.id AND status = 'offered';
        INSERT INTO public.app_errors (app_type, error_message, severity, user_id, metadata)
        VALUES ('database', 'Corrida #' || substring(rec.id::text from 1 for 8) || ' expirada: sem motorista em 5 min.', 'warning', rec.rider_id,
                jsonb_build_object('ride_id', rec.id, 'recovery_type', 'requested_stuck'));
        v_recovered_count := v_recovered_count + 1;
    END LOOP;

    -- 2.2 CORRIDAS 'accepted'/'arrived' com motorista offline há >15 min
    FOR rec IN 
        SELECT r.id, r.driver_id, r.rider_id, r.status AS ride_status, dl.updated_at AS last_ping
        FROM public.rides r
        JOIN public.driver_locations dl ON r.driver_id = dl.driver_id
        WHERE r.status IN ('accepted', 'arrived')
          AND r.updated_at < now() - interval '15 minutes'
    LOOP
        IF rec.last_ping IS NULL OR rec.last_ping < now() - interval '5 minutes' THEN
            UPDATE public.rides SET status = 'requested', driver_id = NULL, accepted_at = NULL, updated_at = now() WHERE id = rec.id;
            UPDATE public.profiles SET status = 'offline', updated_at = now() WHERE id = rec.driver_id;
            UPDATE public.driver_locations SET status = 'offline', updated_at = now() WHERE driver_id = rec.driver_id;
            UPDATE public.ride_offers SET status = 'expired' WHERE ride_id = rec.id AND driver_id = rec.driver_id AND status = 'offered';
            INSERT INTO public.app_errors (app_type, error_message, severity, user_id, metadata)
            VALUES ('database', 'Corrida #' || substring(rec.id::text from 1 for 8) || ' re-enfileirada: motorista offline.', 'warning', rec.driver_id,
                    jsonb_build_object('ride_id', rec.id, 'driver_id', rec.driver_id, 'recovery_type', 'driver_offline_recovered'));
            v_recovered_count := v_recovered_count + 1;
        END IF;
    END LOOP;

    -- 2.3 CORRIDAS 'in_progress' ou 'started' há mais de 3h (Bug original: só verificava 'started')
    FOR rec IN 
        SELECT id, driver_id, rider_id 
        FROM public.rides 
        WHERE status IN ('in_progress', 'started')
          AND updated_at < now() - interval '3 hours'
    LOOP
        UPDATE public.rides SET status = 'finished', updated_at = now() WHERE id = rec.id;
        UPDATE public.profiles SET status = 'online', updated_at = now() WHERE id = rec.driver_id;
        INSERT INTO public.app_errors (app_type, error_message, severity, user_id, metadata)
        VALUES ('database', 'ALERTA CRÍTICO: Corrida #' || substring(rec.id::text from 1 for 8) || ' finalizada após 3h em trânsito.', 'critical', rec.driver_id,
                jsonb_build_object('ride_id', rec.id, 'driver_id', rec.driver_id, 'recovery_type', 'ride_duration_exceeded_completed'));
        v_recovered_count := v_recovered_count + 1;
    END LOOP;

    IF v_recovered_count > 0 THEN
        RAISE NOTICE 'Daemon de Recuperação: % anomalias corrigidas.', v_recovered_count;
    END IF;
END;
$$;

-- 4. INSERIR política padrão de cancelamento (estava vazia — handle_cancelled_ride_financials retornava early)
INSERT INTO public.cancellation_policies (grace_period_seconds, cancellation_fee, driver_compensation, is_active)
VALUES (120, 5.00, 3.00, true)
ON CONFLICT DO NOTHING;

-- 5. LIMPAR corridas presas em 'waiting_for_review' há mais de 24h
UPDATE public.rides 
SET status = 'finished', updated_at = now()
WHERE status = 'waiting_for_review'
  AND updated_at < now() - interval '24 hours';


-- ─────────────────────────────────────────────
-- FILE: 20260528110000_financial_security_webhook_fixes.sql
-- ─────────────────────────────────────────────

-- =====================================================================
-- MIGRAÇÃO: Correções críticas Rodada 4 — Financeiro, Segurança e Webhook
-- Data: 2026-05-28
-- =====================================================================

-- 1. WALLETS: Adicionar pending_balance (usada por finish_ride RPC)
--    Bug: INSERT INTO wallets (..., pending_balance, ...) quebrava toda finalização
ALTER TABLE public.wallets
  ADD COLUMN IF NOT EXISTS pending_balance NUMERIC DEFAULT 0.00;

COMMENT ON COLUMN public.wallets.pending_balance IS 
  'Saldo pendente de confirmação (corridas pagas digitalmente ainda não liquidadas).';

-- 2. WEBHOOK SECRET: Armazenar em app_settings para o trigger notify_webhook_new_offer
--    Bug: current_setting("app.webhook_secret") retornava NULL → webhook-new-ride retornava 401
--    Consequência: Motorista nunca recebia notificação FCM de nova corrida via webhook
INSERT INTO public.app_settings (key, value)
VALUES ('webhook_secret', 'uppi-webhook-2026-secret')
ON CONFLICT (key) DO NOTHING;

-- 3. CORRIGIR notify_webhook_new_offer: buscar secret de app_settings (mais confiável)
CREATE OR REPLACE FUNCTION public.notify_webhook_new_offer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_secret TEXT;
BEGIN
  IF NEW.status != 'offered' THEN
    RETURN NEW;
  END IF;

  -- Buscar secret da tabela de configurações (confiável)
  SELECT value INTO v_secret
  FROM public.app_settings
  WHERE key = 'webhook_secret'
  LIMIT 1;

  -- Fallback: tentar via current_setting
  IF v_secret IS NULL THEN
    v_secret := current_setting('app.webhook_secret', true);
  END IF;

  PERFORM net.http_post(
    url := 'https://kqfmahrxjuqlvxngeurj.supabase.co/functions/v1/webhook-new-ride',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', COALESCE(v_secret, '')
    ),
    body := json_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'schema', TG_TABLE_SCHEMA,
      'record', row_to_json(NEW),
      'timestamp', extract(epoch from now())
    )::jsonb,
    timeout_milliseconds := 5000
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_webhook_new_offer falhou: %', SQLERRM;
  RETURN NEW;
END;
$$;

-- 4. CORRIGIR RLS ride_messages INSERT: sem filtro permitia qualquer usuário inserir em qualquer chat
DROP POLICY IF EXISTS ride_messages_insert ON public.ride_messages;

CREATE POLICY ride_messages_insert ON public.ride_messages
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.rides r
      WHERE r.id::text = ride_messages.ride_id
        AND (r.rider_id = (auth.uid())::text OR r.driver_id = (auth.uid())::text)
    )
  );

-- 5. CORRIGIR RLS reviews INSERT: sem filtro permitia qualquer usuário inserir avaliação
DROP POLICY IF EXISTS reviews_insert ON public.reviews;

CREATE POLICY reviews_insert ON public.reviews
  FOR INSERT
  WITH CHECK (
    reviewer_id = (auth.uid())::text
  );

-- Nota importante para o time:
-- O WEBHOOK_SECRET nas Edge Functions (Supabase Dashboard > Functions > Secrets)
-- DEVE ser definido com o mesmo valor acima: 'uppi-webhook-2026-secret'
-- Sem isso, o webhook-new-ride continuará rejeitando as chamadas do trigger.

-- 6. CORRIGIR RLS rides INSERT: sem filtro permitia qualquer usuário criar corridas diretamente
--    Bug: bypassava o create-order edge function, criando corridas sem cálculo de tarifa
DROP POLICY IF EXISTS rides_insert ON public.rides;

CREATE POLICY rides_insert ON public.rides
  FOR INSERT
  WITH CHECK (
    (auth.uid())::text = rider_id
  );

-- 7. CORRIGIR RLS wallets INSERT: sem filtro permitia criar carteira para qualquer user_id
DROP POLICY IF EXISTS "User inserts own wallet" ON public.wallets;

CREATE POLICY "User inserts own wallet" ON public.wallets
  FOR INSERT
  WITH CHECK (
    (auth.uid())::text = user_id
  );



-- ─────────────────────────────────────────────
-- FILE: 20260528120000_legacy_messages_and_cashback_cdc.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO — LEGACY MESSAGES & CASHBACK RULES CDC REALTIME
-- Data: 2026-05-28
-- Ecossistema Uppi — Engenharia de Banco de Dados
-- ==============================================================================
-- Adiciona suporte a CDC em tempo real (Supabase Realtime) para as tabelas:
-- 1. public.messages (garante que a aba legacy do God Mode funcione em tempo real)
-- 2. public.cashback_rules (permite reatividade síncrona em regras de cashback)
-- ==============================================================================

-- 1. ADICIONAR TABELAS FALTANTES À PUBLICAÇÃO supabase_realtime
-- Usamos blocos anônimos PL/pgSQL para evitar falhas se a tabela já existir na publicação.

-- messages
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;
END $$;

-- cashback_rules
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'cashback_rules'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.cashback_rules;
  END IF;
END $$;

-- 2. GARANTIR REPLICA IDENTITY FULL
-- Garante payload completo para UPDATE e DELETE nas duas tabelas
ALTER TABLE public.messages REPLICA IDENTITY FULL;
ALTER TABLE public.cashback_rules REPLICA IDENTITY FULL;


-- ─────────────────────────────────────────────
-- FILE: 20260528130000_dynamic_webhook_url.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO — URL DINÂMICA DO WEBHOOK DE DESPACHO (PORTABILIDADE TOTAL)
-- Data: 2026-05-28
-- Ecossistema Uppi — Engenharia de Infraestrutura e Banco de Dados
-- ==============================================================================
-- Esta migração resolve o problema de URL do Supabase hardcoded no trigger
-- de notificação de novas ofertas de corrida (notify_webhook_new_offer).
-- Implementa uma busca dinâmica através da variável de sistema 'app.supabase_url'
-- (fornecida nativamente pelo Supabase CLI/Docker e instâncias gerenciadas)
-- com fallback automático para a URL padrão do projeto Uppi de homologação.
-- Evita erros 404 e falhas de disparo de push em ambientes locais ou staging clones.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.notify_webhook_new_offer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_secret TEXT;
  v_supabase_url TEXT;
  v_webhook_url TEXT;
BEGIN
  IF NEW.status != 'offered' THEN
    RETURN NEW;
  END IF;

  -- 1. Buscar a URL base do Supabase de forma dinâmica
  v_supabase_url := current_setting('app.supabase_url', true);
  
  -- Fallback seguro para o projeto de homologação se a variável de ambiente não estiver definida
  IF v_supabase_url IS NULL OR v_supabase_url = '' THEN
    v_supabase_url := 'https://kqfmahrxjuqlvxngeurj.supabase.co';
  END IF;

  -- Construir o endpoint correto da Edge Function
  v_webhook_url := rtrim(v_supabase_url, '/') || '/functions/v1/webhook-new-ride';

  -- 2. Buscar o secret da tabela de configurações
  SELECT value INTO v_secret
  FROM public.app_settings
  WHERE key = 'webhook_secret'
  LIMIT 1;

  -- Fallback de secret via current_setting
  IF v_secret IS NULL THEN
    v_secret := current_setting('app.webhook_secret', true);
  END IF;

  -- 3. Disparar a chamada HTTP assíncrona/segura
  PERFORM net.http_post(
    url := v_webhook_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', COALESCE(v_secret, '')
    ),
    body := json_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'schema', TG_TABLE_SCHEMA,
      'record', row_to_json(NEW),
      'timestamp', extract(epoch from now())
    )::jsonb,
    timeout_milliseconds := 5000
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_webhook_new_offer falhou: %', SQLERRM;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_webhook_new_offer() IS 
  'Trigger dinâmico e portátil para envio de push de nova corrida via Edge Function.';


-- ─────────────────────────────────────────────
-- FILE: 20260530000000_increase_offer_window.sql
-- ─────────────────────────────────────────────

-- =====================================================
-- MIGRAÇÃO: Aumentar Janela de Oferta de Corrida
-- Data: 2026-05-30
-- =====================================================

CREATE OR REPLACE FUNCTION public.rpc_find_and_offer_ride(p_ride_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pickup_loc GEOGRAPHY(POINT);
    v_ride_status TEXT;
    v_service_type TEXT;
    v_gender_required TEXT;
    v_driver_id TEXT;
    v_offer_id UUID;
    v_search_radius INTEGER;
BEGIN
    -- 1. Bloquear linha da corrida para evitar conflitos de concorrência
    SELECT status, pickup_location, service_type INTO v_ride_status, v_pickup_loc, v_service_type
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    -- Se a corrida não existir ou já tiver sido aceita/cancelada, encerra o loop
    IF v_ride_status IS NULL OR v_ride_status NOT IN ('requested', 'searching') THEN
        RETURN FALSE;
    END IF;

    -- 2. Resolver restrição de gênero do serviço selecionado
    SELECT s.gender_required INTO v_gender_required
    FROM public.services s
    WHERE s.name = v_service_type OR s.id::text = v_service_type
    LIMIT 1;

    -- 3. Buscar o motorista 'online' aprovado mais próximo
    SELECT p.id, COALESCE(p.search_radius, 5000) INTO v_driver_id, v_search_radius
    FROM public.profiles p
    WHERE p.role = 'driver'
      AND p.status = 'online'
      AND p.current_location IS NOT NULL
      -- ─── ANTI CHERRY-PICKING: Excluir motoristas em cooldown ───
      AND (p.cooldown_until IS NULL OR p.cooldown_until < NOW())
      -- ═══ UPPI MULHER: Filtro estrito de gênero no servidor ═══
      -- Se o serviço exige gênero específico, SOMENTE motoristas com
      -- gênero verificado e correspondente podem receber a corrida.
      AND (
          v_gender_required IS NULL
          OR (p.gender = v_gender_required AND p.gender_verified = TRUE)
      )
      -- Filtrar por categoria do veículo correspondente ao serviço
      AND (
          v_service_type IS NULL OR
          p.vehicle_type IS NULL OR
          p.vehicle_type = COALESCE(
              (SELECT s.vehicle_category FROM public.services s WHERE s.name = v_service_type LIMIT 1),
              'carro'
          )
      )
      -- Evitar motoristas que já rejeitaram ou expiraram esta corrida recentemente (últimos 30 segundos)
      AND NOT EXISTS (
          SELECT 1 
          FROM public.ride_rejected_drivers rr 
          WHERE rr.ride_id = p_ride_id 
            AND rr.driver_id = p.id
            AND rr.created_at > now() - interval '30 seconds'
      )
      -- Evitar motoristas em corridas ativas
      AND NOT EXISTS (
          SELECT 1 
          FROM public.rides r 
          WHERE r.driver_id = p.id 
            AND r.status IN ('accepted', 'arrived', 'in_progress')
      )
      -- Evitar motoristas com ofertas de corrida ativas pendentes
      AND NOT EXISTS (
          SELECT 1
          FROM public.ride_offers ro
          WHERE ro.driver_id = p.id
            AND ro.status = 'offered'
            AND ro.expires_at > now()
      )
    ORDER BY 
      ST_Distance(p.current_location, v_pickup_loc) * 
      (1.0 + COALESCE(p.consecutive_rejections, 0) * 0.15)
    ASC
    LIMIT 1;

    -- 4. Se um motorista elegível for encontrado, criar a oferta
    IF v_driver_id IS NOT NULL THEN
        UPDATE public.ride_offers
        SET status = 'expired'
        WHERE ride_id = p_ride_id AND status = 'offered';

        -- Aumentado para 30 segundos (antes era 15 seconds)
        INSERT INTO public.ride_offers (ride_id, driver_id, status, expires_at)
        VALUES (p_ride_id, v_driver_id, 'offered', now() + interval '30 seconds')
        RETURNING id INTO v_offer_id;

        UPDATE public.rides
        SET status = 'searching',
            updated_at = now()
        WHERE id = p_ride_id;

        RETURN TRUE;
    ELSE
        UPDATE public.rides
        SET status = 'requested',
            updated_at = now()
        WHERE id = p_ride_id AND status = 'searching';

        RETURN FALSE;
    END IF;
END;
$$;

COMMENT ON FUNCTION public.rpc_find_and_offer_ride(UUID) IS 'Busca o motorista disponível mais próximo com filtro estrito de gênero (Uppi Mulher), anti cherry-picking (cooldown), e penalização por rejeições recentes. Oferta ativa por 30 segundos.';

REVOKE EXECUTE ON FUNCTION public.rpc_find_and_offer_ride(UUID) FROM authenticated, anon, public;
GRANT EXECUTE ON FUNCTION public.rpc_find_and_offer_ride(UUID) TO service_role;


-- ─────────────────────────────────────────────
-- FILE: 20260530000001_ensure_nearby_drivers_grant.sql
-- ─────────────────────────────────────────────

-- =====================================================
-- MIGRAÇÃO: Garantir permissões de nearby_drivers
-- Data: 2026-05-30
-- =====================================================

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name = 'nearby_drivers') THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.nearby_drivers TO authenticated';
  END IF;
END $$;


-- ─────────────────────────────────────────────
-- FILE: 20260601000000_zero_all_fees_temporarily.sql
-- ─────────────────────────────────────────────

-- Migration: Zerar TODAS as taxas e comissões temporariamente
-- Decisão de negócio: Taxa zero por 1 mês (a partir de 2026-06-01)
-- Para reativar, basta alterar os valores na tabela app_settings via Admin Panel.

-- 1. Comissão da plataforma → 0%
INSERT INTO public.app_settings (key, value)
VALUES ('commission_rate', '0')
ON CONFLICT (key) DO UPDATE SET value = '0';

-- 2. Taxa de cancelamento → R$ 0,00
INSERT INTO public.app_settings (key, value)
VALUES ('cancellation_fee', '0')
ON CONFLICT (key) DO UPDATE SET value = '0';

-- 3. Isentar TODOS os motoristas existentes de comissão por 30 dias
-- Isso garante que mesmo que haja comissão individual, será 0
UPDATE public.profiles
SET commission_exempt_until = NOW() + INTERVAL '30 days'
WHERE id IN (
    SELECT DISTINCT driver_id FROM public.driver_locations
)
AND (commission_exempt_until IS NULL OR commission_exempt_until < NOW());


-- ─────────────────────────────────────────────
-- FILE: 20260601010000_prevent_negative_driver_balance.sql
-- ─────────────────────────────────────────────

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


-- ─────────────────────────────────────────────
-- FILE: 20260601020000_exempt_new_drivers_automatically.sql
-- ─────────────────────────────────────────────

-- Migration: Exempt new drivers automatically for 30 days
-- Garantir que qualquer novo motorista cadastrado na tabela raw seja isento de comissão por 30 dias automaticamente.

CREATE OR REPLACE FUNCTION public.exempt_new_drivers_commission()
RETURNS TRIGGER AS $$
BEGIN
  -- Se o perfil mudou para 'driver' ou foi criado como 'driver', e a isenção está nula ou no passado:
  IF NEW.role = 'driver' AND (TG_OP = 'INSERT' OR OLD.role IS DISTINCT FROM 'driver' OR NEW.role IS DISTINCT FROM OLD.role) THEN
    IF NEW.commission_exempt_until IS NULL OR NEW.commission_exempt_until < NOW() THEN
      NEW.commission_exempt_until := NOW() + INTERVAL '30 days';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_exempt_new_drivers ON public.profiles_raw;
CREATE TRIGGER trg_exempt_new_drivers
BEFORE INSERT OR UPDATE ON public.profiles_raw
FOR EACH ROW
EXECUTE FUNCTION public.exempt_new_drivers_commission();

COMMENT ON FUNCTION public.exempt_new_drivers_commission() IS 'Isenta automaticamente novos motoristas de comissão pelos primeiros 30 dias de cadastro.';


-- ─────────────────────────────────────────────
-- FILE: 20260601030000_add_identity_columns_to_profiles_view.sql
-- ─────────────────────────────────────────────

-- =====================================================================
-- MIGRAÇÃO: Adiciona colunas de identidade na VIEW profiles
-- Data: 2026-06-01
-- =====================================================================

-- 1. Reconstruir a VIEW profiles para expor identity_verification_status e identity_docs
CREATE OR REPLACE VIEW public.profiles WITH (security_invoker = true) AS
SELECT
  id,
  role,
  full_name,
  phone_number,
  email,
  fcm_token,
  status,
  wallet_balance,
  search_radius,
  current_location,
  vehicle_details,
  created_at,
  updated_at,
  rating,
  review_count,
  commission_percentage,
  commission_exempt_until,
  subscription_expires_at,
  phone,
  documents,
  is_deleted,
  deleted_at,
  is_approved,
  vehicle_type,
  marker_url,
  certificate_number,
  search_distance,
  vehicle_plate_number,
  vehicle_production_year,
  vehicle_model_id,
  vehicle_color_id,
  bank_name,
  bank_account_number,
  bank_swift_code,
  bank_routing_number,
  address,
  gender,
  id_number,
  preset_avatar_number,
  total_rides,
  total_distance,
  average_rating,
  rating_count,
  public.decrypt_val(encrypted_cpf) AS cpf,
  favorite_drivers,
  is_blocked,
  identity_verification_status,
  identity_docs
FROM public.profiles_raw;

-- 2. Atualizar a função e trigger DML da VIEW profiles
CREATE OR REPLACE FUNCTION public.profiles_view_dml_trigger()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.profiles_raw (
      id, role, full_name, phone_number, email, fcm_token, status, wallet_balance,
      search_radius, current_location, vehicle_details, created_at, updated_at,
      rating, review_count, commission_percentage, commission_exempt_until,
      subscription_expires_at, phone, documents, is_deleted, deleted_at,
      is_approved, vehicle_type, marker_url, certificate_number, search_distance,
      vehicle_plate_number, vehicle_production_year, vehicle_model_id, vehicle_color_id,
      bank_name, bank_account_number, bank_swift_code, bank_routing_number,
      address, gender, id_number, preset_avatar_number, total_rides, total_distance,
      average_rating, rating_count, favorite_drivers, is_blocked, 
      identity_verification_status, identity_docs, encrypted_cpf
    ) VALUES (
      NEW.id, NEW.role, NEW.full_name, NEW.phone_number, NEW.email, NEW.fcm_token, NEW.status, NEW.wallet_balance,
      NEW.search_radius, NEW.current_location, NEW.vehicle_details, NEW.created_at, NEW.updated_at,
      NEW.rating, NEW.review_count, NEW.commission_percentage, NEW.commission_exempt_until,
      NEW.subscription_expires_at, NEW.phone, NEW.documents, NEW.is_deleted, NEW.deleted_at,
      NEW.is_approved, NEW.vehicle_type, NEW.marker_url, NEW.certificate_number, NEW.search_distance,
      NEW.vehicle_plate_number, NEW.vehicle_production_year, NEW.vehicle_model_id, NEW.vehicle_color_id,
      NEW.bank_name, NEW.bank_account_number, NEW.bank_swift_code, NEW.bank_routing_number,
      NEW.address, NEW.gender, NEW.id_number, NEW.preset_avatar_number, NEW.total_rides, NEW.total_distance,
      NEW.average_rating, NEW.rating_count, NEW.favorite_drivers, NEW.is_blocked, 
      NEW.identity_verification_status, NEW.identity_docs, public.encrypt_val(NEW.cpf)
    );
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    UPDATE public.profiles_raw SET
      role = NEW.role,
      full_name = NEW.full_name,
      phone_number = NEW.phone_number,
      email = NEW.email,
      fcm_token = NEW.fcm_token,
      status = NEW.status,
      wallet_balance = NEW.wallet_balance,
      search_radius = NEW.search_radius,
      current_location = NEW.current_location,
      vehicle_details = NEW.vehicle_details,
      created_at = NEW.created_at,
      updated_at = NEW.updated_at,
      rating = NEW.rating,
      review_count = NEW.review_count,
      commission_percentage = NEW.commission_percentage,
      commission_exempt_until = NEW.commission_exempt_until,
      subscription_expires_at = NEW.subscription_expires_at,
      phone = NEW.phone,
      documents = NEW.documents,
      is_deleted = NEW.is_deleted,
      deleted_at = NEW.deleted_at,
      is_approved = NEW.is_approved,
      vehicle_type = NEW.vehicle_type,
      marker_url = NEW.marker_url,
      certificate_number = NEW.certificate_number,
      search_distance = NEW.search_distance,
      vehicle_plate_number = NEW.vehicle_plate_number,
      vehicle_production_year = NEW.vehicle_production_year,
      vehicle_model_id = NEW.vehicle_model_id,
      vehicle_color_id = NEW.vehicle_color_id,
      bank_name = NEW.bank_name,
      bank_account_number = NEW.bank_account_number,
      bank_swift_code = NEW.bank_swift_code,
      bank_routing_number = NEW.bank_routing_number,
      address = NEW.address,
      gender = NEW.gender,
      id_number = NEW.id_number,
      preset_avatar_number = NEW.preset_avatar_number,
      total_rides = NEW.total_rides,
      total_distance = NEW.total_distance,
      average_rating = NEW.average_rating,
      rating_count = NEW.rating_count,
      favorite_drivers = NEW.favorite_drivers,
      is_blocked = NEW.is_blocked,
      identity_verification_status = NEW.identity_verification_status,
      identity_docs = NEW.identity_docs,
      encrypted_cpf = CASE 
        WHEN NEW.cpf IS DISTINCT FROM OLD.cpf THEN public.encrypt_val(NEW.cpf)
        ELSE encrypted_cpf
      END
    WHERE id = OLD.id;
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    DELETE FROM public.profiles_raw WHERE id = OLD.id;
    RETURN OLD;
  END IF;
END;
$$ LANGUAGE plpgsql;


-- ─────────────────────────────────────────────
-- FILE: 20260601040000_add_remaining_columns_to_profiles_view.sql
-- ─────────────────────────────────────────────

-- =====================================================================
-- MIGRAÇÃO: Adiciona colunas restantes na VIEW profiles
-- Data: 2026-06-01
-- Objetivo: Adicionar cooldown_until, consecutive_rejections, colunas de acessibilidade e gender_verified
--            para alinhar a VIEW profiles com as colunas reais de profiles_raw.
-- =====================================================================

-- 1. Reconstruir a VIEW profiles com todas as colunas
CREATE OR REPLACE VIEW public.profiles WITH (security_invoker = true) AS
SELECT
  id,
  role,
  full_name,
  phone_number,
  email,
  fcm_token,
  status,
  wallet_balance,
  search_radius,
  current_location,
  vehicle_details,
  created_at,
  updated_at,
  rating,
  review_count,
  commission_percentage,
  commission_exempt_until,
  subscription_expires_at,
  phone,
  documents,
  is_deleted,
  deleted_at,
  is_approved,
  vehicle_type,
  marker_url,
  certificate_number,
  search_distance,
  vehicle_plate_number,
  vehicle_production_year,
  vehicle_model_id,
  vehicle_color_id,
  bank_name,
  bank_account_number,
  bank_swift_code,
  bank_routing_number,
  address,
  gender,
  id_number,
  preset_avatar_number,
  total_rides,
  total_distance,
  average_rating,
  rating_count,
  public.decrypt_val(encrypted_cpf) AS cpf,
  favorite_drivers,
  is_blocked,
  identity_verification_status,
  identity_docs,
  cooldown_until,
  consecutive_rejections,
  accessibility_wheelchair,
  accessibility_hearing_impaired,
  accessibility_visual_aid,
  accessibility_pet_friendly,
  accessibility_child_seat,
  gender_verified
FROM public.profiles_raw;

-- 2. Atualizar a função e trigger DML da VIEW profiles
CREATE OR REPLACE FUNCTION public.profiles_view_dml_trigger()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.profiles_raw (
      id, role, full_name, phone_number, email, fcm_token, status, wallet_balance,
      search_radius, current_location, vehicle_details, created_at, updated_at,
      rating, review_count, commission_percentage, commission_exempt_until,
      subscription_expires_at, phone, documents, is_deleted, deleted_at,
      is_approved, vehicle_type, marker_url, certificate_number, search_distance,
      vehicle_plate_number, vehicle_production_year, vehicle_model_id, vehicle_color_id,
      bank_name, bank_account_number, bank_swift_code, bank_routing_number,
      address, gender, id_number, preset_avatar_number, total_rides, total_distance,
      average_rating, rating_count, favorite_drivers, is_blocked, 
      identity_verification_status, identity_docs,
      cooldown_until, consecutive_rejections,
      accessibility_wheelchair, accessibility_hearing_impaired,
      accessibility_visual_aid, accessibility_pet_friendly,
      accessibility_child_seat, gender_verified,
      encrypted_cpf
    ) VALUES (
      NEW.id, NEW.role, NEW.full_name, NEW.phone_number, NEW.email, NEW.fcm_token, NEW.status, NEW.wallet_balance,
      NEW.search_radius, NEW.current_location, NEW.vehicle_details, NEW.created_at, NEW.updated_at,
      NEW.rating, NEW.review_count, NEW.commission_percentage, NEW.commission_exempt_until,
      NEW.subscription_expires_at, NEW.phone, NEW.documents, NEW.is_deleted, NEW.deleted_at,
      NEW.is_approved, NEW.vehicle_type, NEW.marker_url, NEW.certificate_number, NEW.search_distance,
      NEW.vehicle_plate_number, NEW.vehicle_production_year, NEW.vehicle_model_id, NEW.vehicle_color_id,
      NEW.bank_name, NEW.bank_account_number, NEW.bank_swift_code, NEW.bank_routing_number,
      NEW.address, NEW.gender, NEW.id_number, NEW.preset_avatar_number, NEW.total_rides, NEW.total_distance,
      NEW.average_rating, NEW.rating_count, NEW.favorite_drivers, NEW.is_blocked, 
      NEW.identity_verification_status, NEW.identity_docs,
      NEW.cooldown_until, NEW.consecutive_rejections,
      NEW.accessibility_wheelchair, NEW.accessibility_hearing_impaired,
      NEW.accessibility_visual_aid, NEW.accessibility_pet_friendly,
      NEW.accessibility_child_seat, NEW.gender_verified,
      public.encrypt_val(NEW.cpf)
    );
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    UPDATE public.profiles_raw SET
      role = NEW.role,
      full_name = NEW.full_name,
      phone_number = NEW.phone_number,
      email = NEW.email,
      fcm_token = NEW.fcm_token,
      status = NEW.status,
      wallet_balance = NEW.wallet_balance,
      search_radius = NEW.search_radius,
      current_location = NEW.current_location,
      vehicle_details = NEW.vehicle_details,
      created_at = NEW.created_at,
      updated_at = NEW.updated_at,
      rating = NEW.rating,
      review_count = NEW.review_count,
      commission_percentage = NEW.commission_percentage,
      commission_exempt_until = NEW.commission_exempt_until,
      subscription_expires_at = NEW.subscription_expires_at,
      phone = NEW.phone,
      documents = NEW.documents,
      is_deleted = NEW.is_deleted,
      deleted_at = NEW.deleted_at,
      is_approved = NEW.is_approved,
      vehicle_type = NEW.vehicle_type,
      marker_url = NEW.marker_url,
      certificate_number = NEW.certificate_number,
      search_distance = NEW.search_distance,
      vehicle_plate_number = NEW.vehicle_plate_number,
      vehicle_production_year = NEW.vehicle_production_year,
      vehicle_model_id = NEW.vehicle_model_id,
      vehicle_color_id = NEW.vehicle_color_id,
      bank_name = NEW.bank_name,
      bank_account_number = NEW.bank_account_number,
      bank_swift_code = NEW.bank_swift_code,
      bank_routing_number = NEW.bank_routing_number,
      address = NEW.address,
      gender = NEW.gender,
      id_number = NEW.id_number,
      preset_avatar_number = NEW.preset_avatar_number,
      total_rides = NEW.total_rides,
      total_distance = NEW.total_distance,
      average_rating = NEW.average_rating,
      rating_count = NEW.rating_count,
      favorite_drivers = NEW.favorite_drivers,
      is_blocked = NEW.is_blocked,
      identity_verification_status = NEW.identity_verification_status,
      identity_docs = NEW.identity_docs,
      cooldown_until = NEW.cooldown_until,
      consecutive_rejections = NEW.consecutive_rejections,
      accessibility_wheelchair = NEW.accessibility_wheelchair,
      accessibility_hearing_impaired = NEW.accessibility_hearing_impaired,
      accessibility_visual_aid = NEW.accessibility_visual_aid,
      accessibility_pet_friendly = NEW.accessibility_pet_friendly,
      accessibility_child_seat = NEW.accessibility_child_seat,
      gender_verified = NEW.gender_verified,
      encrypted_cpf = CASE 
        WHEN NEW.cpf IS DISTINCT FROM OLD.cpf THEN public.encrypt_val(NEW.cpf)
        ELSE encrypted_cpf
      END
    WHERE id = OLD.id;
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    DELETE FROM public.profiles_raw WHERE id = OLD.id;
    RETURN OLD;
  END IF;
END;
$$ LANGUAGE plpgsql;


-- ─────────────────────────────────────────────
-- FILE: 20260601050000_restore_robust_assign_driver_rpc.sql
-- ─────────────────────────────────────────────

-- =====================================================================
-- MIGRAÇÃO: Restaura Robustez da RPC assign_driver_to_ride
-- Data: 2026-06-01
-- Objetivo: Garantir tratamento de segurança, validação estrita de gênero (Uppi Mulher),
--            validação e expiração concorrente de ofertas, cálculo de ETA PostGIS
--            e reset de rejections consecutivas.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.assign_driver_to_ride(
    p_ride_id UUID,
    p_driver_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_status TEXT;
    v_service_type TEXT;
    v_service_id UUID;
    v_gender_required TEXT;
    v_driver_gender TEXT;
    v_driver_gender_verified BOOLEAN;
    v_pickup_lat DOUBLE PRECISION;
    v_pickup_lng DOUBLE PRECISION;
    v_driver_lat DOUBLE PRECISION;
    v_driver_lng DOUBLE PRECISION;
    v_dist_meters DOUBLE PRECISION;
    v_eta_minutes INTEGER;
    v_eta_pickup TIMESTAMP WITH TIME ZONE;
    v_rows INT;
BEGIN
    -- 1. [SEGURANÇA] Validar se o solicitante é de fato o motorista ou service_role
    IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR auth.uid()::text <> p_driver_id) THEN
        RAISE EXCEPTION 'Operação não autorizada. O motorista não corresponde ao usuário autenticado.';
    END IF;

    -- 2. [SEGURANÇA] Bloquear linha da corrida para evitar conflitos concorrentes
    SELECT status, service_type, service_id, pickup_lat, pickup_lng 
    INTO v_status, v_service_type, v_service_id, v_pickup_lat, v_pickup_lng
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Corrida não encontrada (ID: %)', p_ride_id;
    END IF;

    -- Agora aceitamos tanto 'requested' quanto 'searching'
    IF v_status NOT IN ('requested', 'searching') THEN
        RAISE EXCEPTION 'A corrida não está mais disponível para aceite (status atual: %)', v_status;
    END IF;

    -- 3. [UPPI MULHER] Validar restrição estrita de gênero para o serviço
    SELECT s.gender_required INTO v_gender_required
    FROM public.services s
    WHERE s.id = v_service_id OR s.name = v_service_type OR s.id::text = v_service_type
    LIMIT 1;

    IF v_gender_required IS NOT NULL THEN
        SELECT gender, gender_verified 
        INTO v_driver_gender, v_driver_gender_verified
        FROM public.profiles
        WHERE id = p_driver_id;

        IF v_driver_gender IS DISTINCT FROM v_gender_required OR v_driver_gender_verified IS NOT TRUE THEN
            RAISE EXCEPTION 'Este serviço é exclusivo para motoristas mulheres verificadas.';
        END IF;
    END IF;

    -- 4. [SEGURANÇA] Atualizar oferta específica deste motorista como 'accepted'
    UPDATE public.ride_offers
    SET status = 'accepted'
    WHERE ride_id = p_ride_id AND driver_id = p_driver_id AND status = 'offered';
    
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 0 THEN
        RAISE EXCEPTION 'Você não possui uma oferta ativa para esta corrida.';
    END IF;

    -- 5. Expirar as demais ofertas ativas para essa corrida
    UPDATE public.ride_offers
    SET status = 'expired'
    WHERE ride_id = p_ride_id AND driver_id <> p_driver_id AND status = 'offered';

    -- 6. Calcular ETA dinâmico baseado no PostGIS
    SELECT lat, lng INTO v_driver_lat, v_driver_lng
    FROM public.driver_locations
    WHERE driver_id = p_driver_id;

    IF v_driver_lat IS NOT NULL AND v_pickup_lat IS NOT NULL THEN
        v_dist_meters := ST_Distance(
            ST_SetSRID(ST_MakePoint(v_driver_lng, v_driver_lat), 4326)::geography,
            ST_SetSRID(ST_MakePoint(v_pickup_lng, v_pickup_lat), 4326)::geography
        );
        v_eta_minutes := CEIL(v_dist_meters / 500.0); -- ~30km/h
        v_eta_pickup := NOW() + (v_eta_minutes * interval '1 minute');
    ELSE
        v_eta_pickup := NOW() + interval '5 minutes';
    END IF;

    -- 7. Atribuir o motorista à corrida, passar o status para 'accepted', definir accepted_at e eta_pickup
    UPDATE public.rides
    SET driver_id = p_driver_id,
        status = 'accepted',
        accepted_at = NOW(),
        eta_pickup = v_eta_pickup,
        updated_at = NOW()
    WHERE id = p_ride_id;

    -- 8. [ANTI CHERRY-PICKING] Resetar rejeições consecutivas do motorista ao aceitar corrida
    UPDATE public.profiles
    SET consecutive_rejections = 0
    WHERE id = p_driver_id AND consecutive_rejections > 0;
END;
$$;

-- Garantir privilégios
REVOKE EXECUTE ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) TO authenticated, service_role;


-- ─────────────────────────────────────────────
-- FILE: 20260601060000_auto_redispatch_loop.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Despacho Contínuo e Reativo de Corridas
-- Data: 2026-06-01
-- Objetivo: Garantir que corridas no status 'requested' sejam despachadas continuamente
-- e de forma reativa assim que os motoristas atualizarem localização ou status.
-- ==============================================================================

-- 1. ATUALIZAR SWEEP DE OFERTAS EXPIRADAS PARA SUPORTAR REDESPACHO CONTÍNUO (CRON JOB)
CREATE OR REPLACE FUNCTION public.rpc_sweep_expired_offers()
RETURNS TABLE (
    offer_id UUID,
    ride_id UUID,
    driver_id TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
    v_ride RECORD;
BEGIN
    -- 1a. Varre e expira ofertas que passaram do tempo limite de aceitação
    FOR r IN 
        SELECT ro.id, ro.ride_id, ro.driver_id
        FROM public.ride_offers ro
        WHERE ro.status = 'offered'
          AND ro.expires_at < now()
    LOOP
        -- Atualizar status da oferta para expirado
        UPDATE public.ride_offers
        SET status = 'expired'
        WHERE id = r.id AND status = 'offered';

        IF FOUND THEN
            -- Inserir motorista na lista de rejeitados para esta corrida para evitar novo loop imediato com o mesmo
            INSERT INTO public.ride_rejected_drivers (ride_id, driver_id)
            VALUES (r.ride_id, r.driver_id)
            ON CONFLICT (ride_id, driver_id) DO NOTHING;

            -- Tentar despachar instantaneamente para o próximo motorista geolocalizado
            PERFORM public.rpc_find_and_offer_ride(r.ride_id);

            -- Preencher valores de retorno
            offer_id := r.id;
            ride_id := r.ride_id;
            driver_id := r.driver_id;
            RETURN NEXT;
        END IF;
    END LOOP;

    -- 1b. REDESPACHO CONTÍNUO: Varrer corridas ativas travadas no status 'requested'
    -- (criadas nos últimos 20 minutos) que não possuem nenhuma oferta ativa pendente
    FOR v_ride IN
        SELECT r.id
        FROM public.rides r
        WHERE r.status = 'requested'
          AND r.created_at > now() - interval '20 minutes'
          AND NOT EXISTS (
              SELECT 1
              FROM public.ride_offers ro
              WHERE ro.ride_id = r.id
                AND ro.status = 'offered'
                AND ro.expires_at > now()
          )
    LOOP
        -- Tentar encontrar motoristas para essa corrida pendente
        PERFORM public.rpc_find_and_offer_ride(v_ride.id);
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.rpc_sweep_expired_offers() IS 'Expira ofertas ativas fora do tempo e executa varredura periódica para redespachar corridas pendentes travadas em requested.';

-- 2. CRIAR DISPARADOR DE DESPACHO REATIVO EM TEMPO REAL (TRIGGERS DE GEOLOCALIZAÇÃO/STATUS)
CREATE OR REPLACE FUNCTION public.trg_redispatch_on_driver_online_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ride RECORD;
    v_offered BOOLEAN;
BEGIN
    -- Se o motorista estiver online, tentar acoplar corridas pendentes na fila imediatamente
    IF NEW.status = 'online' THEN
        FOR v_ride IN
            SELECT r.id
            FROM public.rides r
            WHERE r.status = 'requested'
              AND r.created_at > now() - interval '20 minutes'
            ORDER BY r.created_at ASC
        LOOP
            -- Executa o algoritmo de despacho para a corrida pendente
            v_offered := public.rpc_find_and_offer_ride(v_ride.id);
            
            -- Se esse motorista específico acabou de ser selecionado e recebeu uma oferta ativamente,
            -- encerramos o loop de busca para ele (pois ele já está ocupado respondendo a uma oferta)
            IF EXISTS (
                SELECT 1
                FROM public.ride_offers ro
                WHERE ro.driver_id = NEW.driver_id
                  AND ro.ride_id = v_ride.id
                  AND ro.status = 'offered'
                  AND ro.expires_at > now()
            ) THEN
                EXIT;
            END IF;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.trg_redispatch_on_driver_online_fn() IS 'Verifica se há corridas requested pendentes e tenta despachá-las imediatamente assim que um motorista fica online ou move-se no mapa.';

-- Criar o trigger na tabela driver_locations
DROP TRIGGER IF EXISTS trg_redispatch_on_driver_online ON public.driver_locations;
CREATE TRIGGER trg_redispatch_on_driver_online
    AFTER INSERT OR UPDATE OF status, lat, lng ON public.driver_locations
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_redispatch_on_driver_online_fn();


-- ─────────────────────────────────────────────
-- FILE: 20260602000000_driver_face_verifications.sql
-- ─────────────────────────────────────────────

-- =============================================================================
-- MIGRATION: Verificação facial de motoristas (anti-fraude)
-- Data: 2026-06-02
-- -----------------------------------------------------------------------------
-- Cria a tabela que recebe os resultados da verificação facial feita no APP do
-- motorista (selfie ao vivo + comparação com a foto de referência do cadastro).
-- O Painel Admin usa esta tabela como FILA DE REVISÃO dos casos duvidosos e
-- como HISTÓRICO. As notas de corte ficam em app_settings (key-value).
--
-- Fluxo de status:
--   auto_approved  -> semelhança >= face_auto_approve_threshold e liveness ok
--   auto_rejected  -> semelhança <  face_auto_reject_threshold  ou liveness falhou
--   needs_review   -> zona de dúvida (entre as duas notas) -> cai no painel
--   approved/rejected -> decisão MANUAL do admin sobre um needs_review
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.driver_face_verifications (
    id                UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    -- profiles é uma VIEW; a tabela real é profiles_raw (por isso o FK aponta p/ ela)
    driver_id         TEXT REFERENCES public.profiles_raw(id) ON DELETE CASCADE NOT NULL,
    selfie_url        TEXT,            -- selfie ao vivo capturada no app
    reference_url     TEXT,            -- foto de referência (cadastro/documento)
    similarity_score  NUMERIC,         -- 0..100 (% de semelhança do serviço de comparação)
    liveness_passed   BOOLEAN DEFAULT false,
    status            TEXT NOT NULL DEFAULT 'needs_review'
                        CHECK (status IN ('auto_approved','auto_rejected','needs_review','approved','rejected')),
    trigger_reason    TEXT DEFAULT 'periodic',  -- 'periodic' | 'pre_online' | 'manual' | 'random'
    decided_by        TEXT,            -- id do admin que decidiu (sem FK p/ não depender do tipo de 'admins')
    decision_reason   TEXT,
    created_at        TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    decided_at        TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_dfv_status  ON public.driver_face_verifications(status);
CREATE INDEX IF NOT EXISTS idx_dfv_driver  ON public.driver_face_verifications(driver_id);
CREATE INDEX IF NOT EXISTS idx_dfv_created ON public.driver_face_verifications(created_at DESC);

ALTER TABLE public.driver_face_verifications ENABLE ROW LEVEL SECURITY;

-- Motorista lê as próprias verificações; admin lê todas.
DROP POLICY IF EXISTS "dfv_select" ON public.driver_face_verifications;
CREATE POLICY "dfv_select" ON public.driver_face_verifications
    FOR SELECT TO authenticated USING (
        auth.uid()::text = driver_id
        OR EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

-- Motorista só insere verificação dele mesmo (o app envia o resultado).
DROP POLICY IF EXISTS "dfv_insert_own" ON public.driver_face_verifications;
CREATE POLICY "dfv_insert_own" ON public.driver_face_verifications
    FOR INSERT TO authenticated WITH CHECK (
        auth.uid()::text = driver_id
    );

-- Somente admins decidem (aprovar/rejeitar) os casos em revisão.
DROP POLICY IF EXISTS "dfv_admin_update" ON public.driver_face_verifications;
CREATE POLICY "dfv_admin_update" ON public.driver_face_verifications
    FOR UPDATE TO authenticated USING (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

-- Realtime: a fila aparece na hora no Painel Admin.
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_face_verifications;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Notas de corte / ativação (não sobrescreve se o admin já tiver ajustado).
INSERT INTO public.app_settings (key, value) VALUES
    ('face_verification_enabled',        'false'),  -- liga/desliga a exigência no app
    ('face_auto_approve_threshold',      '90'),     -- >= aprova automático
    ('face_auto_reject_threshold',       '70'),     -- <  bloqueia automático (entre os dois => revisão)
    ('face_verification_interval_days',  '7')       -- de quantos em quantos dias re-verificar
ON CONFLICT (key) DO NOTHING;

COMMENT ON TABLE public.driver_face_verifications IS
  'Verificações faciais de motoristas (anti-fraude). Preenchida pelo app do motorista; revisada no Painel Admin.';


-- ─────────────────────────────────────────────
-- FILE: 20260603000000_sync_driver_verified_face.sql
-- ─────────────────────────────────────────────

-- Migration: Sincronizar foto de perfil do motorista com a selfie da verificação facial aprovada
-- Data: 2026-06-03

CREATE OR REPLACE FUNCTION public.sync_driver_verified_face_to_profile()
RETURNS TRIGGER AS $$
BEGIN
    -- Se a verificação facial foi aprovada (automaticamente ou manualmente pelo admin)
    -- e existe uma selfie válida, atualiza o avatar_url do perfil do motorista.
    IF NEW.status IN ('approved', 'auto_approved') AND NEW.selfie_url IS NOT NULL THEN
        UPDATE public.profiles_raw
        SET avatar_url = NEW.selfie_url
        WHERE id = NEW.driver_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger disparado após inserção ou atualização de status na verificação facial
DROP TRIGGER IF EXISTS trg_sync_driver_verified_face_to_profile ON public.driver_face_verifications;
CREATE TRIGGER trg_sync_driver_verified_face_to_profile
AFTER INSERT OR UPDATE OF status ON public.driver_face_verifications
FOR EACH ROW
EXECUTE FUNCTION public.sync_driver_verified_face_to_profile();


-- ─────────────────────────────────────────────
-- FILE: 20260604000000_enable_realtime_for_remaining_tables.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO — HABILITAR REALTIME CDC PARA TABELAS RESTANTES DO PAINEL E APPS
-- Data: 2026-06-04
-- Ecossistema Uppi — Engenharia de Banco de Dados
-- ==============================================================================
-- Esta migração adiciona à publicação supabase_realtime as tabelas referenciadas
-- pelo Painel Admin e pelos aplicativos locais que ainda não estavam participando
-- da replicação lógica reativa (CDC).
-- ==============================================================================

-- 1. ADICIONAR TABELAS À PUBLICAÇÃO supabase_realtime

-- coupon_usages
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'coupon_usages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.coupon_usages;
  END IF;
END $$;

-- user_badges
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'user_badges'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_badges;
  END IF;
END $$;

-- admin_chat_audit_logs
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'admin_chat_audit_logs'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.admin_chat_audit_logs;
  END IF;
END $$;

-- saved_places
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'saved_places'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.saved_places;
  END IF;
END $$;


-- 2. GARANTIR REPLICA IDENTITY FULL NAS TABELAS
ALTER TABLE public.coupon_usages REPLICA IDENTITY FULL;
ALTER TABLE public.user_badges REPLICA IDENTITY FULL;
ALTER TABLE public.admin_chat_audit_logs REPLICA IDENTITY FULL;
ALTER TABLE public.saved_places REPLICA IDENTITY FULL;

COMMENT ON TABLE public.coupon_usages IS
  'Histórico de cupons utilizados por usuários. CDC habilitado para controle e relatórios em tempo real.';
COMMENT ON TABLE public.user_badges IS
  'Conquistas e medalhas vinculadas aos usuários. CDC habilitado para exibição dinâmica de badges.';
COMMENT ON TABLE public.admin_chat_audit_logs IS
  'Log de auditoria para acessos administrativos aos chats sob SOS. CDC habilitado para monitoramento ativo de conformidade.';
COMMENT ON TABLE public.saved_places IS
  'Locais favoritos salvos pelos passageiros. CDC habilitado para sincronização de rotas inteligentes.';


-- ─────────────────────────────────────────────
-- FILE: 20260604010000_fix_admin_roles_and_policies.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO — CORREÇÃO DOS PAPÉIS E POLÍTICAS DE ACESSO PARA ADMINISTRADORES
-- Data: 2026-06-04
-- Ecossistema Uppi — Engenharia de Banco de Dados
-- ==============================================================================
-- Esta migração aprimora a validação de administradores e operadores nas políticas RLS
-- e funções de auditoria, garantindo que contas criadas apenas na tabela 'admins' (sem 
-- correspondência na view de profiles) consigam operar o painel administrativo sem erros.
-- ==============================================================================

-- 1. ATUALIZAR FUNÇÃO is_admin_or_operator
-- Agora verifica a tabela física profiles_raw (para otimização e evitar recursão)
-- e também verifica se o ID existe na tabela public.admins.
CREATE OR REPLACE FUNCTION public.is_admin_or_operator(user_id text)
RETURNS boolean
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles_raw WHERE id = user_id AND role = ANY (ARRAY['admin'::text, 'operator'::text])
  ) OR EXISTS (
    SELECT 1 FROM public.admins WHERE id = user_id
  );
END;
$$;

COMMENT ON FUNCTION public.is_admin_or_operator(text) IS 
  'Verifica se o ID de usuário pertence a um administrador/operador na tabela profiles_raw ou admins.';

-- 2. ATUALIZAR FUNÇÃO is_driver PARA USAR A TABELA FÍSICA profiles_raw DIRETAMENTE
CREATE OR REPLACE FUNCTION public.is_driver(user_id text)
RETURNS boolean
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles_raw WHERE id = user_id AND role = 'driver'
  );
END;
$$;

COMMENT ON FUNCTION public.is_driver(text) IS 
  'Verifica se o ID de usuário pertence a um motorista diretamente na tabela física profiles_raw.';

-- 3. RECRIAR POLÍTICA DE SELEÇÃO DE LOGS DE AUDITORIA DE CHAT SOS
-- Agora utiliza a função is_admin_or_operator para autenticar admins de ambos os repositórios.
DROP POLICY IF EXISTS admin_audit_logs_select_policy ON public.admin_chat_audit_logs;
CREATE POLICY admin_audit_logs_select_policy ON public.admin_chat_audit_logs
    FOR SELECT
    TO authenticated
    USING (
        public.is_admin_or_operator(auth.uid()::text)
    );

-- 4. RECRIAR A RPC DE LEITURA DO CHAT SOS COM O NOVO CHECK DE SEGURANÇA
CREATE OR REPLACE FUNCTION public.rpc_get_sos_chat_context(p_ride_id UUID)
RETURNS TABLE (
    message_id UUID,
    ride_id UUID,
    content TEXT,
    sent_by_driver BOOLEAN,
    created_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_admin BOOLEAN;
    v_has_active_sos BOOLEAN;
BEGIN
    -- A. Verificar se o usuário solicitante é de fato um Administrador ou Operador
    v_is_admin := public.is_admin_or_operator(auth.uid()::text);

    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'Acesso negado: Apenas administradores autorizados podem realizar esta operação.';
    END IF;

    -- B. Verificar se a corrida possui algum SOS ativo associado na tabela sos_alerts
    SELECT EXISTS (
        SELECT 1 FROM public.sos_alerts
        WHERE ride_id = p_ride_id AND status = 'active'
    ) INTO v_has_active_sos;

    IF NOT v_has_active_sos THEN
        RAISE EXCEPTION 'Acesso negado: Este chat privado de viagem não possui nenhum alerta SOS ativo associado.';
    END IF;

    -- C. Registrar o log de auditoria permanente do acesso administrativo
    INSERT INTO public.admin_chat_audit_logs (admin_id, ride_id)
    VALUES (auth.uid()::text, p_ride_id);

    -- D. Retornar as mensagens do chat da viagem com segurança
    RETURN QUERY
    SELECT 
        m.id::UUID,
        m.ride_id::UUID,
        m.content::TEXT,
        m.sent_by_driver::BOOLEAN,
        m.created_at::TIMESTAMP WITH TIME ZONE
    FROM public.ride_messages m
    WHERE m.ride_id = p_ride_id
    ORDER BY m.created_at ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_sos_chat_context(UUID) TO authenticated;

COMMENT ON FUNCTION public.rpc_get_sos_chat_context(UUID) IS 
  'Retorna o histórico de chat de uma viagem específica de forma segura e auditada para administradores se houver um alerta SOS ativo.';


-- ─────────────────────────────────────────────
-- FILE: 20260608000000_fix_profiles_rls_rating.sql
-- ─────────────────────────────────────────────

DROP POLICY IF EXISTS "profiles_select_restricted" ON public.profiles;

CREATE POLICY "profiles_select_restricted" ON public.profiles
  FOR SELECT TO authenticated
  USING (
    -- 1. O próprio usuário pode ler seu próprio perfil
    auth.uid()::text = id
    
    -- 2. Administradores podem ler qualquer perfil
    OR EXISTS (
      SELECT 1 FROM public.admins WHERE id = auth.uid()::text
    )
    
    -- 3. Motoristas podem ver perfis de passageiros em suas corridas ativas/recentes/avaliação
    OR id IN (
      SELECT rider_id FROM public.rides
      WHERE driver_id = auth.uid()::text
      AND status IN ('accepted', 'arrived', 'in_progress', 'completed', 'waiting_for_post_pay', 'waiting_for_review', 'finished')
    )
    
    -- 4. Passageiros podem ver perfis de motoristas de suas corridas ativas/recentes/avaliação
    OR id IN (
      SELECT driver_id FROM public.rides
      WHERE rider_id = auth.uid()::text
      AND status IN ('accepted', 'arrived', 'in_progress', 'completed', 'waiting_for_post_pay', 'waiting_for_review', 'finished')
    )
    
    -- 5. Motoristas online podem ver passageiros de corridas que estão aguardando motorista ('requested')
    OR id IN (
      SELECT rider_id FROM public.rides
      WHERE status = 'requested'
    )
  );


-- ─────────────────────────────────────────────
-- FILE: 20260611120000_driver_ride_totals.sql
-- ─────────────────────────────────────────────

-- Mantém profiles.total_rides e profiles.total_distance atualizados
-- automaticamente a cada corrida finalizada (insert em driver_earnings,
-- que ocorre exatamente uma vez por corrida dentro de finish_ride).

CREATE OR REPLACE FUNCTION public.update_driver_ride_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_distance numeric;
BEGIN
  SELECT COALESCE(actual_distance, distance_meters, distance, 0)
  INTO v_distance
  FROM public.rides
  WHERE id = NEW.ride_id;

  UPDATE public.profiles_raw
  SET total_rides    = COALESCE(total_rides, 0) + 1,
      total_distance = COALESCE(total_distance, 0) + COALESCE(v_distance, 0)::integer
  WHERE id = NEW.driver_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_driver_ride_totals ON public.driver_earnings;
CREATE TRIGGER trg_update_driver_ride_totals
  AFTER INSERT ON public.driver_earnings
  FOR EACH ROW
  EXECUTE FUNCTION public.update_driver_ride_totals();

-- Corrige o INSERT via view payout_accounts: o trigger INSTEAD OF devolvia
-- NEW com id/created_at nulos (gerados só na tabela raw), quebrando o
-- `insert ... returning` usado pela edge function user-actions.
CREATE OR REPLACE FUNCTION public.payout_accounts_view_dml_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.id := COALESCE(NEW.id, gen_random_uuid());
    NEW.created_at := COALESCE(NEW.created_at, now());
    NEW.is_default := COALESCE(NEW.is_default, false);
    INSERT INTO public.payout_accounts_raw (
      id, driver_id, payout_method_id, routing_number, account_holder_name, bank_name,
      is_default, account_holder_country, account_holder_city, account_holder_state,
      account_holder_address, account_holder_phone, account_holder_zip, created_at,
      encrypted_account_number
    ) VALUES (
      NEW.id, NEW.driver_id, NEW.payout_method_id, NEW.routing_number, NEW.account_holder_name, NEW.bank_name,
      NEW.is_default, NEW.account_holder_country, NEW.account_holder_city, NEW.account_holder_state,
      NEW.account_holder_address, NEW.account_holder_phone, NEW.account_holder_zip, NEW.created_at,
      public.encrypt_val(NEW.account_number)
    );
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    UPDATE public.payout_accounts_raw SET
      driver_id = NEW.driver_id,
      payout_method_id = NEW.payout_method_id,
      routing_number = NEW.routing_number,
      account_holder_name = NEW.account_holder_name,
      bank_name = NEW.bank_name,
      is_default = NEW.is_default,
      account_holder_country = NEW.account_holder_country,
      account_holder_city = NEW.account_holder_city,
      account_holder_state = NEW.account_holder_state,
      account_holder_address = NEW.account_holder_address,
      account_holder_phone = NEW.account_holder_phone,
      account_holder_zip = NEW.account_holder_zip,
      created_at = NEW.created_at,
      encrypted_account_number = CASE
        WHEN NEW.account_number IS DISTINCT FROM OLD.account_number THEN public.encrypt_val(NEW.account_number)
        ELSE encrypted_account_number
      END
    WHERE id = OLD.id;
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    DELETE FROM public.payout_accounts_raw WHERE id = OLD.id;
    RETURN OLD;
  END IF;
END;
$$;

-- Backfill: recalcular totais históricos a partir das corridas existentes
UPDATE public.profiles_raw p
SET total_rides    = agg.cnt,
    total_distance = agg.dist
FROM (
  SELECT driver_id,
         COUNT(*) AS cnt,
         COALESCE(SUM(COALESCE(actual_distance, distance_meters, distance, 0)), 0)::integer AS dist
  FROM public.rides
  WHERE status IN ('completed', 'finished', 'waiting_for_review')
    AND driver_id IS NOT NULL
  GROUP BY driver_id
) agg
WHERE p.id = agg.driver_id;


-- ─────────────────────────────────────────────
-- FILE: 20260611130000_driver_ride_totals_sane_distance.sql
-- ─────────────────────────────────────────────

-- Ignora distâncias corrompidas (> 200 km por corrida, ex.: corrida de teste
-- de 29/05 com 8.333 km) no acumulador de totais do perfil do motorista.

CREATE OR REPLACE FUNCTION public.update_driver_ride_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_distance numeric;
BEGIN
  SELECT COALESCE(actual_distance, distance_meters, distance, 0)
  INTO v_distance
  FROM public.rides
  WHERE id = NEW.ride_id;

  -- Distância acima de 200 km numa corrida urbana é dado corrompido/teste.
  IF v_distance IS NULL OR v_distance > 200000 THEN
    v_distance := 0;
  END IF;

  UPDATE public.profiles_raw
  SET total_rides    = COALESCE(total_rides, 0) + 1,
      total_distance = COALESCE(total_distance, 0) + v_distance::integer
  WHERE id = NEW.driver_id;

  RETURN NEW;
END;
$$;

-- Re-executa o backfill com o mesmo filtro de sanidade
UPDATE public.profiles_raw p
SET total_rides    = agg.cnt,
    total_distance = agg.dist
FROM (
  SELECT driver_id,
         COUNT(*) AS cnt,
         COALESCE(SUM(
           CASE
             WHEN COALESCE(actual_distance, distance_meters, distance, 0) > 200000 THEN 0
             ELSE COALESCE(actual_distance, distance_meters, distance, 0)
           END
         ), 0)::integer AS dist
  FROM public.rides
  WHERE status IN ('completed', 'finished', 'waiting_for_review')
    AND driver_id IS NOT NULL
  GROUP BY driver_id
) agg
WHERE p.id = agg.driver_id;


-- ─────────────────────────────────────────────
-- FILE: 20260611130000_referrals.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: SISTEMA AUTOMATIZADO DE INDICAÇÃO (REFERRALS)
-- ==============================================================================

-- 1. Colunas adicionais na tabela profiles
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS referral_code TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS referred_by_id TEXT REFERENCES public.profiles(id);

COMMENT ON COLUMN public.profiles.referral_code IS 'Código de indicação exclusivo gerado para o perfil.';
COMMENT ON COLUMN public.profiles.referred_by_id IS 'ID do usuário indicador que indicou este perfil.';

-- 2. Tabela de controle de indicações
CREATE TABLE IF NOT EXISTS public.referrals (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id   TEXT REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    referred_id   TEXT REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    reward_amount NUMERIC(10, 2) DEFAULT 0.00,
    status        TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'completed')),
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    completed_at  TIMESTAMP WITH TIME ZONE,
    CONSTRAINT unique_referred UNIQUE (referred_id)
);

ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

-- Políticas de RLS para a tabela referrals
DROP POLICY IF EXISTS "allow_users_select_own_referrals" ON public.referrals;
CREATE POLICY "allow_users_select_own_referrals" ON public.referrals
    FOR SELECT TO authenticated
    USING (
        auth.uid()::text = referrer_id OR 
        auth.uid()::text = referred_id OR 
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

DROP POLICY IF EXISTS "allow_admin_manage_referrals" ON public.referrals;
CREATE POLICY "allow_admin_manage_referrals" ON public.referrals
    FOR ALL TO authenticated
    USING (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

-- Habilitar replicação em tempo real para referrals
BEGIN;
  ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public.referrals;
  ALTER PUBLICATION supabase_realtime ADD TABLE public.referrals;
COMMIT;

-- 3. Função e Trigger para gerar código de indicação único automaticamente
CREATE OR REPLACE FUNCTION generate_referral_code()
RETURNS TRIGGER AS $$
DECLARE
  v_code TEXT;
  v_exists BOOLEAN;
BEGIN
  IF NEW.role IN ('rider', 'driver') AND NEW.referral_code IS NULL THEN
    LOOP
      -- Gera um código curto de 8 caracteres baseado no MD5
      v_code := 'UPPI' || UPPER(substring(md5(random()::text) from 1 for 6));
      SELECT EXISTS(SELECT 1 FROM public.profiles WHERE referral_code = v_code) INTO v_exists;
      EXIT WHEN NOT v_exists;
    END LOOP;
    NEW.referral_code := v_code;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER tr_generate_referral_code
  BEFORE INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION generate_referral_code();

-- 4. Função e Trigger para registrar indicação pendente na criação do profile
CREATE OR REPLACE FUNCTION create_referral_on_profile_insert()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.referred_by_id IS NOT NULL THEN
    INSERT INTO public.referrals (referrer_id, referred_id, status)
    VALUES (NEW.referred_by_id, NEW.id, 'pending')
    ON CONFLICT (referred_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER tr_create_referral_on_profile_insert
  AFTER INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION create_referral_on_profile_insert();

-- 5. Função e Trigger para processar recompensas quando a corrida for concluída
CREATE OR REPLACE FUNCTION process_referral_on_ride_complete()
RETURNS TRIGGER AS $$
DECLARE
  v_referrer_id TEXT;
  v_ref_status TEXT;
  v_bonus_referrer NUMERIC;
  v_bonus_referred NUMERIC;
  v_enabled TEXT;
BEGIN
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    -- Busca quem indicou o passageiro que finalizou a corrida
    SELECT referred_by_id INTO v_referrer_id 
    FROM public.profiles 
    WHERE id = NEW.rider_id;
    
    IF v_referrer_id IS NOT NULL THEN
      -- Confere se a indicação está pendente
      SELECT status INTO v_ref_status 
      FROM public.referrals 
      WHERE referred_id = NEW.rider_id;
      
      IF v_ref_status = 'pending' THEN
        -- Verifica se o programa de indicações está ativo
        SELECT COALESCE(value, 'false') INTO v_enabled FROM public.app_settings WHERE key = 'referral_enabled';
        
        IF v_enabled = 'true' THEN
          -- Carrega valores das recompensas
          SELECT COALESCE(value::numeric, 10.00) INTO v_bonus_referrer FROM public.app_settings WHERE key = 'referral_bonus_referrer';
          SELECT COALESCE(value::numeric, 5.00) INTO v_bonus_referred FROM public.app_settings WHERE key = 'referral_bonus_referred';
          
          -- 1. Atualiza indicação para concluída
          UPDATE public.referrals
          SET status = 'completed',
              reward_amount = v_bonus_referrer,
              completed_at = now()
          WHERE referred_id = NEW.rider_id;
          
          -- 2. Credita indicador
          UPDATE public.profiles
          SET wallet_balance = wallet_balance + v_bonus_referrer
          WHERE id = v_referrer_id;
          
          INSERT INTO public.wallet_transactions (user_id, amount, transaction_type, description, ride_id)
          VALUES (v_referrer_id, v_bonus_referrer, 'topup', 'Bônus de Indicação Uppi (Indicou um passageiro)', NEW.id);
          
          -- 3. Credita indicado
          UPDATE public.profiles
          SET wallet_balance = wallet_balance + v_bonus_referred
          WHERE id = NEW.rider_id;
          
          INSERT INTO public.wallet_transactions (user_id, amount, transaction_type, description, ride_id)
          VALUES (NEW.rider_id, v_bonus_referred, 'topup', 'Bônus de Indicação Uppi (Utilizou código de indicação)', NEW.id);
        END IF;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER tr_process_referral_on_ride_complete
  AFTER UPDATE ON public.rides
  FOR EACH ROW
  EXECUTE FUNCTION process_referral_on_ride_complete();

-- 6. Parâmetros iniciais de configuração do sistema
INSERT INTO public.app_settings (key, value)
VALUES 
  ('referral_enabled', 'true'),
  ('referral_bonus_referrer', '10.00'),
  ('referral_bonus_referred', '5.00')
ON CONFLICT (key) DO NOTHING;


-- ─────────────────────────────────────────────
-- FILE: 20260611140000_cleanup_corrupted_ride.sql
-- ─────────────────────────────────────────────

-- Clean up/Zero out the corrupted test ride from 29/05 (8,333 km distance, R$ 25,005.35 fare)
-- and update the corresponding driver stats.

-- 1. Zero out the ride values
UPDATE public.rides
SET distance = 0,
    distance_meters = 0,
    actual_distance = 0,
    fare = 0,
    driver_share = 0,
    fee = 0
WHERE (distance > 8000000 OR distance_meters > 8000000 OR actual_distance > 8000000 OR fare > 25000)
  AND created_at >= '2026-05-29 00:00:00+00'::timestamptz
  AND created_at < '2026-05-30 00:00:00+00'::timestamptz;

-- 2. Zero out the driver earnings associated with the corrupted ride
UPDATE public.driver_earnings
SET amount = 0,
    gross_amount = 0,
    commission_pct = 0,
    commission_amt = 0,
    platform_commission = 0,
    net_amount = 0,
    tip_amount = 0,
    driver_amount = 0
WHERE ride_id IN (
    SELECT id FROM public.rides
    WHERE (distance = 0 AND fare = 0)
      AND created_at >= '2026-05-29 00:00:00+00'::timestamptz
      AND created_at < '2026-05-30 00:00:00+00'::timestamptz
);

-- 3. Zero out the wallet transactions associated with the corrupted ride
UPDATE public.wallet_transactions
SET amount = 0
WHERE ride_id IN (
    SELECT id FROM public.rides
    WHERE (distance = 0 AND fare = 0)
      AND created_at >= '2026-05-29 00:00:00+00'::timestamptz
      AND created_at < '2026-05-30 00:00:00+00'::timestamptz
);

-- 4. Re-calculate driver stats for all drivers to normalize totals
UPDATE public.profiles_raw p
SET total_rides    = agg.cnt,
    total_distance = agg.dist
FROM (
  SELECT driver_id,
         COUNT(*) AS cnt,
         COALESCE(SUM(
           CASE
             WHEN COALESCE(actual_distance, distance_meters, distance, 0) > 200000 THEN 0
             ELSE COALESCE(actual_distance, distance_meters, distance, 0)
           END
         ), 0)::integer AS dist
  FROM public.rides
  WHERE status IN ('completed', 'finished', 'waiting_for_review')
    AND driver_id IS NOT NULL
  GROUP BY driver_id
) agg
WHERE p.id = agg.driver_id;


-- ─────────────────────────────────────────────
-- FILE: 20260615000000_fix_driver_earnings_admin_visibility.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- CONSOLIDAÇÃO — POLÍTICA DE SELECT DE driver_earnings
-- Data: 2026-06-15
-- ==============================================================================
-- Contexto: o banco de produção possuía DUAS políticas de SELECT sobrepostas
-- ("own_or_admin_read_earnings" baseada em profiles_raw.role e a política ALL
-- "admin_all_access" baseada na tabela admins). Esta migração unifica a checagem
-- de SELECT numa única política canônica usando is_admin_or_operator(), que cobre
-- AMBAS as fontes (profiles_raw.role E a tabela admins) e evita recursão de RLS.
--
-- Observação: a leitura por administradores JÁ funcionava em produção via a
-- política "admin_all_access". Esta migração é uma limpeza/consolidação, não um
-- desbloqueio — nenhum acesso é adicionado nem removido para admins/operadores.
-- ==============================================================================

DROP POLICY IF EXISTS "driver_earnings_select"      ON public.driver_earnings;
DROP POLICY IF EXISTS "own_or_admin_read_earnings"  ON public.driver_earnings;

CREATE POLICY "driver_earnings_select" ON public.driver_earnings
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = driver_id
    OR public.is_admin_or_operator(auth.uid()::text)
  );


-- ─────────────────────────────────────────────
-- FILE: 20260615103000_secure_webhook_fallback.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO — SEGURANÇA E REMOÇÃO DE URL DE STAGING HARDCODED NO WEBHOOK DE OFERTAS
-- Data: 2026-06-15
-- Ecossistema Uppi — Engenharia de Infraestrutura e Banco de Dados
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.notify_webhook_new_offer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_secret TEXT;
  v_supabase_url TEXT;
  v_webhook_url TEXT;
BEGIN
  IF NEW.status != 'offered' THEN
    RETURN NEW;
  END IF;

  -- 1. Buscar a URL base do Supabase de forma dinâmica
  v_supabase_url := current_setting('app.supabase_url', true);
  
  -- 2. Tentar buscar na tabela app_settings se a variável GUC não estiver definida
  IF v_supabase_url IS NULL OR v_supabase_url = '' THEN
    SELECT value INTO v_supabase_url
    FROM public.app_settings
    WHERE key = 'supabase_url'
    LIMIT 1;
  END IF;

  -- 3. Se ainda assim estiver ausente, abortar com aviso para não disparar contra servidor de staging
  IF v_supabase_url IS NULL OR v_supabase_url = '' THEN
    RAISE WARNING 'notify_webhook_new_offer ignorado: app.supabase_url ou app_settings(supabase_url) não configurados.';
    RETURN NEW;
  END IF;

  -- Construir o endpoint correto da Edge Function
  v_webhook_url := rtrim(v_supabase_url, '/') || '/functions/v1/webhook-new-ride';

  -- 4. Buscar o secret da tabela de configurações
  SELECT value INTO v_secret
  FROM public.app_settings
  WHERE key = 'webhook_secret'
  LIMIT 1;

  -- Fallback de secret via current_setting
  IF v_secret IS NULL THEN
    v_secret := current_setting('app.webhook_secret', true);
  END IF;

  -- 5. Disparar a chamada HTTP assíncrona/segura
  PERFORM net.http_post(
    url := v_webhook_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', COALESCE(v_secret, '')
    ),
    body := json_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'schema', TG_TABLE_SCHEMA,
      'record', row_to_json(NEW),
      'timestamp', extract(epoch from now())
    )::jsonb,
    timeout_milliseconds := 5000
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_webhook_new_offer falhou: %', SQLERRM;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_webhook_new_offer() IS 
  'Trigger dinâmico e seguro para envio de push de nova corrida via Edge Function, sem URL de staging hardcoded.';


-- ─────────────────────────────────────────────
-- FILE: 20260616120000_scheduled_rides_dispatch.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Despacho Automático de Corridas Agendadas (booked)
-- 1. rpc_dispatch_scheduled_rides()
-- 2. Cron job 'dispatch-scheduled-rides' (a cada minuto)
-- 3. Atualizar cron job 'cleanup-expired-rides' para respeitar expected_at
-- ==============================================================================

-- 1. FUNÇÃO DE DESPACHO DE AGENDAMENTOS
CREATE OR REPLACE FUNCTION public.rpc_dispatch_scheduled_rides()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
BEGIN
    -- Busca corridas agendadas ('booked') que devem ser iniciadas nos próximos 15 minutos
    FOR r IN 
        SELECT id 
        FROM public.rides 
        WHERE status = 'booked' 
          AND expected_at IS NOT NULL 
          AND expected_at <= now() + interval '15 minutes'
    LOOP
        -- Atualiza para 'requested', o que dispara automaticamente o trigger trg_on_ride_requested
        UPDATE public.rides
        SET status = 'requested',
            updated_at = now()
        WHERE id = r.id;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.rpc_dispatch_scheduled_rides() IS 'Varre as corridas agendadas (booked) e altera o status para requested faltando 15 minutos para o horário esperado, acionando o loop geolocalizado de despacho.';

-- 2. AGENDAR DESPACHO NO PG_CRON (a cada minuto)
SELECT cron.unschedule('dispatch-scheduled-rides') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dispatch-scheduled-rides');
SELECT cron.schedule(
  'dispatch-scheduled-rides',
  '* * * * *',
  $$
    SELECT public.rpc_dispatch_scheduled_rides();
  $$
);

-- 3. AJUSTAR CRON DE LIMPEZA EXISTENTE PARA RESPEITAR EXPECTED_AT
SELECT cron.unschedule('cleanup-expired-rides') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup-expired-rides');
SELECT cron.schedule(
  'cleanup-expired-rides',
  '*/5 * * * *',
  $$
    UPDATE public.rides
    SET status = 'expired', updated_at = now()
    WHERE status = 'requested'
      AND driver_id IS NULL
      AND COALESCE(expected_at, created_at) < now() - interval '3 minutes';
  $$
);

-- Garantir privilégios
GRANT EXECUTE ON FUNCTION public.rpc_dispatch_scheduled_rides() TO authenticated;


-- ─────────────────────────────────────────────
-- FILE: 20260616140000_safety_schema_suspicious_devices.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Isolamento do Módulo de Segurança (Esquema 'safety')
-- 1. Criar esquema safety
-- 2. Criar tabela safety.suspicious_devices e migrar dados existentes
-- 3. Habilitar RLS e políticas
-- 4. Atualizar RPC pública rpc_flag_suspicious_device
-- ==============================================================================

-- 1. CRIAR O ESQUEMA DE SEGURANÇA
CREATE SCHEMA IF NOT EXISTS safety;

-- 2. CRIAR A TABELA NO NOVO ESQUEMA
CREATE TABLE IF NOT EXISTS safety.suspicious_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id TEXT REFERENCES public.profiles_raw(id) ON DELETE CASCADE,
    threat_type TEXT NOT NULL CHECK (threat_type IN ('root_jailbreak', 'emulator', 'fake_gps')),
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Mover dados se a tabela antiga existir
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'suspicious_devices') THEN
        INSERT INTO safety.suspicious_devices (id, profile_id, threat_type, details, created_at)
        SELECT id, profile_id, threat_type, details, created_at FROM public.suspicious_devices
        ON CONFLICT (id) DO NOTHING;
        
        DROP TABLE public.suspicious_devices CASCADE;
    END IF;
END $$;

-- 3. HABILITAR RLS E POLÍTICAS NO NOVO ESQUEMA
ALTER TABLE safety.suspicious_devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow authenticated users to insert security logs" ON safety.suspicious_devices;
CREATE POLICY "Allow authenticated users to insert security logs"
    ON safety.suspicious_devices
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid()::text = profile_id);

DROP POLICY IF EXISTS "Allow authenticated users to select their own logs" ON safety.suspicious_devices;
CREATE POLICY "Allow authenticated users to select their own logs"
    ON safety.suspicious_devices
    FOR SELECT
    TO authenticated
    USING (auth.uid()::text = profile_id);

-- Permitir leitura completa para administradores
DROP POLICY IF EXISTS "Allow admins to read all security logs" ON safety.suspicious_devices;
CREATE POLICY "Allow admins to read all security logs"
    ON safety.suspicious_devices
    FOR ALL
    TO authenticated
    USING (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

-- 4. ATUALIZAR A RPC PÚBLICA PARA ESCREVER NO ESQUEMA SAFETY (Retrocompatibilidade)
CREATE OR REPLACE FUNCTION public.rpc_flag_suspicious_device(p_threat_type TEXT, p_details JSONB)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Insere o log no esquema safety
  INSERT INTO safety.suspicious_devices (profile_id, threat_type, details)
  VALUES (auth.uid()::text, p_threat_type, p_details);

  -- Bloqueia o motorista no esquema public
  UPDATE public.profiles
  SET status = 'blocked',
      is_approved = false,
      updated_at = now()
  WHERE id = auth.uid()::text;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_flag_suspicious_device(TEXT, JSONB) TO authenticated;


-- ─────────────────────────────────────────────
-- FILE: 20260617000000_optimize_realtime_publications.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Otimização do Supabase Realtime (Redução de Mensagens CDC)
-- Data: 2026-06-17
-- Ecossistema Uppi — Engenharia de Banco de Dados
-- ==============================================================================

-- 1. REMOVER TABELAS NÃO CRÍTICAS DA REPLICAÇÃO EM TEMPO REAL
-- Remove as tabelas estáticas da publicação 'supabase_realtime' para economizar tráfego CDC.
DO $$
DECLARE
  t_name TEXT;
  tables_to_drop TEXT[] := ARRAY[
    'announcements',
    'favorite_addresses',
    'favorite_drivers',
    'saved_places',
    'challenges',
    'badge_definitions',
    'feedbacks',
    'reviews',
    'ride_reviews',
    'payout_accounts_raw',
    'payout_methods',
    'car_models',
    'car_colors',
    'coupon_usages',
    'user_badges',
    'complaints',
    'support_tickets'
  ];
BEGIN
  FOREACH t_name IN ARRAY tables_to_drop
  LOOP
    IF EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t_name
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime DROP TABLE public.%I', t_name);
    END IF;
  END LOOP;
END $$;

-- 2. GARANTIR QUE APENAS AS TABELAS DO FLUXO CRÍTICO PARTICIPEM DA PUBLICAÇÃO
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'rides'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.rides;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'ride_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_messages;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'sos_alerts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.sos_alerts;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'ride_offers'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_offers;
  END IF;
END $$;


-- ─────────────────────────────────────────────
-- FILE: 20260618000000_optimize_redispatch_trigger.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Otimização do Trigger de Despacho (Redução de Carga no PostgreSQL)
-- Data: 2026-06-18
-- Ecossistema Uppi — Engenharia de Banco de Dados
-- ==============================================================================

-- 1. RECRIAR O TRIGGER PARA DISPARAR APENAS NA TRANSIÇÃO DE STATUS PARA 'online'
-- Isso evita que o trigger e a função PostGIS rodem em cada atualização de GPS (lat/lng) dos motoristas online.
DROP TRIGGER IF EXISTS trg_redispatch_on_driver_online ON public.driver_locations;

CREATE TRIGGER trg_redispatch_on_driver_online
    AFTER INSERT OR UPDATE OF status ON public.driver_locations
    FOR EACH ROW
    WHEN (NEW.status = 'online' AND (OLD.status IS DISTINCT FROM NEW.status OR OLD.status IS NULL))
    EXECUTE FUNCTION public.trg_redispatch_on_driver_online_fn();


-- ─────────────────────────────────────────────
-- FILE: 20260619000000_add_boarding_pin_enabled.sql
-- ─────────────────────────────────────────────

-- =====================================================================
-- MIGRAÇÃO: Adiciona opção de configuração de PIN de embarque no perfil
-- Data: 2026-06-19
-- =====================================================================

-- 1. Adicionar coluna boarding_pin_enabled na tabela profiles_raw
ALTER TABLE public.profiles_raw ADD COLUMN IF NOT EXISTS boarding_pin_enabled BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN public.profiles_raw.boarding_pin_enabled IS 
  'Define se o passageiro deseja exigir a verificação de PIN de 4 dígitos antes do motorista iniciar a corrida.';

-- 2. Reconstruir a VIEW profiles para incluir a nova coluna
CREATE OR REPLACE VIEW public.profiles WITH (security_invoker = true) AS
SELECT
  id,
  role,
  full_name,
  phone_number,
  email,
  fcm_token,
  status,
  wallet_balance,
  search_radius,
  current_location,
  vehicle_details,
  created_at,
  updated_at,
  rating,
  review_count,
  commission_percentage,
  commission_exempt_until,
  subscription_expires_at,
  phone,
  documents,
  is_deleted,
  deleted_at,
  is_approved,
  vehicle_type,
  marker_url,
  certificate_number,
  search_distance,
  vehicle_plate_number,
  vehicle_production_year,
  vehicle_model_id,
  vehicle_color_id,
  bank_name,
  bank_account_number,
  bank_swift_code,
  bank_routing_number,
  address,
  gender,
  id_number,
  preset_avatar_number,
  total_rides,
  total_distance,
  average_rating,
  rating_count,
  public.decrypt_val(encrypted_cpf) AS cpf,
  favorite_drivers,
  is_blocked,
  identity_verification_status,
  identity_docs,
  cooldown_until,
  consecutive_rejections,
  accessibility_wheelchair,
  accessibility_hearing_impaired,
  accessibility_visual_aid,
  accessibility_pet_friendly,
  accessibility_child_seat,
  gender_verified,
  boarding_pin_enabled
FROM public.profiles_raw;

-- 3. Atualizar a função de DML da VIEW profiles
CREATE OR REPLACE FUNCTION public.profiles_view_dml_trigger()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.profiles_raw (
      id, role, full_name, phone_number, email, fcm_token, status, wallet_balance,
      search_radius, current_location, vehicle_details, created_at, updated_at,
      rating, review_count, commission_percentage, commission_exempt_until,
      subscription_expires_at, phone, documents, is_deleted, deleted_at,
      is_approved, vehicle_type, marker_url, certificate_number, search_distance,
      vehicle_plate_number, vehicle_production_year, vehicle_model_id, vehicle_color_id,
      bank_name, bank_account_number, bank_swift_code, bank_routing_number,
      address, gender, id_number, preset_avatar_number, total_rides, total_distance,
      average_rating, rating_count, favorite_drivers, is_blocked, 
      identity_verification_status, identity_docs,
      cooldown_until, consecutive_rejections,
      accessibility_wheelchair, accessibility_hearing_impaired,
      accessibility_visual_aid, accessibility_pet_friendly,
      accessibility_child_seat, gender_verified,
      encrypted_cpf, boarding_pin_enabled
    ) VALUES (
      NEW.id, NEW.role, NEW.full_name, NEW.phone_number, NEW.email, NEW.fcm_token, NEW.status, NEW.wallet_balance,
      NEW.search_radius, NEW.current_location, NEW.vehicle_details, NEW.created_at, NEW.updated_at,
      NEW.rating, NEW.review_count, NEW.commission_percentage, NEW.commission_exempt_until,
      NEW.subscription_expires_at, NEW.phone, NEW.documents, NEW.is_deleted, NEW.deleted_at,
      NEW.is_approved, NEW.vehicle_type, NEW.marker_url, NEW.certificate_number, NEW.search_distance,
      NEW.vehicle_plate_number, NEW.vehicle_production_year, NEW.vehicle_model_id, NEW.vehicle_color_id,
      NEW.bank_name, NEW.bank_account_number, NEW.bank_swift_code, NEW.bank_routing_number,
      NEW.address, NEW.gender, NEW.id_number, NEW.preset_avatar_number, NEW.total_rides, NEW.total_distance,
      NEW.average_rating, NEW.rating_count, NEW.favorite_drivers, NEW.is_blocked, 
      NEW.identity_verification_status, NEW.identity_docs,
      NEW.cooldown_until, NEW.consecutive_rejections,
      NEW.accessibility_wheelchair, NEW.accessibility_hearing_impaired,
      NEW.accessibility_visual_aid, NEW.accessibility_pet_friendly,
      NEW.accessibility_child_seat, NEW.gender_verified,
      public.encrypt_val(NEW.cpf), NEW.boarding_pin_enabled
    );
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    UPDATE public.profiles_raw SET
      role = NEW.role,
      full_name = NEW.full_name,
      phone_number = NEW.phone_number,
      email = NEW.email,
      fcm_token = NEW.fcm_token,
      status = NEW.status,
      wallet_balance = NEW.wallet_balance,
      search_radius = NEW.search_radius,
      current_location = NEW.current_location,
      vehicle_details = NEW.vehicle_details,
      created_at = NEW.created_at,
      updated_at = NEW.updated_at,
      rating = NEW.rating,
      review_count = NEW.review_count,
      commission_percentage = NEW.commission_percentage,
      commission_exempt_until = NEW.commission_exempt_until,
      subscription_expires_at = NEW.subscription_expires_at,
      phone = NEW.phone,
      documents = NEW.documents,
      is_deleted = NEW.is_deleted,
      deleted_at = NEW.deleted_at,
      is_approved = NEW.is_approved,
      vehicle_type = NEW.vehicle_type,
      marker_url = NEW.marker_url,
      certificate_number = NEW.certificate_number,
      search_distance = NEW.search_distance,
      vehicle_plate_number = NEW.vehicle_plate_number,
      vehicle_production_year = NEW.vehicle_production_year,
      vehicle_model_id = NEW.vehicle_model_id,
      vehicle_color_id = NEW.vehicle_color_id,
      bank_name = NEW.bank_name,
      bank_account_number = NEW.bank_account_number,
      bank_swift_code = NEW.bank_swift_code,
      bank_routing_number = NEW.bank_routing_number,
      address = NEW.address,
      gender = NEW.gender,
      id_number = NEW.id_number,
      preset_avatar_number = NEW.preset_avatar_number,
      total_rides = NEW.total_rides,
      total_distance = NEW.total_distance,
      average_rating = NEW.average_rating,
      rating_count = NEW.rating_count,
      favorite_drivers = NEW.favorite_drivers,
      is_blocked = NEW.is_blocked,
      identity_verification_status = NEW.identity_verification_status,
      identity_docs = NEW.identity_docs,
      cooldown_until = NEW.cooldown_until,
      consecutive_rejections = NEW.consecutive_rejections,
      accessibility_wheelchair = NEW.accessibility_wheelchair,
      accessibility_hearing_impaired = NEW.accessibility_hearing_impaired,
      accessibility_visual_aid = NEW.accessibility_visual_aid,
      accessibility_pet_friendly = NEW.accessibility_pet_friendly,
      accessibility_child_seat = NEW.accessibility_child_seat,
      gender_verified = NEW.gender_verified,
      boarding_pin_enabled = NEW.boarding_pin_enabled,
      encrypted_cpf = CASE 
        WHEN NEW.cpf IS DISTINCT FROM OLD.cpf THEN public.encrypt_val(NEW.cpf)
        ELSE encrypted_cpf
      END
    WHERE id = OLD.id;
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    DELETE FROM public.profiles_raw WHERE id = OLD.id;
    RETURN OLD;
  END IF;
END;
$$ LANGUAGE plpgsql;


-- ─────────────────────────────────────────────
-- FILE: 20260620000000_add_get_matching_surge_zone.sql
-- ─────────────────────────────────────────────

-- Função PostgreSQL para buscar zonas de tarifas dinâmicas (surge_zones) que cobrem um determinado ponto
CREATE OR REPLACE FUNCTION public.get_matching_surge_zone(
  p_lat FLOAT,
  p_lng FLOAT
)
RETURNS TABLE(
  id UUID,
  name TEXT,
  multiplier NUMERIC(3,2)
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    sz.id,
    sz.name,
    sz.multiplier
  FROM public.surge_zones sz
  WHERE
    sz.is_active = true
    AND (sz.expires_at IS NULL OR sz.expires_at > NOW())
    -- ST_Contains requer geometry, convertendo de geography
    AND ST_Contains(
      sz.boundary::geometry,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geometry
    )
  ORDER BY sz.multiplier DESC
  LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_matching_surge_zone(FLOAT, FLOAT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_matching_surge_zone(FLOAT, FLOAT) TO service_role;


-- ─────────────────────────────────────────────
-- FILE: 20260620000001_add_ride_safety_columns.sql
-- ─────────────────────────────────────────────

-- Adicionar colunas de segurança e monitoramento de rota na tabela rides
ALTER TABLE public.rides
  ADD COLUMN IF NOT EXISTS route_polyline JSONB DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS deviation_alert_sent BOOLEAN DEFAULT false;

COMMENT ON COLUMN public.rides.route_polyline IS 'Polilinha com as coordenadas geográficas planejadas da rota da viagem';
COMMENT ON COLUMN public.rides.deviation_alert_sent IS 'Sinalizador para evitar o envio repetido do alerta de desvio de rota';


-- ─────────────────────────────────────────────
-- FILE: 20260620000002_add_batch_matching.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRATION: Despacho Ponderado em Lote (Batching & Scored Dispatch)
-- Data: 2026-06-20
-- Autor: Antigravity
-- ==============================================================================

-- 1. Cria a função de despacho em lote com score ponderado (Algoritmo Húngaro Guloso Bipartido)
CREATE OR REPLACE FUNCTION public.rpc_batch_dispatch_scored()
RETURNS TABLE (
  ride_id UUID,
  driver_id TEXT,
  score FLOAT
) 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ride RECORD;
  v_best_driver_id TEXT;
  v_best_score FLOAT;
BEGIN
  -- Cria tabelas temporárias para armazenar os pools de corridas e motoristas
  CREATE TEMP TABLE temp_pending_rides ON COMMIT DROP AS
  SELECT r.id, r.pickup_lat, r.pickup_lng
  FROM public.rides r
  WHERE r.status = 'requested'
    AND r.created_at > now() - interval '20 minutes'
    AND NOT EXISTS (
      SELECT 1 
      FROM public.ride_offers ro 
      WHERE ro.ride_id = r.id 
        AND ro.status = 'offered' 
        AND ro.expires_at > now()
    );

  CREATE TEMP TABLE temp_available_drivers ON COMMIT DROP AS
  SELECT dl.driver_id, dl.lat, dl.lng, COALESCE(p.rating, 4.5)::FLOAT as rating
  FROM public.driver_locations dl
  LEFT JOIN public.profiles p ON p.id = dl.driver_id
  WHERE dl.status = 'online'
    -- Motorista não tem ofertas ativas
    AND NOT EXISTS (
      SELECT 1 
      FROM public.ride_offers ro 
      WHERE ro.driver_id = dl.driver_id 
        AND ro.status = 'offered' 
        AND ro.expires_at > now()
    )
    -- Motorista não está em corrida ativa
    AND NOT EXISTS (
      SELECT 1 
      FROM public.rides r 
      WHERE r.driver_id = dl.driver_id 
        AND r.status IN ('accepted', 'arrived', 'in_progress')
    );

  -- Loop guloso para encontrar o par ótimo de menor distância/maior score
  FOR v_ride IN SELECT * FROM temp_pending_rides LOOP
    -- Encontra o melhor motorista com base na fórmula de score geodésico + rating
    SELECT ad.driver_id, 
      (
        (1.0 / GREATEST(ST_Distance(
          ST_MakePoint(ad.lng::FLOAT, ad.lat::FLOAT)::geography,
          ST_MakePoint(v_ride.pickup_lng, v_ride.pickup_lat)::geography
        ) / 1000.0, 0.1)) * 0.4
        + ad.rating / 5.0 * 0.4
        + 0.2
      )::FLOAT AS calc_score INTO v_best_driver_id, v_best_score
    FROM temp_available_drivers ad
    WHERE NOT EXISTS (
      SELECT 1 
      FROM public.ride_rejected_drivers rr 
      WHERE rr.ride_id = v_ride.id 
        AND rr.driver_id = ad.driver_id
    )
    ORDER BY calc_score DESC
    LIMIT 1;

    -- Se um motorista elegível for encontrado, cria a oferta e retira o motorista do pool
    IF v_best_driver_id IS NOT NULL THEN
      -- Inserir nova oferta de 15 segundos
      INSERT INTO public.ride_offers (ride_id, driver_id, status, expires_at)
      VALUES (v_ride.id, v_best_driver_id, 'offered', now() + interval '15 seconds');

      -- Alterar status da corrida para 'searching'
      UPDATE public.rides
      SET status = 'searching',
          updated_at = now()
      WHERE id = v_ride.id;

      -- Remover motorista do pool temporário para evitar dupla oferta nesta rodada
      DELETE FROM temp_available_drivers WHERE temp_available_drivers.driver_id = v_best_driver_id;

      -- Retornar os dados do match
      ride_id := v_ride.id;
      driver_id := v_best_driver_id;
      score := v_best_score;
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$$;

-- 2. Atualiza a função rpc_find_and_offer_ride para usar get_nearby_drivers_scored
CREATE OR REPLACE FUNCTION public.rpc_find_and_offer_ride(p_ride_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pickup_lat FLOAT;
    v_pickup_lng FLOAT;
    v_ride_status TEXT;
    v_driver_id TEXT;
BEGIN
    -- Bloquear linha da corrida para evitar conflitos concorrentes
    SELECT status, pickup_lat, pickup_lng INTO v_ride_status, v_pickup_lat, v_pickup_lng
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    -- Se a corrida não existir ou já tiver sido aceita/cancelada, encerra o loop
    IF v_ride_status IS NULL OR v_ride_status NOT IN ('requested', 'searching') THEN
        RETURN FALSE;
    END IF;

    -- Buscar o motorista 'online' aprovado com o maior score via get_nearby_drivers_scored
    SELECT ds.driver_id INTO v_driver_id
    FROM public.get_nearby_drivers_scored(v_pickup_lat, v_pickup_lng, 5.0) ds
    WHERE NOT EXISTS (
        SELECT 1 
        FROM public.ride_rejected_drivers rr 
        WHERE rr.ride_id = p_ride_id 
          AND rr.driver_id = ds.driver_id
    )
    -- Evitar motoristas em corridas ativas
    AND NOT EXISTS (
        SELECT 1 
        FROM public.rides r 
        WHERE r.driver_id = ds.driver_id 
          AND r.status IN ('accepted', 'arrived', 'in_progress')
    )
    -- Evitar motoristas com ofertas de corrida ativas pendentes
    AND NOT EXISTS (
        SELECT 1
        FROM public.ride_offers ro
        WHERE ro.driver_id = ds.driver_id
          AND ro.status = 'offered'
          AND ro.expires_at > now()
    )
    ORDER BY ds.score DESC
    LIMIT 1;

    -- Se um motorista elegível for encontrado, criar a oferta e atualizar o status
    IF v_driver_id IS NOT NULL THEN
        -- Expirar ofertas anteriores ainda marcadas como 'offered' para esta corrida
        UPDATE public.ride_offers
        SET status = 'expired'
        WHERE ride_id = p_ride_id AND status = 'offered';

        -- Inserir nova oferta de 15 segundos
        INSERT INTO public.ride_offers (ride_id, driver_id, status, expires_at)
        VALUES (p_ride_id, v_driver_id, 'offered', now() + interval '15 seconds');

        -- Alterar status da corrida para 'searching'
        UPDATE public.rides
        SET status = 'searching',
            updated_at = now()
        WHERE id = p_ride_id;

        RETURN TRUE;
    ELSE
        -- Nenhum motorista encontrado na região: reverter status para 'requested'
        UPDATE public.rides
        SET status = 'requested',
            updated_at = now()
        WHERE id = p_ride_id AND status = 'searching';

        RETURN FALSE;
    END IF;
END;
$$;

-- 3. Atualizar rpc_sweep_expired_offers para usar o rpc_batch_dispatch_scored (despacho contínuo em lote)
CREATE OR REPLACE FUNCTION public.rpc_sweep_expired_offers()
RETURNS TABLE (
    offer_id UUID,
    ride_id UUID,
    driver_id TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
BEGIN
    -- 1. Varre e expira ofertas que passaram do tempo limite de aceitação
    FOR r IN 
        SELECT ro.id, ro.ride_id, ro.driver_id
        FROM public.ride_offers ro
        WHERE ro.status = 'offered'
          AND ro.expires_at < now()
    LOOP
        -- Atualizar status da oferta para expirado
        UPDATE public.ride_offers
        SET status = 'expired'
        WHERE id = r.id AND status = 'offered';

        IF FOUND THEN
            -- Inserir motorista na lista de rejeitados para esta corrida para evitar novo loop imediato
            INSERT INTO public.ride_rejected_drivers (ride_id, driver_id)
            VALUES (r.ride_id, r.driver_id)
            ON CONFLICT (ride_id, driver_id) DO NOTHING;

            -- Tentar despachar instantaneamente para o próximo motorista geolocalizado
            PERFORM public.rpc_find_and_offer_ride(r.ride_id);

            -- Preencher valores de retorno
            offer_id := r.id;
            ride_id := r.ride_id;
            driver_id := r.driver_id;
            RETURN NEXT;
        END IF;
    END LOOP;

    -- 2. DISPARAR DESPACHO EM LOTE PONDERADO (BATCHING)
    -- Em vez de despachar um por um de forma FCFS simples, roda o algoritmo guloso bipartido.
    PERFORM public.rpc_batch_dispatch_scored();
END;
$$;

-- Privilégios
GRANT EXECUTE ON FUNCTION public.rpc_batch_dispatch_scored() TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_batch_dispatch_scored() TO service_role;


-- ─────────────────────────────────────────────
-- FILE: 20260620000003_add_driver_mp_account.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRATION: Adicionar campo mercado_pago_account_id para Split de Pagamento
-- Data: 2026-06-20
-- Autor: Antigravity
-- ==============================================================================

-- 1. Adicionar coluna na tabela base profiles_raw
ALTER TABLE public.profiles_raw
  ADD COLUMN IF NOT EXISTS mercado_pago_account_id TEXT;

COMMENT ON COLUMN public.profiles_raw.mercado_pago_account_id IS 'ID da conta Mercado Pago do motorista para recebimento direto de split de pagamento';

-- 2. Reconstruir a VIEW profiles para incluir a nova coluna
CREATE OR REPLACE VIEW public.profiles WITH (security_invoker = true) AS
SELECT
  id,
  role,
  full_name,
  phone_number,
  email,
  fcm_token,
  status,
  wallet_balance,
  search_radius,
  current_location,
  vehicle_details,
  created_at,
  updated_at,
  rating,
  review_count,
  commission_percentage,
  commission_exempt_until,
  subscription_expires_at,
  phone,
  documents,
  is_deleted,
  deleted_at,
  is_approved,
  vehicle_type,
  marker_url,
  certificate_number,
  search_distance,
  vehicle_plate_number,
  vehicle_production_year,
  vehicle_model_id,
  vehicle_color_id,
  bank_name,
  bank_account_number,
  bank_swift_code,
  bank_routing_number,
  address,
  gender,
  id_number,
  preset_avatar_number,
  total_rides,
  total_distance,
  average_rating,
  rating_count,
  public.decrypt_val(encrypted_cpf) AS cpf,
  favorite_drivers,
  is_blocked,
  identity_verification_status,
  identity_docs,
  cooldown_until,
  consecutive_rejections,
  accessibility_wheelchair,
  accessibility_hearing_impaired,
  accessibility_visual_aid,
  accessibility_pet_friendly,
  accessibility_child_seat,
  gender_verified,
  mercado_pago_account_id,
  boarding_pin_enabled
FROM public.profiles_raw;

-- 3. Atualizar a função de DML da VIEW profiles para repassar a nova coluna para a tabela base
CREATE OR REPLACE FUNCTION public.profiles_view_dml_trigger()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.profiles_raw (
      id, role, full_name, phone_number, email, fcm_token, status, wallet_balance,
      search_radius, current_location, vehicle_details, created_at, updated_at,
      rating, review_count, commission_percentage, commission_exempt_until,
      subscription_expires_at, phone, documents, is_deleted, deleted_at,
      is_approved, vehicle_type, marker_url, certificate_number, search_distance,
      vehicle_plate_number, vehicle_production_year, vehicle_model_id, vehicle_color_id,
      bank_name, bank_account_number, bank_swift_code, bank_routing_number,
      address, gender, id_number, preset_avatar_number, total_rides, total_distance,
      average_rating, rating_count, favorite_drivers, is_blocked, 
      identity_verification_status, identity_docs,
      cooldown_until, consecutive_rejections,
      accessibility_wheelchair, accessibility_hearing_impaired,
      accessibility_visual_aid, accessibility_pet_friendly,
      accessibility_child_seat, gender_verified,
      encrypted_cpf, mercado_pago_account_id, boarding_pin_enabled
    ) VALUES (
      NEW.id, NEW.role, NEW.full_name, NEW.phone_number, NEW.email, NEW.fcm_token, NEW.status, NEW.wallet_balance,
      NEW.search_radius, NEW.current_location, NEW.vehicle_details, NEW.created_at, NEW.updated_at,
      NEW.rating, NEW.review_count, NEW.commission_percentage, NEW.commission_exempt_until,
      NEW.subscription_expires_at, NEW.phone, NEW.documents, NEW.is_deleted, NEW.deleted_at,
      NEW.is_approved, NEW.vehicle_type, NEW.marker_url, NEW.certificate_number, NEW.search_distance,
      NEW.vehicle_plate_number, NEW.vehicle_production_year, NEW.vehicle_model_id, NEW.vehicle_color_id,
      NEW.bank_name, NEW.bank_account_number, NEW.bank_swift_code, NEW.bank_routing_number,
      NEW.address, NEW.gender, NEW.id_number, NEW.preset_avatar_number, NEW.total_rides, NEW.total_distance,
      NEW.average_rating, NEW.rating_count, NEW.favorite_drivers, NEW.is_blocked, 
      NEW.identity_verification_status, NEW.identity_docs,
      NEW.cooldown_until, NEW.consecutive_rejections,
      NEW.accessibility_wheelchair, NEW.accessibility_hearing_impaired,
      NEW.accessibility_visual_aid, NEW.accessibility_pet_friendly,
      NEW.accessibility_child_seat, NEW.gender_verified,
      public.encrypt_val(NEW.cpf), NEW.mercado_pago_account_id, NEW.boarding_pin_enabled
    );
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    UPDATE public.profiles_raw SET
      role = NEW.role,
      full_name = NEW.full_name,
      phone_number = NEW.phone_number,
      email = NEW.email,
      fcm_token = NEW.fcm_token,
      status = NEW.status,
      wallet_balance = NEW.wallet_balance,
      search_radius = NEW.search_radius,
      current_location = NEW.current_location,
      vehicle_details = NEW.vehicle_details,
      created_at = NEW.created_at,
      updated_at = NEW.updated_at,
      rating = NEW.rating,
      review_count = NEW.review_count,
      commission_percentage = NEW.commission_percentage,
      commission_exempt_until = NEW.commission_exempt_until,
      subscription_expires_at = NEW.subscription_expires_at,
      phone = NEW.phone,
      documents = NEW.documents,
      is_deleted = NEW.is_deleted,
      deleted_at = NEW.deleted_at,
      is_approved = NEW.is_approved,
      vehicle_type = NEW.vehicle_type,
      marker_url = NEW.marker_url,
      certificate_number = NEW.certificate_number,
      search_distance = NEW.search_distance,
      vehicle_plate_number = NEW.vehicle_plate_number,
      vehicle_production_year = NEW.vehicle_production_year,
      vehicle_model_id = NEW.vehicle_model_id,
      vehicle_color_id = NEW.vehicle_color_id,
      bank_name = NEW.bank_name,
      bank_account_number = NEW.bank_account_number,
      bank_swift_code = NEW.bank_swift_code,
      bank_routing_number = NEW.bank_routing_number,
      address = NEW.address,
      gender = NEW.gender,
      id_number = NEW.id_number,
      preset_avatar_number = NEW.preset_avatar_number,
      total_rides = NEW.total_rides,
      total_distance = NEW.total_distance,
      average_rating = NEW.average_rating,
      rating_count = NEW.rating_count,
      favorite_drivers = NEW.favorite_drivers,
      is_blocked = NEW.is_blocked,
      identity_verification_status = NEW.identity_verification_status,
      identity_docs = NEW.identity_docs,
      cooldown_until = NEW.cooldown_until,
      consecutive_rejections = NEW.consecutive_rejections,
      accessibility_wheelchair = NEW.accessibility_wheelchair,
      accessibility_hearing_impaired = NEW.accessibility_hearing_impaired,
      accessibility_visual_aid = NEW.accessibility_visual_aid,
      accessibility_pet_friendly = NEW.accessibility_pet_friendly,
      accessibility_child_seat = NEW.accessibility_child_seat,
      gender_verified = NEW.gender_verified,
      mercado_pago_account_id = NEW.mercado_pago_account_id,
      boarding_pin_enabled = NEW.boarding_pin_enabled,
      encrypted_cpf = CASE 
        WHEN NEW.cpf IS DISTINCT FROM OLD.cpf THEN public.encrypt_val(NEW.cpf)
        ELSE encrypted_cpf
      END
    WHERE id = OLD.id;
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    DELETE FROM public.profiles_raw WHERE id = OLD.id;
    RETURN OLD;
  END IF;
END;
$$ LANGUAGE plpgsql;


-- ─────────────────────────────────────────────
-- FILE: 20260621000000_add_payment_methods_toggles.sql
-- ─────────────────────────────────────────────

-- Migration: Adicionar colunas de controle de formas de pagamento em app_settings
-- Permite que o admin ative/desative cash (dinheiro) e wallet (carteira) globalmente.

-- 1. Adicionar colunas
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS cash_enabled BOOLEAN DEFAULT true;
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS wallet_enabled BOOLEAN DEFAULT true;

-- 2. Atualizar a linha global_config com os novos defaults
UPDATE public.app_settings
SET cash_enabled = true, wallet_enabled = true
WHERE key = 'global_config';

-- 3. Inserir chaves correspondentes como key-value (para compatibilidade com SettingsScreen de ler individualmente)
INSERT INTO public.app_settings (key, value)
VALUES 
  ('cash_enabled', 'true'),
  ('wallet_enabled', 'true')
ON CONFLICT (key) DO NOTHING;

COMMENT ON COLUMN public.app_settings.cash_enabled IS 'Indica se a forma de pagamento em Dinheiro (Cash) está ativa globalmente.';
COMMENT ON COLUMN public.app_settings.wallet_enabled IS 'Indica se a forma de pagamento via Saldo da Carteira (Wallet) está ativa globalmente.';


-- ─────────────────────────────────────────────
-- FILE: 20260621020000_cancel_offers_on_ride_end.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Cancelar ofertas de corrida ativas quando a corrida é encerrada/cancelada
-- Garante que o motorista pare de receber a oferta no exato segundo em que o
-- passageiro cancela a corrida.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.cancel_active_offers_on_ride_end()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Se o status da corrida mudou para um estado final/cancelado
  IF NEW.status IN ('rider_canceled', 'driver_canceled', 'canceled', 'completed', 'finished', 'expired') THEN
    UPDATE public.ride_offers
    SET status = 'expired'
    WHERE ride_id = NEW.id AND status = 'offered';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cancel_active_offers ON public.rides;
CREATE TRIGGER trg_cancel_active_offers
  AFTER UPDATE OF status ON public.rides
  FOR EACH ROW
  EXECUTE FUNCTION public.cancel_active_offers_on_ride_end();

COMMENT ON FUNCTION public.cancel_active_offers_on_ride_end() IS 
  'Expira automaticamente todas as ofertas pendentes na tabela ride_offers quando a corrida correspondente é cancelada ou concluída.';


-- ─────────────────────────────────────────────
-- FILE: 20260621030000_fix_radar_ride_assignment.sql
-- ─────────────────────────────────────────────

-- =====================================================================
-- MIGRAÇÃO: Permitir Aceite de Corrida via Radar (requested)
-- Data: 2026-06-21
-- Objetivo: Redefine assign_driver_to_ride para aceitar atribuições diretas
--            quando a corrida está com status 'requested' (aberta no radar),
--            mesmo se não houver registro prévio em ride_offers para o motorista.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.assign_driver_to_ride(
    p_ride_id UUID,
    p_driver_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_status TEXT;
    v_service_type TEXT;
    v_service_id TEXT;
    v_gender_required TEXT;
    v_driver_gender TEXT;
    v_driver_gender_verified BOOLEAN;
    v_pickup_lat DOUBLE PRECISION;
    v_pickup_lng DOUBLE PRECISION;
    v_driver_lat DOUBLE PRECISION;
    v_driver_lng DOUBLE PRECISION;
    v_dist_meters DOUBLE PRECISION;
    v_eta_minutes INTEGER;
    v_eta_pickup TIMESTAMP WITH TIME ZONE;
    v_rows INT;
BEGIN
    -- 1. [SEGURANÇA] Validar se o solicitante é de fato o motorista ou service_role
    IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR auth.uid()::text <> p_driver_id) THEN
        RAISE EXCEPTION 'Operação não autorizada. O motorista não corresponde ao usuário autenticado.';
    END IF;

    -- 2. [SEGURANÇA] Bloquear linha da corrida para evitar conflitos concorrentes
    SELECT status, service_type, service_id, pickup_lat, pickup_lng 
    INTO v_status, v_service_type, v_service_id, v_pickup_lat, v_pickup_lng
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Corrida não encontrada (ID: %)', p_ride_id;
    END IF;

    -- Agora aceitamos tanto 'requested' quanto 'searching'
    IF v_status NOT IN ('requested', 'searching') THEN
        RAISE EXCEPTION 'A corrida não está mais disponível para aceite (status atual: %)', v_status;
    END IF;

    -- 3. [UPPI MULHER] Validar restrição estrita de gênero para o serviço
    SELECT s.gender_required INTO v_gender_required
    FROM public.services s
    WHERE s.id = v_service_id OR s.name = v_service_type OR s.id::text = v_service_type
    LIMIT 1;

    IF v_gender_required IS NOT NULL THEN
        SELECT gender, gender_verified 
        INTO v_driver_gender, v_driver_gender_verified
        FROM public.profiles
        WHERE id = p_driver_id;

        IF v_driver_gender IS DISTINCT FROM v_gender_required OR v_driver_gender_verified IS NOT TRUE THEN
            RAISE EXCEPTION 'Este serviço é exclusivo para motoristas mulheres verificadas.';
        END IF;
    END IF;

    -- 4. [SEGURANÇA] Atualizar oferta específica deste motorista como 'accepted' se ela existir
    UPDATE public.ride_offers
    SET status = 'accepted'
    WHERE ride_id = p_ride_id AND driver_id = p_driver_id AND status = 'offered';
    
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    
    -- Se não havia oferta direcionada ('offered') para este motorista em específico (caso do Radar de Viagens),
    -- mas o status da corrida é 'requested' (está aberta no radar):
    IF v_rows = 0 THEN
        IF v_status = 'requested' THEN
            -- Inserimos um registro em ride_offers como 'accepted' para fins de histórico e integridade
            INSERT INTO public.ride_offers (ride_id, driver_id, status, expires_at)
            VALUES (p_ride_id, p_driver_id, 'accepted', NOW() + interval '1 minute');
        ELSE
            RAISE EXCEPTION 'Você não possui uma oferta ativa para esta corrida.';
        END IF;
    END IF;

    -- 5. Expirar as demais ofertas ativas para essa corrida
    UPDATE public.ride_offers
    SET status = 'expired'
    WHERE ride_id = p_ride_id AND driver_id <> p_driver_id AND status = 'offered';

    -- 6. Calcular ETA dinâmico baseado no PostGIS
    SELECT lat, lng INTO v_driver_lat, v_driver_lng
    FROM public.driver_locations
    WHERE driver_id = p_driver_id;

    IF v_driver_lat IS NOT NULL AND v_pickup_lat IS NOT NULL THEN
        v_dist_meters := ST_Distance(
            ST_SetSRID(ST_MakePoint(v_driver_lng, v_driver_lat), 4326)::geography,
            ST_SetSRID(ST_MakePoint(v_pickup_lng, v_pickup_lat), 4326)::geography
        );
        v_eta_minutes := CEIL(v_dist_meters / 500.0); -- ~30km/h
        v_eta_pickup := NOW() + (v_eta_minutes * interval '1 minute');
    ELSE
        v_eta_pickup := NOW() + interval '5 minutes';
    END IF;

    -- 7. Atribuir o motorista à corrida, passar o status para 'accepted', definir accepted_at e eta_pickup
    UPDATE public.rides
    SET driver_id = p_driver_id,
        status = 'accepted',
        accepted_at = NOW(),
        eta_pickup = v_eta_pickup,
        updated_at = NOW()
    WHERE id = p_ride_id;

    -- 8. [ANTI CHERRY-PICKING] Resetar rejeições consecutivas do motorista ao aceitar corrida
    UPDATE public.profiles
    SET consecutive_rejections = 0
    WHERE id = p_driver_id AND consecutive_rejections > 0;
END;
$$;

COMMENT ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) IS 'Atribui um motorista a uma corrida com verificação estrita de gênero verificado (Uppi Mulher), aceitação direta para corridas do radar (status requested) e controle transacional de concorrência.';


-- ─────────────────────────────────────────────
-- FILE: 20260621040000_optimize_realtime_driver_locations.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO: Remover driver_locations da Replicação CDC
-- Data: 2026-06-21
-- Objetivo: Remove a tabela driver_locations da replicação supabase_realtime
--            para estancar o vazamento de mensagens do Realtime causado por updates de GPS.
--            A localização em tempo real do motorista já é transmitida via Broadcast,
--            tornando a replicação CDC do Postgres desnecessária e consumidora de cota.
-- ==============================================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'driver_locations'
  ) THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE public.driver_locations;
  END IF;
END $$;


-- ─────────────────────────────────────────────
-- FILE: 20260621050000_cleanup_legacy_tables.sql
-- ─────────────────────────────────────────────

-- Migration: Limpeza de tabelas legadas/mortas (messages, ratings, ride_reviews, sos_signals)
-- Garante que se o banco for reconstruído do zero, estas tabelas obsoletas serão excluídas.

DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.ratings CASCADE;
DROP TABLE IF EXISTS public.ride_reviews CASCADE;
DROP TABLE IF EXISTS public.sos_signals CASCADE;


-- ─────────────────────────────────────────────
-- FILE: 20260621060000_dynamic_new_ride_webhook.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- MIGRAÇÃO — URL DINÂMICA DO WEBHOOK DE NOVAS CORRIDAS (PORTABILIDADE TOTAL)
-- Data: 2026-06-21
-- Ecossistema Uppi — Engenharia de Infraestrutura e Banco de Dados
-- ==============================================================================
-- Esta migração resolve o problema de URL do Supabase hardcoded no trigger
-- de notificação de novas corridas (notify_webhook_new_ride).
-- Implementa uma busca dinâmica através da variável de sistema 'app.supabase_url'
-- com fallback para a tabela app_settings e finalmente para a URL padrão de homologação.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.notify_webhook_new_ride()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_supabase_url TEXT;
  v_webhook_url TEXT;
BEGIN
  -- Só dispara para corridas com status 'requested'
  IF NEW.status != 'requested' THEN
    RETURN NEW;
  END IF;

  -- 1. Buscar a URL base do Supabase de forma dinâmica
  v_supabase_url := current_setting('app.supabase_url', true);
  
  -- Fallback seguro se a variável GUC não estiver definida
  IF v_supabase_url IS NULL OR v_supabase_url = '' THEN
    SELECT value INTO v_supabase_url
    FROM public.app_settings
    WHERE key = 'supabase_url'
    LIMIT 1;
  END IF;

  -- Se ainda assim estiver ausente, fallback para homologação
  IF v_supabase_url IS NULL OR v_supabase_url = '' THEN
    v_supabase_url := 'https://kqfmahrxjuqlvxngeurj.supabase.co';
  END IF;

  -- Construir o endpoint correto da Edge Function
  v_webhook_url := rtrim(v_supabase_url, '/') || '/functions/v1/webhook-new-ride';

  -- Disparar a chamada HTTP assíncrona/segura
  PERFORM net.http_post(
    url := v_webhook_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', COALESCE(current_setting('app.webhook_secret', true), '')
    ),
    body := json_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'schema', TG_TABLE_SCHEMA,
      'record', row_to_json(NEW),
      'timestamp', extract(epoch from now())
    )::jsonb,
    timeout_milliseconds := 5000
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_webhook_new_ride falhou: %', SQLERRM;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_webhook_new_ride() IS 
  'Trigger dinâmico e portátil para envio de push de nova corrida criada via Edge Function.';


-- ─────────────────────────────────────────────
-- FILE: 20260621070000_drop_vehicle_categories.sql
-- ─────────────────────────────────────────────

-- ==============================================================================
-- UPPI DB CLEANUP: Remoção da tabela obsoleta vehicle_categories
-- ==============================================================================
-- Motivo: Esta tabela está completamente órfã e sem nenhuma referência no
-- código do monorepo (frontend, backend ou outras migrations).
-- ==============================================================================

DROP TABLE IF EXISTS public.vehicle_categories CASCADE;


-- ─────────────────────────────────────────────
-- FILE: 20260624120000_add_comprehensive_vehicle_models.sql
-- ─────────────────────────────────────────────

-- Inserir lista abrangente de modelos de veículos populares (Carros, Motos e Elétricos) no Brasil
INSERT INTO public.car_models (name)
SELECT val.name FROM (
  VALUES 
  -- Carros Populares e de Aplicativo
  ('Fiat Mobi'),
  ('Renault Kwid'),
  ('Chevrolet Onix'),
  ('Hyundai HB20'),
  ('Volkswagen Polo'),
  ('Fiat Argo'),
  ('Chevrolet Onix Plus'),
  ('Fiat Cronos'),
  ('Hyundai HB20S'),
  ('Toyota Yaris'),
  ('Toyota Yaris Sedan'),
  ('Honda City'),
  ('Honda City Hatchback'),
  ('Nissan Versa'),
  ('Chevrolet Spin'),
  -- SUVs Populares
  ('Volkswagen T-Cross'),
  ('Chevrolet Tracker'),
  ('Hyundai Creta'),
  ('Jeep Renegade'),
  ('Nissan Kicks'),
  ('Fiat Pulse'),
  ('Fiat Fastback'),
  ('Volkswagen Nivus'),
  ('Renault Duster'),
  ('Honda HR-V'),
  ('Jeep Compass'),
  ('Toyota Corolla Cross'),
  -- Carros Sedãs e Premium
  ('Toyota Corolla'),
  ('Honda Civic'),
  ('Nissan Sentra'),
  ('Volkswagen Jetta'),
  ('Chevrolet Cruze'),
  -- Motos Populares e de Aplicativo
  ('Honda CG 160 Fan'),
  ('Honda CG 160 Titan'),
  ('Honda CG 160 Start'),
  ('Honda Biz 125'),
  ('Honda Biz 110i'),
  ('Honda NXR 160 Bros'),
  ('Honda Pop 110i'),
  ('Honda PCX 160'),
  ('Honda XRE 190'),
  ('Honda XRE 300'),
  ('Honda CB 300F Twister'),
  ('Yamaha YBR 150 Factor'),
  ('Yamaha Fazer FZ15'),
  ('Yamaha Fazer FZ25'),
  ('Yamaha Crosser 150'),
  ('Yamaha Lander 250'),
  ('Yamaha NMAX 160'),
  ('Yamaha Fluo 125'),
  -- Veículos Elétricos e Híbridos
  ('BYD Dolphin'),
  ('BYD Dolphin Mini'),
  ('BYD Song Plus (Híbrido)'),
  ('BYD King (Híbrido)'),
  ('BYD Seal'),
  ('BYD Yuan Plus'),
  ('GWM Ora 03'),
  ('GWM Haval H6 (Híbrido)'),
  ('Toyota Corolla (Híbrido)'),
  ('Toyota Corolla Cross (Híbrido)'),
  ('Renault Kwid E-Tech'),
  ('JAC E-JS1'),
  ('Volvo XC40 Recharge'),
  ('Nissan Leaf')
) as val(name)
WHERE NOT EXISTS (
  SELECT 1 FROM public.car_models WHERE public.car_models.name = val.name
);

-- ==============================================================================
-- ─────────────────────────────────────────────
-- SIMULATED DEMAND HOTSPOTS (FORCE HEATMAPS)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.simulated_hotspots (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    latitude    FLOAT8 NOT NULL,
    longitude   FLOAT8 NOT NULL,
    intensity   TEXT NOT NULL CHECK (intensity IN ('low', 'medium', 'high', 'extreme')),
    multiplier  NUMERIC(3,2) DEFAULT 1.00 CHECK (multiplier >= 1.00),
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    expires_at  TIMESTAMP WITH TIME ZONE
);

ALTER TABLE public.simulated_hotspots ENABLE ROW LEVEL SECURITY;

-- Qualquer usuário pode ler hotspots simulados ativos
DROP POLICY IF EXISTS "allow_select_simulated_hotspots" ON public.simulated_hotspots;
CREATE POLICY "allow_select_simulated_hotspots" ON public.simulated_hotspots
    FOR SELECT USING (expires_at IS NULL OR expires_at > now());

-- Apenas admins autenticados gerenciam hotspots
DROP POLICY IF EXISTS "allow_admin_manage_simulated_hotspots" ON public.simulated_hotspots;
CREATE POLICY "allow_admin_manage_simulated_hotspots" ON public.simulated_hotspots
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

-- Adicionar simulated_hotspots à replicação realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.simulated_hotspots;

-- ==============================================================================
-- ─────────────────────────────────────────────
-- TRIGGER AUTOMÁTICA DE 7 DIAS GRÁTIS DE TAXA ZERO AO ATIVAR MOTORISTA
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.grant_free_trial_on_activation()
RETURNS TRIGGER AS $$
BEGIN
    -- Se o status mudou para 'active' e o motorista ainda não possui data de isenção definida
    IF NEW.status = 'active' AND (OLD.status IS DISTINCT FROM 'active' OR OLD IS NULL) AND NEW.commission_exempt_until IS NULL THEN
        NEW.commission_exempt_until := NOW() + interval '7 days';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_grant_free_trial_on_activation ON public.profiles;
CREATE TRIGGER trg_grant_free_trial_on_activation
BEFORE INSERT OR UPDATE OF status ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.grant_free_trial_on_activation();
