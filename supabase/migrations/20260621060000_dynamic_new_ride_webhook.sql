-- ==============================================================================
-- MIGRAÇÃO — URL DINÂMICA DO WEBHOOK DE NOVAS CORRIDAS (PORTABILIDADE TOTAL)
-- Data: 2026-06-21
-- Ecossistema Uppi — Engenharia de Infraestrutura e Banco de Dados
-- ==============================================================================
-- Esta migração resolve o problema de URL do Supabase hardcoded no trigger
-- de notificação de novas corridas (notify_webhook_new_ride).
-- Implementa uma busca dinâmica através da variável de sistema 'app.supabase_url'
-- com fallback para a tabela app_settings e finalmente para a URL padrão de homologação.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.notify_webhook_new_ride()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_supabase_url TEXT;
  v_webhook_url TEXT;
BEGIN
  -- Só dispara para corridas com status 'requested'
  IF NEW.status != 'requested' THEN
    RETURN NEW;
  END IF;

  -- 1. Buscar a URL base do Supabase de forma dinâmica
  v_supabase_url := current_setting('app.supabase_url', true);
  
  -- Fallback seguro se a variável GUC não estiver definida
  IF v_supabase_url IS NULL OR v_supabase_url = '' THEN
    SELECT value INTO v_supabase_url
    FROM public.app_settings
    WHERE key = 'supabase_url'
    LIMIT 1;
  END IF;

  -- Se ainda assim estiver ausente, fallback para homologação
  IF v_supabase_url IS NULL OR v_supabase_url = '' THEN
    v_supabase_url := 'https://kqfmahrxjuqlvxngeurj.supabase.co';
  END IF;

  -- Construir o endpoint correto da Edge Function
  v_webhook_url := rtrim(v_supabase_url, '/') || '/functions/v1/webhook-new-ride';

  -- Disparar a chamada HTTP assíncrona/segura
  PERFORM net.http_post(
    url := v_webhook_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', COALESCE(current_setting('app.webhook_secret', true), '')
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
  RAISE WARNING 'notify_webhook_new_ride falhou: %', SQLERRM;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_webhook_new_ride() IS 
  'Trigger dinâmico e portátil para envio de push de nova corrida criada via Edge Function.';
