-- ==============================================================================
-- MIGRAÇÃO CRÍTICA — CORRIGE RLS de profiles + cria wallet + RPC increment
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. PROFILES: Permitir que usuários autenticados leiam dados PÚBLICOS
--    de outros perfis (nome, foto, rating) — necessário para rider↔driver
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Usuário lê próprio perfil" ON public.profiles;

-- Nova policy: qualquer autenticado pode ler dados públicos de qualquer perfil
-- (full_name, avatar_url, rating, vehicle_type, etc.)
CREATE POLICY "Authenticated users can read profiles"
  ON public.profiles FOR SELECT TO authenticated
  USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WALLETS: Tabela de carteira para motoristas e passageiros
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.wallets (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT NOT NULL UNIQUE REFERENCES public.profiles(id),
    balance NUMERIC(12,2) DEFAULT 0.00 NOT NULL,
    currency TEXT DEFAULT 'BRL',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='wallets' AND policyname='User reads own wallet') THEN
    CREATE POLICY "User reads own wallet" ON public.wallets
      FOR SELECT TO authenticated
      USING (user_id = auth.uid()::text);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='wallets' AND policyname='User inserts own wallet') THEN
    CREATE POLICY "User inserts own wallet" ON public.wallets
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid()::text);
  END IF;
END $$;

-- Admin pode ver/atualizar qualquer wallet
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='wallets' AND policyname='admin_wallets_all') THEN
    CREATE POLICY "admin_wallets_all" ON public.wallets
      FOR ALL TO authenticated
      USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator'))
      );
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. RPC increment_wallet — atualiza saldo de forma atômica (SECURITY DEFINER)
--    Aceita valores negativos (dedução de comissão) e positivos (recarga)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.increment_wallet(
  target_user_id TEXT,
  amount_to_add NUMERIC
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Cria wallet se não existir
  INSERT INTO public.wallets (user_id, balance)
  VALUES (target_user_id, 0)
  ON CONFLICT (user_id) DO NOTHING;

  -- Atualiza o saldo atomicamente
  UPDATE public.wallets
  SET balance = balance + amount_to_add,
      updated_at = now()
  WHERE user_id = target_user_id;
END;
$$;

-- Permitir que qualquer autenticado chame a RPC
-- (a função é SECURITY DEFINER, então executa com permissões do owner)
GRANT EXECUTE ON FUNCTION public.increment_wallet TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Habilitar Realtime na wallets (para o app ver saldo atualizar em tempo real)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'wallets'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.wallets;
  END IF;
END $$;

ALTER TABLE public.wallets REPLICA IDENTITY FULL;

-- ==============================================================================
-- FIM — Profiles RLS aberto para leitura, wallet criada, RPC pronta
-- ==============================================================================
