-- ==============================================================================
-- MIGRAÇÃO — HABILITAR REALTIME NAS TABELAS FALTANTES
-- ==============================================================================
-- O código Flutter usa .stream(primaryKey: ['id']) nas tabelas abaixo,
-- porém elas NÃO estavam registradas na publicação supabase_realtime.
-- Sem isso o Realtime só faz polling local — NÃO recebe push do servidor.
-- ==============================================================================

-- 1. rides — status da corrida em tempo real (rider + driver)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'rides'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.rides;
  END IF;
END $$;

-- 2. profiles — localização do motorista + dados do perfil em tempo real
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'profiles'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
  END IF;
END $$;

-- 3. app_settings — configurações globais instantâneas (map provider, etc)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'app_settings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.app_settings;
  END IF;
END $$;

-- 4. Garantir REPLICA IDENTITY FULL nas tabelas com Realtime
-- Isso permite que o Supabase envie o registro completo (old + new) nos eventos
ALTER TABLE public.rides REPLICA IDENTITY FULL;
ALTER TABLE public.profiles REPLICA IDENTITY FULL;
ALTER TABLE public.app_settings REPLICA IDENTITY FULL;
ALTER TABLE public.ride_messages REPLICA IDENTITY FULL;
ALTER TABLE public.driver_locations REPLICA IDENTITY FULL;

-- ==============================================================================
-- FIM — Agora TODAS as tabelas usadas com .stream() têm Realtime ativo
-- ==============================================================================
