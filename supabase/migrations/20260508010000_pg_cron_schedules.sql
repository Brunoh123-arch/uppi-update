-- ==============================================================================
-- CONFIGURAÇÃO PG CRON - Tarefas automáticas do Supabase
-- Execute no SQL Editor do Supabase após o deploy das Edge Functions
-- ==============================================================================

-- Habilitar extensão pg_cron (já vem habilitada no Supabase por padrão)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ==============================================================================
-- 1. LIMPEZA DE CORRIDAS EXPIRADAS (a cada 5 minutos)
-- Marca corridas 'requested' sem motorista por mais de 3 minutos como 'expired'
-- ==============================================================================
SELECT cron.schedule(
  'cleanup-expired-rides',
  '*/5 * * * *',
  $$
    UPDATE public.rides
    SET status = 'expired', updated_at = now()
    WHERE status = 'requested'
      AND driver_id IS NULL
      AND created_at < now() - interval '3 minutes';
  $$
);

-- ==============================================================================
-- 2. MOTORISTAS INATIVOS (a cada 10 minutos)
-- Marca motoristas que não atualizaram localização por mais de 15 minutos como 'offline'
-- ==============================================================================
SELECT cron.schedule(
  'cleanup-inactive-drivers',
  '*/10 * * * *',
  $$
    UPDATE public.driver_locations
    SET status = 'offline'
    WHERE status = 'online'
      AND updated_at < now() - interval '15 minutes';
  $$
);

-- ==============================================================================
-- 3. LIMPAR TOKENS FCM ANTIGOS (diariamente às 03:00 UTC)
-- Remove tokens FCM de perfis que não atualizam há mais de 30 dias
-- ==============================================================================
SELECT cron.schedule(
  'cleanup-stale-fcm-tokens',
  '0 3 * * *',
  $$
    UPDATE public.profiles
    SET fcm_token = NULL
    WHERE fcm_token IS NOT NULL
      AND updated_at < now() - interval '30 days';
  $$
);

-- ==============================================================================
-- 4. EXPIRAR CUPONS VENCIDOS (diariamente à meia-noite UTC)
-- ==============================================================================
SELECT cron.schedule(
  'expire-old-coupons',
  '0 0 * * *',
  $$
    UPDATE public.coupons
    SET is_active = false, is_enabled = false
    WHERE (expiration_date IS NOT NULL AND expiration_date < now())
       OR (expires_at IS NOT NULL AND expires_at < now());
  $$
);

-- ==============================================================================
-- VERIFICAR AGENDAMENTOS
-- ==============================================================================
-- Para verificar os crons agendados:
-- SELECT * FROM cron.job;
--
-- Para desabilitar um cron:
-- SELECT cron.unschedule('cleanup-expired-rides');
-- ==============================================================================
