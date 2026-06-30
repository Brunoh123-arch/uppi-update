-- ==============================================================================
-- CONSOLIDAÇÃO — POLÍTICA DE SELECT DE driver_earnings
-- Data: 2026-06-15
-- ==============================================================================
-- Contexto: o banco de produção possuía DUAS políticas de SELECT sobrepostas
-- ("own_or_admin_read_earnings" baseada em profiles_raw.role e a política ALL
-- "admin_all_access" baseada na tabela admins). Esta migração unifica a checagem
-- de SELECT numa única política canônica usando is_admin_or_operator(), que cobre
-- AMBAS as fontes (profiles_raw.role E a tabela admins) e evita recursão de RLS.
--
-- Observação: a leitura por administradores JÁ funcionava em produção via a
-- política "admin_all_access". Esta migração é uma limpeza/consolidação, não um
-- desbloqueio — nenhum acesso é adicionado nem removido para admins/operadores.
-- ==============================================================================

DROP POLICY IF EXISTS "driver_earnings_select"      ON public.driver_earnings;
DROP POLICY IF EXISTS "own_or_admin_read_earnings"  ON public.driver_earnings;

CREATE POLICY "driver_earnings_select" ON public.driver_earnings
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = driver_id
    OR public.is_admin_or_operator(auth.uid()::text)
  );
