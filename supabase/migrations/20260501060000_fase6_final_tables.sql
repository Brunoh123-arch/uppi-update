-- Migration: Create missing tables and storage buckets for Uppi App
-- Date: 2026-05-01

-- 1. Create Cancel Reasons
CREATE TABLE IF NOT EXISTS public.cancel_reasons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('rider', 'driver')),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed basic cancel reasons
INSERT INTO public.cancel_reasons (name, role) VALUES 
('Motorista demorou muito', 'rider'),
('Solicitei por engano', 'rider'),
('Mudei de planos', 'rider'),
('Problemas pessoais', 'rider'),
('Passageiro não apareceu', 'driver'),
('Local de difícil acesso', 'driver'),
('Problemas mecânicos', 'driver')
ON CONFLICT DO NOTHING;

-- 2. Create Complaints
CREATE TABLE IF NOT EXISTS public.complaints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id UUID NOT NULL,
    user_id TEXT NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('rider', 'driver')),
    subject TEXT NOT NULL,
    content TEXT NOT NULL,
    status TEXT DEFAULT 'submitted',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Create Car Models
CREATE TABLE IF NOT EXISTS public.car_models (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed common car models
INSERT INTO public.car_models (name) VALUES 
('Chevrolet Onix'), ('Hyundai HB20'), ('Volkswagen Polo'), 
('Fiat Argo'), ('Jeep Renegade'), ('Toyota Corolla'), ('Honda Civic')
ON CONFLICT DO NOTHING;

-- 4. Create Car Colors
CREATE TABLE IF NOT EXISTS public.car_colors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed common colors
INSERT INTO public.car_colors (name) VALUES 
('Branco'), ('Preto'), ('Prata'), ('Cinza'), ('Vermelho'), ('Azul')
ON CONFLICT DO NOTHING;

-- 5. Create Driver Locations
CREATE TABLE IF NOT EXISTS public.driver_locations (
    driver_id TEXT PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    heading DOUBLE PRECISION DEFAULT 0.0,
    vehicle_type TEXT DEFAULT 'carro',
    marker_url TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on all new tables
ALTER TABLE public.cancel_reasons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.complaints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.car_models ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.car_colors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.driver_locations ENABLE ROW LEVEL SECURITY;

-- 6. RLS Policies
-- cancel_reasons, car_models, car_colors: anyone can read
CREATE POLICY "Public read cancel_reasons" ON public.cancel_reasons FOR SELECT USING (true);
CREATE POLICY "Public read car_models" ON public.car_models FOR SELECT USING (true);
CREATE POLICY "Public read car_colors" ON public.car_colors FOR SELECT USING (true);

-- complaints: users can insert and read their own
CREATE POLICY "Users can insert complaints" ON public.complaints FOR INSERT WITH CHECK (auth.uid()::text = user_id);
CREATE POLICY "Users can view own complaints" ON public.complaints FOR SELECT USING (auth.uid()::text = user_id);

-- driver_locations: drivers can upsert their own, riders can read all
CREATE POLICY "Drivers can update own location" ON public.driver_locations FOR ALL USING (auth.uid()::text = driver_id) WITH CHECK (auth.uid()::text = driver_id);
CREATE POLICY "Anyone can read driver locations" ON public.driver_locations FOR SELECT USING (true);

-- 7. Storage Bucket: identity-docs
INSERT INTO storage.buckets (id, name, public) 
VALUES ('identity-docs', 'identity-docs', true)
ON CONFLICT (id) DO NOTHING;

-- Storage Policies for identity-docs
CREATE POLICY "Public access to identity-docs" ON storage.objects FOR SELECT USING (bucket_id = 'identity-docs');
CREATE POLICY "Auth users can upload identity-docs" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'identity-docs' AND auth.role() = 'authenticated');
CREATE POLICY "Users can update their own identity-docs" ON storage.objects FOR UPDATE USING (bucket_id = 'identity-docs' AND auth.uid()::text = (storage.foldername(name))[2]);
