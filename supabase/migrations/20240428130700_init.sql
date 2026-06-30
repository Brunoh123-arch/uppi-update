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
