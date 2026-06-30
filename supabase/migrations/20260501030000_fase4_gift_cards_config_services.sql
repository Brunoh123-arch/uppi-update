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
    commission_percent NUMERIC DEFAULT 15.0,
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
VALUES ('pricing', 1.0, 15.0)
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
