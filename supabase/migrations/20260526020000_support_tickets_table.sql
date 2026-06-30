-- ==============================================================================
-- MIGRAÇÃO DE SUPORTE TICKETS — UPPI BRASIL
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.support_tickets (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES public.profiles(id),
    subject TEXT NOT NULL,
    message TEXT NOT NULL,
    category TEXT DEFAULT 'geral',
    status TEXT DEFAULT 'open',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='support_tickets' AND policyname='Inserir ticket de suporte') THEN
    CREATE POLICY "Inserir ticket de suporte" ON public.support_tickets FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid()::text);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='support_tickets' AND policyname='Ler proprios tickets de suporte') THEN
    CREATE POLICY "Ler proprios tickets de suporte" ON public.support_tickets FOR SELECT TO authenticated USING (user_id = auth.uid()::text);
  END IF;
END $$;
