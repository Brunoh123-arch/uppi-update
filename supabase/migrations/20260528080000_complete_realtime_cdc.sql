-- ==============================================================================
-- MIGRAÇÃO — HABILITAR REALTIME CDC COMPLETO & AJUSTAR REPLICA IDENTITY
-- Data: 2026-05-28
-- Ecossistema Uppi — Engenharia de Banco de Dados
-- ==============================================================================
-- Esta migração resolve os problemas de sincronismo em tempo real (CDC)
-- habilitando o Supabase Realtime nas tabelas que o Flutter consome via streams
-- e aplicando REPLICA IDENTITY FULL para garantir o payload completo de UPDATE/DELETE.
-- ==============================================================================

-- 1. ADICIONAR TABELAS FALTANTES À PUBLICAÇÃO supabase_realtime
-- Usamos blocos anônimos PL/pgSQL dinâmicos para evitar falhas se a tabela
-- já estiver adicionada na publicação.

-- announcements
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'announcements'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.announcements;
  END IF;
END $$;

-- complaints
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'complaints'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.complaints;
  END IF;
END $$;

-- support_tickets
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'support_tickets'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.support_tickets;
  END IF;
END $$;

-- gift_cards
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'gift_cards'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.gift_cards;
  END IF;
END $$;

-- payment_methods
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'payment_methods'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.payment_methods;
  END IF;
END $$;

-- payout_accounts
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'payout_accounts_raw'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.payout_accounts_raw;
  END IF;
END $$;

-- payment_gateways
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'payment_gateways'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.payment_gateways;
  END IF;
END $$;

-- pix_payments
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'pix_payments'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.pix_payments;
  END IF;
END $$;

-- mp_payments
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'mp_payments'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.mp_payments;
  END IF;
END $$;

-- cancel_reasons
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'cancel_reasons'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.cancel_reasons;
  END IF;
END $$;

-- quick_replies
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'quick_replies'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.quick_replies;
  END IF;
END $$;

-- payout_methods
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'payout_methods'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.payout_methods;
  END IF;
END $$;

-- challenges
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'challenges'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.challenges;
  END IF;
END $$;

-- badge_definitions
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'badge_definitions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.badge_definitions;
  END IF;
END $$;

-- favorite_addresses
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'favorite_addresses'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.favorite_addresses;
  END IF;
END $$;

-- favorite_drivers
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'favorite_drivers'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.favorite_drivers;
  END IF;
END $$;

-- config
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'config'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.config;
  END IF;
END $$;

-- ride_reviews
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'ride_reviews'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_reviews;
  END IF;
END $$;

-- feedbacks
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'feedbacks'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.feedbacks;
  END IF;
END $$;

-- reviews
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'reviews'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.reviews;
  END IF;
END $$;

-- ratings
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'ratings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ratings;
  END IF;
END $$;

-- ride_messages (para garantir escuta de chat em tempo real)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'ride_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_messages;
  END IF;
END $$;

-- car_models (dados de veículos para aprovação de motoristas)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'car_models'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.car_models;
  END IF;
END $$;

-- car_colors (dados de cores para aprovação de motoristas)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'car_colors'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.car_colors;
  END IF;
END $$;


-- 2. GARANTIR REPLICA IDENTITY FULL NAS TABELAS CRÍTICAS DE CDC
-- Isso força o PostgreSQL a incluir os dados completos de antes e depois nos
-- payloads de UPDATE e DELETE, permitindo que a aplicação faça validações
-- completas de transições de status em tempo real.

-- Tabelas que já estavam na publicação mas sem REPLICA IDENTITY FULL
ALTER TABLE public.ride_activities REPLICA IDENTITY FULL;
ALTER TABLE public.sos_alerts REPLICA IDENTITY FULL;
ALTER TABLE public.driver_earnings REPLICA IDENTITY FULL;
ALTER TABLE public.admins REPLICA IDENTITY FULL;
ALTER TABLE public.ride_offers REPLICA IDENTITY FULL;
ALTER TABLE public.surge_zones REPLICA IDENTITY FULL;
ALTER TABLE public.ride_tracking_shares REPLICA IDENTITY FULL;
ALTER TABLE public.driver_kyc_history REPLICA IDENTITY FULL;
ALTER TABLE public.payout_requests REPLICA IDENTITY FULL;
ALTER TABLE public.danger_zones REPLICA IDENTITY FULL;
ALTER TABLE public.passenger_subscriptions REPLICA IDENTITY FULL;

-- Novas tabelas adicionadas que possuem reatividade a alterações cadastrais ou fluxos
ALTER TABLE public.announcements REPLICA IDENTITY FULL;
ALTER TABLE public.complaints REPLICA IDENTITY FULL;
ALTER TABLE public.support_tickets REPLICA IDENTITY FULL;
ALTER TABLE public.gift_cards REPLICA IDENTITY FULL;
ALTER TABLE public.payment_methods REPLICA IDENTITY FULL;
ALTER TABLE public.payout_accounts_raw REPLICA IDENTITY FULL;
ALTER TABLE public.pix_payments REPLICA IDENTITY FULL;
ALTER TABLE public.mp_payments REPLICA IDENTITY FULL;
ALTER TABLE public.quick_replies REPLICA IDENTITY FULL;
ALTER TABLE public.challenges REPLICA IDENTITY FULL;
ALTER TABLE public.badge_definitions REPLICA IDENTITY FULL;
ALTER TABLE public.config REPLICA IDENTITY FULL;
ALTER TABLE public.feedbacks REPLICA IDENTITY FULL;
ALTER TABLE public.reviews REPLICA IDENTITY FULL;
ALTER TABLE public.ride_reviews REPLICA IDENTITY FULL;
ALTER TABLE public.car_models REPLICA IDENTITY FULL;
ALTER TABLE public.car_colors REPLICA IDENTITY FULL;

-- 3. NOTA SOBRE VIEWS (Ex: high_risk_drivers)
-- O Supabase Realtime/CDC utiliza o Logical Replication do PostgreSQL, que por
-- especificação técnica nativa do motor relacional, não oferece suporte a CDC
-- em Views convencionais de forma síncrona.
-- Caso o monitoramento em tempo real do mapa da View public.high_risk_drivers
-- precise ser reativo instantaneamente sem polling, recomenda-se que a aplicação
-- Flutter escute diretamente a tabela public.driver_locations filtrando no cliente,
-- ou que seja criada uma tabela materializada com gatilhos de sincronização
-- transacionais para as alterações de status de risco.
