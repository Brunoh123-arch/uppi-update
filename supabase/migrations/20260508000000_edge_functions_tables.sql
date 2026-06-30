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
