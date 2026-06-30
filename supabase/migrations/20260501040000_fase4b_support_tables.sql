-- ==============================================================================
-- MIGRAÇÃO FASE 4B — UPPI BRASIL
-- Tabelas de suporte: ride_reviews, ride_messages, sos_signals,
--                     driver_locations, car_models, car_colors
-- ==============================================================================

-- 1. RIDE REVIEWS
CREATE TABLE IF NOT EXISTS public.ride_reviews (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ride_id TEXT NOT NULL,
    reviewer_id TEXT NOT NULL REFERENCES public.profiles(id),
    rating INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
    review TEXT,
    role TEXT DEFAULT 'rider',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
ALTER TABLE public.ride_reviews ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='ride_reviews' AND policyname='Inserir review') THEN
    CREATE POLICY "Inserir review" ON public.ride_reviews FOR INSERT TO authenticated WITH CHECK (reviewer_id = auth.uid()::text);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='ride_reviews' AND policyname='Ler reviews') THEN
    CREATE POLICY "Ler reviews" ON public.ride_reviews FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- 2. RIDE MESSAGES (chat em tempo real entre motorista e passageiro)
CREATE TABLE IF NOT EXISTS public.ride_messages (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ride_id TEXT NOT NULL,
    sender_id TEXT NOT NULL REFERENCES public.profiles(id),
    content TEXT NOT NULL,
    sent_by_driver BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
ALTER TABLE public.ride_messages ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='ride_messages' AND policyname='Enviar mensagem') THEN
    CREATE POLICY "Enviar mensagem" ON public.ride_messages FOR INSERT TO authenticated WITH CHECK (sender_id = auth.uid()::text);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='ride_messages' AND policyname='Ler mensagens da corrida') THEN
    CREATE POLICY "Ler mensagens da corrida" ON public.ride_messages FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- Habilitar Realtime para chat
ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_messages;

-- 3. SOS SIGNALS
CREATE TABLE IF NOT EXISTS public.sos_signals (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ride_id TEXT NOT NULL,
    submitted_by TEXT NOT NULL REFERENCES public.profiles(id),
    status TEXT DEFAULT 'Submitted',
    role TEXT DEFAULT 'rider',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
ALTER TABLE public.sos_signals ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sos_signals' AND policyname='Enviar SOS') THEN
    CREATE POLICY "Enviar SOS" ON public.sos_signals FOR INSERT TO authenticated WITH CHECK (submitted_by = auth.uid()::text);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sos_signals' AND policyname='Ler SOS') THEN
    CREATE POLICY "Ler SOS" ON public.sos_signals FOR SELECT TO authenticated USING (submitted_by = auth.uid()::text);
  END IF;
END $$;

-- 4. DRIVER LOCATIONS (rastreio em tempo real)
CREATE TABLE IF NOT EXISTS public.driver_locations (
    driver_id TEXT PRIMARY KEY REFERENCES public.profiles(id),
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    heading DOUBLE PRECISION DEFAULT 0,
    vehicle_type TEXT DEFAULT 'carro',
    marker_url TEXT,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
ALTER TABLE public.driver_locations ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='driver_locations' AND policyname='Motorista atualiza propria loc') THEN
    CREATE POLICY "Motorista atualiza propria loc" ON public.driver_locations FOR ALL TO authenticated
      USING (driver_id = auth.uid()::text) WITH CHECK (driver_id = auth.uid()::text);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='driver_locations' AND policyname='Ler localizacoes motoristas') THEN
    CREATE POLICY "Ler localizacoes motoristas" ON public.driver_locations FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- Habilitar Realtime para rastreio
ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_locations;

-- 5. CAR MODELS (referência para registro de veículos)
CREATE TABLE IF NOT EXISTS public.car_models (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
ALTER TABLE public.car_models ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='car_models' AND policyname='Ler modelos') THEN
    CREATE POLICY "Ler modelos" ON public.car_models FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- Seed data: modelos populares no Brasil
INSERT INTO public.car_models (name) VALUES
  ('Chevrolet Onix'), ('Fiat Argo'), ('Hyundai HB20'),
  ('Volkswagen Gol'), ('Toyota Corolla'), ('Honda Civic'),
  ('Fiat Mobi'), ('Renault Kwid'), ('Chevrolet Prisma'),
  ('Volkswagen Polo'), ('Fiat Cronos'), ('Nissan Kicks')
ON CONFLICT DO NOTHING;

-- 6. CAR COLORS (referência para cores de veículos)
CREATE TABLE IF NOT EXISTS public.car_colors (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
ALTER TABLE public.car_colors ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='car_colors' AND policyname='Ler cores') THEN
    CREATE POLICY "Ler cores" ON public.car_colors FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- Seed data: cores comuns
INSERT INTO public.car_colors (name) VALUES
  ('Preto'), ('Branco'), ('Prata'), ('Cinza'),
  ('Vermelho'), ('Azul'), ('Verde'), ('Amarelo'),
  ('Marrom'), ('Bege')
ON CONFLICT DO NOTHING;

-- 7. Colunas extras em profiles para driver registration
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_approved BOOLEAN DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS vehicle_type TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS marker_url TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS certificate_number TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS search_distance INT DEFAULT 5000;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS vehicle_plate_number TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS vehicle_production_year INT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS vehicle_model_id TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS vehicle_color_id TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bank_name TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bank_account_number TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bank_swift_code TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bank_routing_number TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS gender TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS id_number TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS preset_avatar_number INT;

-- ==============================================================================
-- FIM DA MIGRAÇÃO FASE 4B
-- ==============================================================================
