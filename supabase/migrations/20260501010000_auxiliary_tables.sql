-- ==============================================================================
-- MIGRAÇÃO: Tabelas auxiliares para funcionalidades do app
-- services, cancel_reasons, messages, complaints, sos_signals
-- ==============================================================================

-- 1. TIPOS DE SERVIÇO (Standard, SUV, Moto etc.)
CREATE TABLE IF NOT EXISTS public.services (
    id TEXT NOT NULL PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    image_url TEXT,
    base_fare DECIMAL(10, 2) DEFAULT 5.00,
    per_km_fare DECIMAL(10, 2) DEFAULT 2.00,
    per_minute_fare DECIMAL(10, 2) DEFAULT 0.50,
    minimum_fare DECIMAL(10, 2) DEFAULT 7.00,
    surge_multiplier DECIMAL(5, 2) DEFAULT 1.00,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);
ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Leitura de Serviços" ON public.services FOR SELECT USING (true);

-- 2. MOTIVOS DE CANCELAMENTO
CREATE TABLE IF NOT EXISTS public.cancel_reasons (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    role TEXT DEFAULT 'rider' CHECK (role IN ('rider', 'driver')),
    is_active BOOLEAN DEFAULT TRUE
);
ALTER TABLE public.cancel_reasons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Leitura de Motivos" ON public.cancel_reasons FOR SELECT USING (true);

-- Dados padrão de motivos de cancelamento
INSERT INTO public.cancel_reasons (name, role) VALUES
  ('Motorista demorou muito', 'rider'),
  ('Solicitei por engano', 'rider'),
  ('Mudei de planos', 'rider'),
  ('Problemas pessoais', 'rider'),
  ('Passageiro não apareceu', 'driver'),
  ('Trânsito excessivo', 'driver'),
  ('Problemas no carro', 'driver'),
  ('Motivos pessoais', 'driver')
ON CONFLICT DO NOTHING;

-- 3. MENSAGENS DE CHAT EM TEMPO REAL
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ride_id UUID REFERENCES public.rides(id) ON DELETE CASCADE NOT NULL,
    sender_id TEXT REFERENCES public.profiles(id) NOT NULL,
    content TEXT NOT NULL,
    sent_by_driver BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Leitura de Mensagens" ON public.messages
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.rides
            WHERE rides.id = messages.ride_id
            AND (rides.rider_id = auth.uid()::text OR rides.driver_id = auth.uid()::text)
        )
    );
CREATE POLICY "Envio de Mensagens" ON public.messages
    FOR INSERT WITH CHECK (auth.uid()::text = sender_id);

-- 4. RECLAMAÇÕES PÓS-CORRIDA
CREATE TABLE IF NOT EXISTS public.complaints (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ride_id TEXT,
    user_id TEXT REFERENCES public.profiles(id),
    role TEXT CHECK (role IN ('rider', 'driver')),
    subject TEXT NOT NULL,
    content TEXT NOT NULL,
    status TEXT DEFAULT 'submitted' CHECK (status IN ('submitted', 'in_review', 'resolved', 'closed')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);
ALTER TABLE public.complaints ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Criar Reclamação" ON public.complaints FOR INSERT WITH CHECK (auth.uid()::text = user_id);
CREATE POLICY "Ver próprias reclamações" ON public.complaints FOR SELECT USING (auth.uid()::text = user_id);

-- 5. SINAIS DE SOS
CREATE TABLE IF NOT EXISTS public.sos_signals (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ride_id TEXT,
    submitted_by TEXT REFERENCES public.profiles(id),
    role TEXT CHECK (role IN ('rider', 'driver')),
    status TEXT DEFAULT 'submitted',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);
ALTER TABLE public.sos_signals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Criar SOS" ON public.sos_signals FOR INSERT WITH CHECK (auth.uid()::text = submitted_by);
