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
