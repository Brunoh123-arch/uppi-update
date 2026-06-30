-- ==============================================================================
-- MIGRAÇÃO — LEGACY MESSAGES & CASHBACK RULES CDC REALTIME
-- Data: 2026-05-28
-- Ecossistema Uppi — Engenharia de Banco de Dados
-- ==============================================================================
-- Adiciona suporte a CDC em tempo real (Supabase Realtime) para as tabelas:
-- 1. public.messages (garante que a aba legacy do God Mode funcione em tempo real)
-- 2. public.cashback_rules (permite reatividade síncrona em regras de cashback)
-- ==============================================================================

-- 1. ADICIONAR TABELAS FALTANTES À PUBLICAÇÃO supabase_realtime
-- Usamos blocos anônimos PL/pgSQL para evitar falhas se a tabela já existir na publicação.

-- messages
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;
END $$;

-- cashback_rules
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'cashback_rules'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.cashback_rules;
  END IF;
END $$;

-- 2. GARANTIR REPLICA IDENTITY FULL
-- Garante payload completo para UPDATE e DELETE nas duas tabelas
ALTER TABLE public.messages REPLICA IDENTITY FULL;
ALTER TABLE public.cashback_rules REPLICA IDENTITY FULL;
