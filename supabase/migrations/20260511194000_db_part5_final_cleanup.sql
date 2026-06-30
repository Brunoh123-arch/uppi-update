-- ==============================================================================
-- ORGANIZAÇÃO FINAL — PARTE 5
-- Resolvendo todos os problemas restantes detectados na auditoria CRUD:
-- 1. Policies 'public' em tabelas de catálogo (app_settings, cancel_reasons, etc.)
-- 2. Policies duplicadas e conflitantes (services, sos_signals, ride_messages)
-- 3. Policies INSERT faltando (mp_payments, pix_payments, gift_cards)
-- 4. Limpeza de policies legadas com nomes em português duplicando novas
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. APP_SETTINGS — public → authenticated
--    (configurações do app não devem ser expostas a usuários não logados)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "app_settings_select" ON public.app_settings;

CREATE POLICY "app_settings_select" ON public.app_settings
  FOR SELECT TO authenticated
  USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. CANCEL_REASONS — public → authenticated + remover duplicata legada
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Leitura de Motivos" ON public.cancel_reasons;
DROP POLICY IF EXISTS "Public read cancel_reasons" ON public.cancel_reasons;

CREATE POLICY "cancel_reasons_select" ON public.cancel_reasons
  FOR SELECT TO authenticated
  USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. CAR_COLORS — public → authenticated
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Public read car_colors" ON public.car_colors;

CREATE POLICY "car_colors_select" ON public.car_colors
  FOR SELECT TO authenticated
  USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. CAR_MODELS — public → authenticated
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Public read car_models" ON public.car_models;

CREATE POLICY "car_models_select" ON public.car_models
  FOR SELECT TO authenticated
  USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. SERVICES — consolidar 3 SELECT duplicadas em 1 autenticada
--    ("Leitura de Serviços" era public, "Ver servicos ativos" e
--    "services_select_authenticated" eram authenticated — manter só 1)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Leitura de Serviços" ON public.services;
DROP POLICY IF EXISTS "Ver servicos ativos" ON public.services;
DROP POLICY IF EXISTS "services_select_authenticated" ON public.services;

-- Política unificada: autenticados veem serviços ativos; admin vê todos
CREATE POLICY "services_select" ON public.services
  FOR SELECT TO authenticated
  USING (
    is_active = true OR
    EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. MP_PAYMENTS — adicionar INSERT para webhook (service_role)
--    A Edge Function do webhook usa service_role — mas garantindo que
--    admins também possam inserir manualmente
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "mp_payments_insert" ON public.mp_payments;

CREATE POLICY "mp_payments_insert" ON public.mp_payments
  FOR INSERT TO authenticated
  WITH CHECK (
    -- O passageiro pode registrar via checkout
    auth.uid()::text = rider_id OR
    -- Admins podem registrar manualmente
    EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. PIX_PAYMENTS — adicionar INSERT
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "pix_payments_insert" ON public.pix_payments;

CREATE POLICY "pix_payments_insert" ON public.pix_payments
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid()::text = rider_id OR
    EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. GIFT_CARDS — adicionar INSERT (admin cria gift cards)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "gift_cards_insert" ON public.gift_cards;

CREATE POLICY "gift_cards_insert" ON public.gift_cards
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. SOS_SIGNALS — remover duplicata de INSERT ("Enviar SOS" era legada)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Enviar SOS" ON public.sos_signals;
-- Mantém apenas: sos_signals_insert (criada na migração anterior)

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. RIDE_MESSAGES — remover duplicata de SELECT ("Ler mensagens da corrida")
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Ler mensagens da corrida" ON public.ride_messages;
-- Mantém apenas: ride_messages_select (criada na migração de RLS)

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. COUPONS — adicionar INSERT/UPDATE para admin (via admin_all já cobre)
--    Mas falta UPDATE policy para usuários normais resgatarem?
--    Não — coupons são só leitura para usuários. Admin já tem ALL. OK.
-- ─────────────────────────────────────────────────────────────────────────────
-- Remover duplicata de SELECT legada (em português)
DROP POLICY IF EXISTS "Ver cupons ativos" ON public.coupons;
-- Mantém: coupons_select_authenticated + admin_all_coupons

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. WALLETS — adicionar UPDATE para o próprio usuário
--    (necessário para a RPC increment_wallet funcionar sem service_role
--    quando chamada pelo cliente Flutter direto)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "user_updates_own_wallet" ON public.wallets;

CREATE POLICY "user_updates_own_wallet" ON public.wallets
  FOR UPDATE TO authenticated
  USING (auth.uid()::text = user_id)
  WITH CHECK (auth.uid()::text = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 13. PAYMENT_GATEWAYS — remover duplicata legada em português
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Ver gateways ativos" ON public.payment_gateways;
-- Mantém: payment_gateways_select_authenticated

-- ─────────────────────────────────────────────────────────────────────────────
-- 14. ADMIN_AUDIT_LOG — garantir que admins podem INSERT (para registrar ações)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'admin_audit_log' AND policyname = 'audit_log_insert'
  ) THEN
    CREATE POLICY "audit_log_insert" ON public.admin_audit_log
      FOR INSERT TO authenticated
      WITH CHECK (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
      );
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 15. ANNOUNCEMENTS — admin pode criar/editar anúncios
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'announcements' AND policyname = 'announcements_admin_write'
  ) THEN
    CREATE POLICY "announcements_admin_write" ON public.announcements
      FOR ALL TO authenticated
      USING (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
      )
      WITH CHECK (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
      );
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 16. CAR_COLORS e CAR_MODELS — admin pode fazer INSERT/UPDATE (gerenciar catálogo)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'car_colors' AND policyname = 'car_colors_admin'
  ) THEN
    CREATE POLICY "car_colors_admin" ON public.car_colors
      FOR ALL TO authenticated
      USING (EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text))
      WITH CHECK (EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'car_models' AND policyname = 'car_models_admin'
  ) THEN
    CREATE POLICY "car_models_admin" ON public.car_models
      FOR ALL TO authenticated
      USING (EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text))
      WITH CHECK (EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text));
  END IF;
END $$;

-- ==============================================================================
-- FIM DA PARTE 5 — Banco de dados completamente auditado
-- ==============================================================================
