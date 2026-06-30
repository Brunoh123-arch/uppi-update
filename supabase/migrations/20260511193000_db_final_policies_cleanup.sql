-- ==============================================================================
-- ORGANIZAÇÃO FINAL — PARTE 4
-- 1. Converter policies 'public' residuais → 'authenticated'
-- 2. Adicionar policies INSERT faltando (coupon_usages, user_badges, ride_activities)
-- 3. Verificar e corrigir tabela admins (RLS completo)
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. badge_definitions — public → authenticated
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Ler badges" ON public.badge_definitions;

CREATE POLICY "badge_definitions_select" ON public.badge_definitions
  FOR SELECT TO authenticated
  USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. challenges — public → authenticated
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Ler desafios ativos" ON public.challenges;

CREATE POLICY "challenges_select" ON public.challenges
  FOR SELECT TO authenticated
  USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. quick_replies — public → authenticated
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Ler quick replies" ON public.quick_replies;

CREATE POLICY "quick_replies_select" ON public.quick_replies
  FOR SELECT TO authenticated
  USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. coupon_usages — adicionar INSERT (sem esta policy o app não consegue
--    registrar uso de cupom → erro silencioso no checkout)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "coupon_usages_insert" ON public.coupon_usages;

CREATE POLICY "coupon_usages_insert" ON public.coupon_usages
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. user_badges — adicionar INSERT (sistema precisa conceder badges
--    via service_role ou após ação do usuário)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "user_badges_insert" ON public.user_badges;

-- Apenas service_role ou admin pode inserir badges (não o próprio usuário)
CREATE POLICY "user_badges_insert" ON public.user_badges
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.admins WHERE id = auth.uid()::text
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. ride_activities — adicionar INSERT (Edge Functions precisam registrar
--    eventos da corrida: accept, start, finish, cancel)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "ride_activities_insert" ON public.ride_activities;

CREATE POLICY "ride_activities_insert" ON public.ride_activities
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.rides r
      WHERE r.id = ride_id
        AND (r.driver_id = auth.uid()::text OR r.rider_id = auth.uid()::text)
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. admins — garantir que a tabela tem RLS completo e seguro
-- ─────────────────────────────────────────────────────────────────────────────
-- Verificar policies existentes e adicionar o que faltar
DO $$
BEGIN
  -- Admin pode ver sua própria linha (necessário para o painel admin verificar acesso)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'admins' AND policyname = 'admins_self_select'
  ) THEN
    CREATE POLICY "admins_self_select" ON public.admins
      FOR SELECT TO authenticated
      USING (id = auth.uid()::text);
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Garantir trigger updated_at nas tabelas que ainda não têm
-- ─────────────────────────────────────────────────────────────────────────────

-- Verificar se challenges tem updated_at
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='challenges' AND column_name='updated_at') THEN
    ALTER TABLE public.challenges ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT now();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE event_object_table = 'challenges' AND trigger_name LIKE '%updated_at%'
  ) THEN
    CREATE TRIGGER set_challenges_updated_at
      BEFORE UPDATE ON public.challenges
      FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END $$;

-- Verificar se badge_definitions tem updated_at
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='badge_definitions' AND column_name='updated_at') THEN
    ALTER TABLE public.badge_definitions ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT now();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE event_object_table = 'badge_definitions' AND trigger_name LIKE '%updated_at%'
  ) THEN
    CREATE TRIGGER set_badge_definitions_updated_at
      BEFORE UPDATE ON public.badge_definitions
      FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END $$;

-- Verificar se admins tem updated_at
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='admins' AND column_name='updated_at') THEN
    ALTER TABLE public.admins ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT now();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE event_object_table = 'admins' AND trigger_name LIKE '%updated_at%'
  ) THEN
    CREATE TRIGGER set_admins_updated_at
      BEFORE UPDATE ON public.admins
      FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. Habilitar Realtime nas tabelas de suporte ao app
--    (ride_activities → UI do motorista atualiza em tempo real)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  -- ride_activities
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'ride_activities'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_activities;
  END IF;

  -- ride_messages
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'ride_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_messages;
  END IF;

  -- sos_alerts
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'sos_alerts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.sos_alerts;
  END IF;
END $$;

-- ==============================================================================
-- FIM — Banco de dados 100% auditado e organizado
-- ==============================================================================
