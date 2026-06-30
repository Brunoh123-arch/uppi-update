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
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS commission_rate NUMERIC(5,2) DEFAULT 15.00;
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'BRL';
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS map_provider TEXT DEFAULT 'googleMaps';
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS global_surge_multiplier NUMERIC(4,2) DEFAULT 1.00;
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS google_map_api_key TEXT DEFAULT '';

-- Garantir que existe pelo menos uma row de configuração para o admin usar
INSERT INTO public.app_settings (key, value, driver_search_radius, commission_rate, currency, map_provider, global_surge_multiplier, google_map_api_key)
VALUES ('global_config', 'master', 10, 15.00, 'BRL', 'googleMaps', 1.00, '')
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
