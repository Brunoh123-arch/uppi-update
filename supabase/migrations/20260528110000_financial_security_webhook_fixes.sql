-- =====================================================================
-- MIGRAÇÃO: Correções críticas Rodada 4 — Financeiro, Segurança e Webhook
-- Data: 2026-05-28
-- =====================================================================

-- 1. WALLETS: Adicionar pending_balance (usada por finish_ride RPC)
--    Bug: INSERT INTO wallets (..., pending_balance, ...) quebrava toda finalização
ALTER TABLE public.wallets
  ADD COLUMN IF NOT EXISTS pending_balance NUMERIC DEFAULT 0.00;

COMMENT ON COLUMN public.wallets.pending_balance IS 
  'Saldo pendente de confirmação (corridas pagas digitalmente ainda não liquidadas).';

-- 2. WEBHOOK SECRET: Armazenar em app_settings para o trigger notify_webhook_new_offer
--    Bug: current_setting("app.webhook_secret") retornava NULL → webhook-new-ride retornava 401
--    Consequência: Motorista nunca recebia notificação FCM de nova corrida via webhook
INSERT INTO public.app_settings (key, value)
VALUES ('webhook_secret', 'uppi-webhook-2026-secret')
ON CONFLICT (key) DO NOTHING;

-- 3. CORRIGIR notify_webhook_new_offer: buscar secret de app_settings (mais confiável)
CREATE OR REPLACE FUNCTION public.notify_webhook_new_offer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_secret TEXT;
BEGIN
  IF NEW.status != 'offered' THEN
    RETURN NEW;
  END IF;

  -- Buscar secret da tabela de configurações (confiável)
  SELECT value INTO v_secret
  FROM public.app_settings
  WHERE key = 'webhook_secret'
  LIMIT 1;

  -- Fallback: tentar via current_setting
  IF v_secret IS NULL THEN
    v_secret := current_setting('app.webhook_secret', true);
  END IF;

  PERFORM net.http_post(
    url := 'https://kqfmahrxjuqlvxngeurj.supabase.co/functions/v1/webhook-new-ride',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', COALESCE(v_secret, '')
    ),
    body := json_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'schema', TG_TABLE_SCHEMA,
      'record', row_to_json(NEW),
      'timestamp', extract(epoch from now())
    )::jsonb,
    timeout_milliseconds := 5000
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_webhook_new_offer falhou: %', SQLERRM;
  RETURN NEW;
END;
$$;

-- 4. CORRIGIR RLS ride_messages INSERT: sem filtro permitia qualquer usuário inserir em qualquer chat
DROP POLICY IF EXISTS ride_messages_insert ON public.ride_messages;

CREATE POLICY ride_messages_insert ON public.ride_messages
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.rides r
      WHERE r.id::text = ride_messages.ride_id
        AND (r.rider_id = (auth.uid())::text OR r.driver_id = (auth.uid())::text)
    )
  );

-- 5. CORRIGIR RLS reviews INSERT: sem filtro permitia qualquer usuário inserir avaliação
DROP POLICY IF EXISTS reviews_insert ON public.reviews;

CREATE POLICY reviews_insert ON public.reviews
  FOR INSERT
  WITH CHECK (
    reviewer_id = (auth.uid())::text
  );

-- Nota importante para o time:
-- O WEBHOOK_SECRET nas Edge Functions (Supabase Dashboard > Functions > Secrets)
-- DEVE ser definido com o mesmo valor acima: 'uppi-webhook-2026-secret'
-- Sem isso, o webhook-new-ride continuará rejeitando as chamadas do trigger.

-- 6. CORRIGIR RLS rides INSERT: sem filtro permitia qualquer usuário criar corridas diretamente
--    Bug: bypassava o create-order edge function, criando corridas sem cálculo de tarifa
DROP POLICY IF EXISTS rides_insert ON public.rides;

CREATE POLICY rides_insert ON public.rides
  FOR INSERT
  WITH CHECK (
    (auth.uid())::text = rider_id
  );

-- 7. CORRIGIR RLS wallets INSERT: sem filtro permitia criar carteira para qualquer user_id
DROP POLICY IF EXISTS "User inserts own wallet" ON public.wallets;

CREATE POLICY "User inserts own wallet" ON public.wallets
  FOR INSERT
  WITH CHECK (
    (auth.uid())::text = user_id
  );

