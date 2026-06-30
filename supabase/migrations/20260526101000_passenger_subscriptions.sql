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

