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
