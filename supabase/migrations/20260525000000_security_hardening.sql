-- ==============================================================================
-- HARDENING DE BANCO DE DADOS - UPPI BRASIL (2026-05-25)
-- Fixes críticos de segurança:
-- 1. Revogar execução da função increment_wallet de papéis não autorizados (banco livre)
-- 2. Restringir RLS de profiles para evitar vazamento massivo de PII
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- FIX 1: Restringir a RPC increment_wallet
-- ─────────────────────────────────────────────────────────────────────────────
-- A RPC increment_wallet é SECURITY DEFINER. Qualquer usuário autenticado
-- anteriormente podia chamá-la via client.from().rpc() e alterar o próprio saldo.
-- Solução: revogar de autenticado/público e permitir apenas a service_role (Edge Functions).

REVOKE EXECUTE ON FUNCTION public.increment_wallet(target_user_id TEXT, amount_to_add NUMERIC) FROM authenticated, anon, public;
GRANT EXECUTE ON FUNCTION public.increment_wallet(target_user_id TEXT, amount_to_add NUMERIC) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- FIX 2: Blindar tabela de perfis (profiles) contra vazamento de PII
-- ─────────────────────────────────────────────────────────────────────────────
-- Existia uma política permissiva "Authenticated users can read profiles"
-- ou "profiles_select_all" com USING (true) que anulava RLS restritivos.
-- Solução: dropar as políticas genéricas e aplicar regras estritas baseadas no fluxo.

DROP POLICY IF EXISTS "Authenticated users can read profiles" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_all" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_restricted" ON public.profiles;

CREATE POLICY "profiles_select_restricted" ON public.profiles
  FOR SELECT TO authenticated
  USING (
    -- 1. O próprio usuário pode ler seu próprio perfil
    auth.uid()::text = id
    
    -- 2. Administradores podem ler qualquer perfil
    OR EXISTS (
      SELECT 1 FROM public.admins WHERE id = auth.uid()::text
    )
    
    -- 3. Motoristas podem ver perfis de passageiros em suas corridas ativas/recentes
    OR id IN (
      SELECT rider_id FROM public.rides
      WHERE driver_id = auth.uid()::text
      AND status IN ('accepted', 'arrived', 'in_progress', 'completed', 'waiting_for_post_pay')
    )
    
    -- 4. Passageiros podem ver perfis de motoristas de suas corridas ativas/recentes
    OR id IN (
      SELECT driver_id FROM public.rides
      WHERE rider_id = auth.uid()::text
      AND status IN ('accepted', 'arrived', 'in_progress', 'completed', 'waiting_for_post_pay')
    )
    
    -- 5. Motoristas online podem ver passageiros de corridas que estão aguardando motorista ('requested')
    OR id IN (
      SELECT rider_id FROM public.rides
      WHERE status = 'requested'
    )
  );
