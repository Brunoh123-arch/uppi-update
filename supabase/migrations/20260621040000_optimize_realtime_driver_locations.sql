-- ==============================================================================
-- MIGRAÇÃO: Remover driver_locations da Replicação CDC
-- Data: 2026-06-21
-- Objetivo: Remove a tabela driver_locations da replicação supabase_realtime
--            para estancar o vazamento de mensagens do Realtime causado por updates de GPS.
--            A localização em tempo real do motorista já é transmitida via Broadcast,
--            tornando a replicação CDC do Postgres desnecessária e consumidora de cota.
-- ==============================================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'driver_locations'
  ) THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE public.driver_locations;
  END IF;
END $$;
