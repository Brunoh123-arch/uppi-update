-- ==============================================================================
-- MIGRAÇÃO: Agendar cleanup-expired Edge Function via pg_cron
-- Agenda chamada HTTP à Edge Function cleanup-expired a cada 5 minutos
-- para tratar corridas fantasma (in_progress > 45min), corridas accepted
-- stale, e motoristas inativos.
-- ==============================================================================

-- Garantir extensão pg_net para chamadas HTTP via cron
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Remover agendamentos anteriores se existirem
SELECT cron.unschedule('call-cleanup-expired-function')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'call-cleanup-expired-function');

-- Agendar chamada à Edge Function cleanup-expired a cada 5 minutos
SELECT cron.schedule(
  'call-cleanup-expired-function',
  '*/5 * * * *',
  $$
    SELECT net.http_post(
      url := current_setting('app.supabase_url', true) || '/functions/v1/cleanup-expired',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', current_setting('app.webhook_secret', true)
      ),
      body := '{"scheduled": true}'::jsonb,
      timeout_milliseconds := 10000
    );
  $$
);

-- ─────────────────────────────────────────────────────────────────────────────
-- NOTA: Para que este cron funcione, é necessário configurar as variáveis:
--   app.supabase_url → URL do projeto Supabase
--   app.webhook_secret → Mesmo secret usado em WEBHOOK_SECRET no env das Edge Functions
--
-- Execute no SQL Editor do Supabase:
--   ALTER DATABASE postgres SET app.supabase_url = 'https://<seu-projeto>.supabase.co';
--   ALTER DATABASE postgres SET app.webhook_secret = '<seu-webhook-secret>';
-- ─────────────────────────────────────────────────────────────────────────────
