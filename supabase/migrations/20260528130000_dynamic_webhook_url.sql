-- ==============================================================================
-- MIGRAÇÃO — URL DINÂMICA DO WEBHOOK DE DESPACHO (PORTABILIDADE TOTAL)
-- Data: 2026-05-28
-- Ecossistema Uppi — Engenharia de Infraestrutura e Banco de Dados
-- ==============================================================================
-- Esta migração resolve o problema de URL do Supabase hardcoded no trigger
-- de notificação de novas ofertas de corrida (notify_webhook_new_offer).
-- Implementa uma busca dinâmica através da variável de sistema 'app.supabase_url'
-- (fornecida nativamente pelo Supabase CLI/Docker e instâncias gerenciadas)
-- com fallback automático para a URL padrão do projeto Uppi de homologação.
-- Evita erros 404 e falhas de disparo de push em ambientes locais ou staging clones.
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
  
  -- Fallback seguro para o projeto de homologação se a variável de ambiente não estiver definida
  IF v_supabase_url IS NULL OR v_supabase_url = '' THEN
    v_supabase_url := 'https://kqfmahrxjuqlvxngeurj.supabase.co';
  END IF;

  -- Construir o endpoint correto da Edge Function
  v_webhook_url := rtrim(v_supabase_url, '/') || '/functions/v1/webhook-new-ride';

  -- 2. Buscar o secret da tabela de configurações
  SELECT value INTO v_secret
  FROM public.app_settings
  WHERE key = 'webhook_secret'
  LIMIT 1;

  -- Fallback de secret via current_setting
  IF v_secret IS NULL THEN
    v_secret := current_setting('app.webhook_secret', true);
  END IF;

  -- 3. Disparar a chamada HTTP assíncrona/segura
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
  'Trigger dinâmico e portátil para envio de push de nova corrida via Edge Function.';
