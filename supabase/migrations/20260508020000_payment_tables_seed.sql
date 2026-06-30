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
