-- Fix 1: adicionar colunas faltantes em rides
ALTER TABLE rides ADD COLUMN IF NOT EXISTS eta_pickup TIMESTAMPTZ;
ALTER TABLE rides ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;

-- Fix 2: incluir estados intermediários no constraint
ALTER TABLE rides DROP CONSTRAINT IF EXISTS rides_status_check;
ALTER TABLE rides ADD CONSTRAINT rides_status_check CHECK (
  status IN ('requested','found','no_close_found','booked','accepted',
             'driver_accepted','arrived','started','in_progress',
             'completed','finished','waiting_for_review',
             'canceled','rider_canceled','driver_canceled',
             'expired','no_driver')
);

-- Fix 3: derrubar a versão UUID conflitante e manter só a TEXT
DROP FUNCTION IF EXISTS public.increment_wallet(UUID, NUMERIC);

-- Fix 4: corrigir tipos na tabela ratings e políticas RLS
-- 1. Drop de políticas RLS existentes
DROP POLICY IF EXISTS ratings_select ON public.ratings;
DROP POLICY IF EXISTS ratings_insert ON public.ratings;
DROP POLICY IF EXISTS ratings_update ON public.ratings;
DROP POLICY IF EXISTS ratings_select_auth ON public.ratings;
DROP POLICY IF EXISTS ratings_insert_auth ON public.ratings;
DROP POLICY IF EXISTS ratings_update_auth ON public.ratings;

-- 2. Drop de foreign keys antigas
ALTER TABLE public.ratings DROP CONSTRAINT IF EXISTS ratings_rated_by_fkey;
ALTER TABLE public.ratings DROP CONSTRAINT IF EXISTS ratings_rated_user_fkey;

-- 3. Alterar os tipos das colunas para TEXT
ALTER TABLE public.ratings ALTER COLUMN rated_by TYPE TEXT;
ALTER TABLE public.ratings ALTER COLUMN rated_user TYPE TEXT;

-- 4. Criar novas foreign keys apontando para public.profiles(id)
ALTER TABLE public.ratings ADD CONSTRAINT ratings_rated_by_fkey FOREIGN KEY (rated_by) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.ratings ADD CONSTRAINT ratings_rated_user_fkey FOREIGN KEY (rated_user) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- 5. Recriar políticas RLS
CREATE POLICY "ratings_select" ON public.ratings FOR SELECT USING (true);
CREATE POLICY "ratings_insert" ON public.ratings FOR INSERT WITH CHECK (auth.uid()::text = rated_by);
CREATE POLICY "ratings_update" ON public.ratings FOR UPDATE USING (auth.uid()::text = rated_by);
