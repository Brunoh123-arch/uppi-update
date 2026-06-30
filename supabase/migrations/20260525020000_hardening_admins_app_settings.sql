-- ==============================================================================
-- HARDENING DE SEGURANÇA: admins E app_settings - UPPI BRASIL (2026-05-25)
-- Fix de vulnerabilidades críticas:
-- 1. Trancar tabela 'admins' contra auto-cadastro e privilégios frouxos
-- 2. Trancar tabela 'app_settings' para ocultar chaves do Mercado Pago e maps
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. HARDENING DA TABELA 'admins'
-- ─────────────────────────────────────────────────────────────────────────────

-- Permitir SELECT apenas ao próprio usuário autenticado ou se ele já for um admin cadastrado
DROP POLICY IF EXISTS "admins_select_authenticated" ON public.admins;
CREATE POLICY "admins_select_authenticated" ON public.admins
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = id 
    OR EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- Bloquear completamente INSERTs vindo de conexões públicas/authenticated do client
DROP POLICY IF EXISTS "admins_insert_authenticated" ON public.admins;
CREATE POLICY "admins_insert_authenticated" ON public.admins
  FOR INSERT TO authenticated WITH CHECK (false);

-- Permitir UPDATE apenas se for o próprio usuário ou se for um superadmin autenticado
DROP POLICY IF EXISTS "admins_update_self" ON public.admins;
CREATE POLICY "admins_update_self" ON public.admins
  FOR UPDATE TO authenticated
  USING (
    auth.uid()::text = id 
    OR EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text AND role = 'superadmin')
  )
  WITH CHECK (
    auth.uid()::text = id 
    OR EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text AND role = 'superadmin')
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. HARDENING DA TABELA 'app_settings'
-- ─────────────────────────────────────────────────────────────────────────────

-- Permitir SELECT apenas de chaves não sensíveis para usuários comuns.
-- Administradores autenticados podem ler absolutamente qualquer chave (incluindo MP e Google Maps).
DROP POLICY IF EXISTS "app_settings_select" ON public.app_settings;
CREATE POLICY "app_settings_select" ON public.app_settings
  FOR SELECT USING (
    (NOT (key LIKE 'mp_%' OR key = 'google_map_api_key')) 
    OR EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- Bloquear INSERT/UPDATE/DELETE geral de app_settings para usuários comuns.
-- Apenas administradores autenticados podem modificar as configurações.
DROP POLICY IF EXISTS "app_settings_insert" ON public.app_settings;
DROP POLICY IF EXISTS "app_settings_update" ON public.app_settings;

CREATE POLICY "app_settings_write_admin" ON public.app_settings
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text))
  WITH CHECK (EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text));
