-- ==============================================================================
-- MIGRAÇÃO — SEGURANÇA E REMOÇÃO DE URL DE STAGING HARDCODED NO WEBHOOK DE OFERTAS
-- Data: 2026-06-15
-- Ecossistema Uppi — Engenharia de Infraestrutura e Banco de Dados
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.notify_webhook_new_offer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_secret TEXT;
  v_supabase_url TEXT;
  v_webhook_url TEXT;
BEGIN
  IF NEW.status != 'offered' THEN
    RETURN NEW;
  END IF;

  -- 1. Buscar a URL base do Supabase de forma dinâmica
  v_supabase_url := current_setting('app.supabase_url', true);
  
  -- 2. Tentar buscar na tabela app_settings se a variável GUC não estiver definida
  IF v_supabase_url IS NULL OR v_supabase_url = '' THEN
    SELECT value INTO v_supabase_url
    FROM public.app_settings
    WHERE key = 'supabase_url'
    LIMIT 1;
  END IF;

  -- 3. Se ainda assim estiver ausente, abortar com aviso para não disparar contra servidor de staging
  IF v_supabase_url IS NULL OR v_supabase_url = '' THEN
    RAISE WARNING 'notify_webhook_new_offer ignorado: app.supabase_url ou app_settings(supabase_url) não configurados.';
    RETURN NEW;
  END IF;

  -- Construir o endpoint correto da Edge Function
  v_webhook_url := rtrim(v_supabase_url, '/') || '/functions/v1/webhook-new-ride';

  -- 4. Buscar o secret da tabela de configurações
  SELECT value INTO v_secret
  FROM public.app_settings
  WHERE key = 'webhook_secret'
  LIMIT 1;

  -- Fallback de secret via current_setting
  IF v_secret IS NULL THEN
    v_secret := current_setting('app.webhook_secret', true);
  END IF;

  -- 5. Disparar a chamada HTTP assíncrona/segura
  PERFORM net.http_post(
    url := v_webhook_url,
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

COMMENT ON FUNCTION public.notify_webhook_new_offer() IS 
  'Trigger dinâmico e seguro para envio de push de nova corrida via Edge Function, sem URL de staging hardcoded.';
