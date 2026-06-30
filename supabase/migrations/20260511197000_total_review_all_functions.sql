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
