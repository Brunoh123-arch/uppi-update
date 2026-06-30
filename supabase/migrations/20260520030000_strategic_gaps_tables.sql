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
