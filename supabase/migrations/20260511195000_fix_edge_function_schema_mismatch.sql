-- ==============================================================================
-- CORREÇÃO CRÍTICA — Incompatibilidades entre Edge Functions e Banco
-- 1. ride_activities: adicionar coluna actor_id (usada em finish-order, cancel-order, accept-order)
-- 2. wallet_transactions: a coluna 'type' existe como alias, mas transaction_type é a principal
--    → adicionamos 'type' como coluna real para compatibilidade
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. ride_activities — adicionar actor_id
--    Edge Functions insert { ride_id, type, actor_id } mas a tabela não tem actor_id
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'ride_activities' AND column_name = 'actor_id'
  ) THEN
    ALTER TABLE public.ride_activities ADD COLUMN actor_id TEXT;
    COMMENT ON COLUMN public.ride_activities.actor_id IS 'UID do usuário que gerou o evento (motorista ou passageiro)';
  END IF;
END $$;

-- Índice para buscar atividades por ator
CREATE INDEX IF NOT EXISTS idx_ride_activities_actor_id
  ON public.ride_activities (actor_id)
  WHERE actor_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. wallet_transactions — a Edge Function insere com 'type' mas a coluna
--    principal é 'transaction_type'. A tabela já tem ambas (type e transaction_type).
--    Vamos garantir que 'type' é preenchido com o mesmo valor quando transaction_type
--    é inserido (via trigger de sincronização).
-- ─────────────────────────────────────────────────────────────────────────────

-- Trigger que sincroniza type ↔ transaction_type ao inserir
CREATE OR REPLACE FUNCTION public.sync_wallet_transaction_type()
RETURNS TRIGGER AS $$
BEGIN
  -- Se inseriu 'type' mas não 'transaction_type', sincroniza
  IF NEW.transaction_type IS NULL AND NEW.type IS NOT NULL THEN
    NEW.transaction_type := NEW.type;
  END IF;
  -- Se inseriu 'transaction_type' mas não 'type', sincroniza
  IF NEW.type IS NULL AND NEW.transaction_type IS NOT NULL THEN
    NEW.type := NEW.transaction_type;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_wallet_transaction_type ON public.wallet_transactions;

CREATE TRIGGER trg_sync_wallet_transaction_type
  BEFORE INSERT OR UPDATE ON public.wallet_transactions
  FOR EACH ROW EXECUTE FUNCTION public.sync_wallet_transaction_type();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. profiles — garantir colunas usadas pelas Edge Functions
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  -- commission_percentage (usada em finish-order e admin-actions)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name='commission_percentage') THEN
    ALTER TABLE public.profiles ADD COLUMN commission_percentage NUMERIC(5,2) DEFAULT NULL;
    COMMENT ON COLUMN public.profiles.commission_percentage IS 'Comissão individual do motorista (NULL = usa comissão global)';
  END IF;

  -- commission_exempt_until (isenção de comissão)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name='commission_exempt_until') THEN
    ALTER TABLE public.profiles ADD COLUMN commission_exempt_until TIMESTAMP WITH TIME ZONE DEFAULT NULL;
    COMMENT ON COLUMN public.profiles.commission_exempt_until IS 'Data até quando o motorista está isento de comissão';
  END IF;

  -- fcm_token (notificações push)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name='fcm_token') THEN
    ALTER TABLE public.profiles ADD COLUMN fcm_token TEXT DEFAULT NULL;
    COMMENT ON COLUMN public.profiles.fcm_token IS 'Token FCM para notificações push';
  END IF;
END $$;

-- Índice para buscar FCM token rapidamente ao enviar notificação
CREATE INDEX IF NOT EXISTS idx_profiles_fcm_token
  ON public.profiles (id)
  WHERE fcm_token IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. config — garantir que a tabela tem a estrutura correta
--    admin-actions usa: key, value, updated_at
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='config' AND column_name='updated_at') THEN
    ALTER TABLE public.config ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT now();
  END IF;
END $$;

-- Trigger updated_at para config
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE event_object_table = 'config' AND trigger_name LIKE '%updated_at%'
  ) THEN
    CREATE TRIGGER set_config_updated_at
      BEFORE UPDATE ON public.config
      FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. rides — verificar e adicionar campos usados em finish-order
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  -- service_type (categoria da corrida: standard, premium, moto, etc.)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rides' AND column_name='service_type') THEN
    ALTER TABLE public.rides ADD COLUMN service_type TEXT;
  END IF;
  
  -- notes (observações do passageiro)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rides' AND column_name='notes') THEN
    ALTER TABLE public.rides ADD COLUMN notes TEXT;
  END IF;
END $$;

-- ==============================================================================
-- FIM — Incompatibilidades Edge Function ↔ Banco corrigidas
-- ==============================================================================
