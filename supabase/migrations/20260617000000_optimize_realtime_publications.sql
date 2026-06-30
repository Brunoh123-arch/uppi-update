-- ==============================================================================
-- MIGRAÇÃO: Otimização do Supabase Realtime (Redução de Mensagens CDC)
-- Data: 2026-06-17
-- Ecossistema Uppi — Engenharia de Banco de Dados
-- ==============================================================================

-- 1. REMOVER TABELAS NÃO CRÍTICAS DA REPLICAÇÃO EM TEMPO REAL
-- Remove as tabelas estáticas da publicação 'supabase_realtime' para economizar tráfego CDC.
DO $$
DECLARE
  t_name TEXT;
  tables_to_drop TEXT[] := ARRAY[
    'announcements',
    'favorite_addresses',
    'favorite_drivers',
    'saved_places',
    'challenges',
    'badge_definitions',
    'feedbacks',
    'reviews',
    'ride_reviews',
    'payout_accounts_raw',
    'payout_methods',
    'car_models',
    'car_colors',
    'coupon_usages',
    'user_badges',
    'complaints',
    'support_tickets'
  ];
BEGIN
  FOREACH t_name IN ARRAY tables_to_drop
  LOOP
    IF EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t_name
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime DROP TABLE public.%I', t_name);
    END IF;
  END LOOP;
END $$;

-- 2. GARANTIR QUE APENAS AS TABELAS DO FLUXO CRÍTICO PARTICIPEM DA PUBLICAÇÃO
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'rides'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.rides;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'ride_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_messages;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'sos_alerts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.sos_alerts;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'ride_offers'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_offers;
  END IF;
END $$;
