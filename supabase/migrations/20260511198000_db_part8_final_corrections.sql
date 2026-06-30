-- ==============================================================================
-- REVISÃO TOTAL — Parte 7: Últimos ajustes nas funções finais analisadas
-- ==============================================================================

-- 1. DRIVER_EARNINGS - completando as colunas que estavam faltando
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_earnings' AND column_name='gross_amount') THEN
    ALTER TABLE public.driver_earnings ADD COLUMN gross_amount NUMERIC(10, 2);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_earnings' AND column_name='commission_pct') THEN
    ALTER TABLE public.driver_earnings ADD COLUMN commission_pct NUMERIC(5, 2);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_earnings' AND column_name='commission_amt') THEN
    ALTER TABLE public.driver_earnings ADD COLUMN commission_amt NUMERIC(10, 2);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_earnings' AND column_name='net_amount') THEN
    ALTER TABLE public.driver_earnings ADD COLUMN net_amount NUMERIC(10, 2);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='driver_earnings' AND column_name='payment_method') THEN
    ALTER TABLE public.driver_earnings ADD COLUMN payment_method TEXT;
  END IF;
END $$;

-- 2. RATINGS - tabela ausente sendo usada em rate_ride
CREATE TABLE IF NOT EXISTS public.ratings (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ride_id UUID REFERENCES public.rides(id) ON DELETE CASCADE,
    rated_by UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    rated_user UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    score INTEGER CHECK (score >= 1 AND score <= 5),
    comment TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(ride_id, rated_by)
);

ALTER TABLE public.ratings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ratings_select" ON public.ratings FOR SELECT USING (true);
CREATE POLICY "ratings_insert" ON public.ratings FOR INSERT WITH CHECK (auth.uid() = rated_by);
CREATE POLICY "ratings_update" ON public.ratings FOR UPDATE USING (auth.uid() = rated_by);

-- 3. RIDES - completando tracking_token e avaliações (faltando completed_at, rider_rating, driver_rating)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rides' AND column_name='rider_rating') THEN
    ALTER TABLE public.rides ADD COLUMN rider_rating INTEGER;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rides' AND column_name='driver_rating') THEN
    ALTER TABLE public.rides ADD COLUMN driver_rating INTEGER;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rides' AND column_name='completed_at') THEN
    ALTER TABLE public.rides ADD COLUMN completed_at TIMESTAMP WITH TIME ZONE;
  END IF;
END $$;

-- 4. FIX NA FUNÇÃO COMPLETE RIDE NO BANCO (se existir)
-- Isso atualiza as assinaturas da função complete_ride para não causarem mais erros se forem chamadas no banco
CREATE OR REPLACE FUNCTION increment_wallet(p_user_id UUID, p_amount NUMERIC)
RETURNS VOID AS $$
BEGIN
  UPDATE wallets
  SET balance = balance + p_amount,
      updated_at = NOW()
  WHERE user_id = p_user_id;

  -- Se a carteira não existir, ela será criada com o saldo inicial pelo trigger set_initial_wallet_balance que criamos antes.
  IF NOT FOUND THEN
    INSERT INTO wallets (user_id, balance) VALUES (p_user_id, p_amount);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Garantir que a policy RLS no wallets permite inserção para a trigger
DROP POLICY IF EXISTS "wallets_insert" ON public.wallets;
CREATE POLICY "wallets_insert" ON public.wallets FOR INSERT WITH CHECK (auth.uid()::text = user_id OR (EXISTS (SELECT 1 FROM public.admins WHERE admins.id::text = auth.uid()::text)));

