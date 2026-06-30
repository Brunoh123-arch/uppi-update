-- ==============================================================================
-- MIGRAÇÃO — HABILITAR REALTIME CDC PARA TABELAS RESTANTES DO PAINEL E APPS
-- Data: 2026-06-04
-- Ecossistema Uppi — Engenharia de Banco de Dados
-- ==============================================================================
-- Esta migração adiciona à publicação supabase_realtime as tabelas referenciadas
-- pelo Painel Admin e pelos aplicativos locais que ainda não estavam participando
-- da replicação lógica reativa (CDC).
-- ==============================================================================

-- 1. ADICIONAR TABELAS À PUBLICAÇÃO supabase_realtime

-- coupon_usages
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'coupon_usages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.coupon_usages;
  END IF;
END $$;

-- user_badges
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'user_badges'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_badges;
  END IF;
END $$;

-- admin_chat_audit_logs
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'admin_chat_audit_logs'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.admin_chat_audit_logs;
  END IF;
END $$;

-- saved_places
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'saved_places'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.saved_places;
  END IF;
END $$;


-- 2. GARANTIR REPLICA IDENTITY FULL NAS TABELAS
ALTER TABLE public.coupon_usages REPLICA IDENTITY FULL;
ALTER TABLE public.user_badges REPLICA IDENTITY FULL;
ALTER TABLE public.admin_chat_audit_logs REPLICA IDENTITY FULL;
ALTER TABLE public.saved_places REPLICA IDENTITY FULL;

COMMENT ON TABLE public.coupon_usages IS
  'Histórico de cupons utilizados por usuários. CDC habilitado para controle e relatórios em tempo real.';
COMMENT ON TABLE public.user_badges IS
  'Conquistas e medalhas vinculadas aos usuários. CDC habilitado para exibição dinâmica de badges.';
COMMENT ON TABLE public.admin_chat_audit_logs IS
  'Log de auditoria para acessos administrativos aos chats sob SOS. CDC habilitado para monitoramento ativo de conformidade.';
COMMENT ON TABLE public.saved_places IS
  'Locais favoritos salvos pelos passageiros. CDC habilitado para sincronização de rotas inteligentes.';
