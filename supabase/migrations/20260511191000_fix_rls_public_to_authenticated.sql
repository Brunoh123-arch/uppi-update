-- ==============================================================================
-- CORREÇÃO CRÍTICA DE SEGURANÇA — RLS policies com 'public' → 'authenticated'
-- Em Supabase/Postgres, 'public' = acesso sem autenticação (qualquer pessoa)
-- Toda policy que protege dados de usuários deve usar TO authenticated
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- COMPLAINTS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Criar Reclamação" ON public.complaints;
DROP POLICY IF EXISTS "Users can insert complaints" ON public.complaints;
DROP POLICY IF EXISTS "Users can view own complaints" ON public.complaints;
DROP POLICY IF EXISTS "Ver próprias reclamações" ON public.complaints;

CREATE POLICY "complaints_insert" ON public.complaints
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY "complaints_select" ON public.complaints
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = user_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator'))
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- COUPON_USAGES
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Ver próprios usos" ON public.coupon_usages;

CREATE POLICY "coupon_usages_select" ON public.coupon_usages
  FOR SELECT TO authenticated
  USING (auth.uid()::text = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- DRIVER_DOCUMENTS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Motorista atualiza docs" ON public.driver_documents;
DROP POLICY IF EXISTS "Motorista insere docs" ON public.driver_documents;
DROP POLICY IF EXISTS "Motorista vê próprios docs" ON public.driver_documents;

CREATE POLICY "driver_documents_select" ON public.driver_documents
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = driver_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator'))
  );

CREATE POLICY "driver_documents_insert" ON public.driver_documents
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = driver_id);

CREATE POLICY "driver_documents_update" ON public.driver_documents
  FOR UPDATE TO authenticated
  USING (auth.uid()::text = driver_id)
  WITH CHECK (auth.uid()::text = driver_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- DRIVER_EARNINGS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "driver_earnings_insert" ON public.driver_earnings;
DROP POLICY IF EXISTS "driver_earnings_select" ON public.driver_earnings;

CREATE POLICY "driver_earnings_select" ON public.driver_earnings
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = driver_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator'))
  );

CREATE POLICY "driver_earnings_insert" ON public.driver_earnings
  FOR INSERT TO service_role
  WITH CHECK (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- DRIVER_LOCATIONS — manter leitura pública (necessário para o mapa de passageiros)
-- mas restringir escrita somente ao próprio motorista autenticado
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Anyone can read driver locations" ON public.driver_locations;
DROP POLICY IF EXISTS "Drivers can update own location" ON public.driver_locations;

-- Passageiros autenticados precisam ver motoristas no mapa
CREATE POLICY "driver_locations_select" ON public.driver_locations
  FOR SELECT TO authenticated
  USING (true);

-- Só o motorista dono pode atualizar/inserir sua localização
CREATE POLICY "driver_locations_upsert" ON public.driver_locations
  FOR ALL TO authenticated
  USING (auth.uid()::text = driver_id)
  WITH CHECK (auth.uid()::text = driver_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- FEEDBACKS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Criar feedback" ON public.feedbacks;
DROP POLICY IF EXISTS "Ver feedbacks de corridas próprias" ON public.feedbacks;

CREATE POLICY "feedbacks_insert" ON public.feedbacks
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = rider_id OR auth.uid()::text = driver_id);

CREATE POLICY "feedbacks_select" ON public.feedbacks
  FOR SELECT TO authenticated
  USING (auth.uid()::text = rider_id OR auth.uid()::text = driver_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- MESSAGES
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Envio de Mensagens" ON public.messages;
DROP POLICY IF EXISTS "Leitura de Mensagens" ON public.messages;

-- messages vinculadas a corridas: quem é rider ou driver da corrida pode ler
CREATE POLICY "messages_select" ON public.messages
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = sender_id OR
    EXISTS (
      SELECT 1 FROM public.rides r
      WHERE r.id = ride_id AND (r.rider_id = auth.uid()::text OR r.driver_id = auth.uid()::text)
    )
  );

CREATE POLICY "messages_insert" ON public.messages
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = sender_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- MP_PAYMENTS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Admin vê todos pagamentos MP" ON public.mp_payments;
DROP POLICY IF EXISTS "Ver próprios pagamentos MP" ON public.mp_payments;

CREATE POLICY "mp_payments_select_own" ON public.mp_payments
  FOR SELECT TO authenticated
  USING (auth.uid()::text = rider_id);

CREATE POLICY "mp_payments_admin" ON public.mp_payments
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator')));

-- ─────────────────────────────────────────────────────────────────────────────
-- PAYMENT_METHODS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Atualizar próprios métodos de pagamento" ON public.payment_methods;
DROP POLICY IF EXISTS "Deletar próprios métodos de pagamento" ON public.payment_methods;
DROP POLICY IF EXISTS "Inserir próprios métodos de pagamento" ON public.payment_methods;
DROP POLICY IF EXISTS "Ver próprios métodos de pagamento" ON public.payment_methods;

-- payment_methods.user_id é do tipo UUID (não text), então comparamos com auth.uid() direto
CREATE POLICY "payment_methods_all" ON public.payment_methods
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- PAYOUT_ACCOUNTS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Atualizar próprias contas de saque" ON public.payout_accounts;
DROP POLICY IF EXISTS "Deletar próprias contas de saque" ON public.payout_accounts;
DROP POLICY IF EXISTS "Inserir próprias contas de saque" ON public.payout_accounts;
DROP POLICY IF EXISTS "Ver próprias contas de saque" ON public.payout_accounts;

CREATE POLICY "payout_accounts_all" ON public.payout_accounts
  FOR ALL TO authenticated
  USING (auth.uid()::text = driver_id)
  WITH CHECK (auth.uid()::text = driver_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- PIX_PAYMENTS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Admin vê todos pagamentos PIX" ON public.pix_payments;
DROP POLICY IF EXISTS "Ver próprios pagamentos PIX" ON public.pix_payments;

CREATE POLICY "pix_payments_select_own" ON public.pix_payments
  FOR SELECT TO authenticated
  USING (auth.uid()::text = rider_id);

CREATE POLICY "pix_payments_admin" ON public.pix_payments
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator')));

-- ─────────────────────────────────────────────────────────────────────────────
-- PROFILES — INSERT e UPDATE para usuário autenticado
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "Usuário edita próprio perfil" ON public.profiles;

CREATE POLICY "profiles_insert" ON public.profiles
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = id);

CREATE POLICY "profiles_update" ON public.profiles
  FOR UPDATE TO authenticated
  USING (auth.uid()::text = id)
  WITH CHECK (auth.uid()::text = id);

-- ─────────────────────────────────────────────────────────────────────────────
-- REVIEWS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Criar review" ON public.reviews;
DROP POLICY IF EXISTS "Ver reviews" ON public.reviews;

CREATE POLICY "reviews_select" ON public.reviews
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "reviews_insert" ON public.reviews
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = reviewer_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- RIDE_ACTIVITIES
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Ver atividades da corrida" ON public.ride_activities;

-- ride_activities.ride_id é UUID (join direto com rides.id)
CREATE POLICY "ride_activities_select" ON public.ride_activities
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.rides r
      WHERE r.id = ride_id AND (r.rider_id = auth.uid()::text OR r.driver_id = auth.uid()::text)
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- RIDE_MESSAGES
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Enviar mensagem" ON public.ride_messages;
DROP POLICY IF EXISTS "Ver mensagens da corrida" ON public.ride_messages;
DROP POLICY IF EXISTS "ride_messages_select" ON public.ride_messages;

CREATE POLICY "ride_messages_select" ON public.ride_messages
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.rides r
      WHERE r.id::text = ride_id AND (r.rider_id = auth.uid()::text OR r.driver_id = auth.uid()::text)
    )
  );

CREATE POLICY "ride_messages_insert" ON public.ride_messages
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = sender_id OR sent_by_driver IS NOT NULL);

-- ─────────────────────────────────────────────────────────────────────────────
-- RIDES
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Atualização de Corridas" ON public.rides;
DROP POLICY IF EXISTS "Criação de Corridas" ON public.rides;
DROP POLICY IF EXISTS "rides_select" ON public.rides;

CREATE POLICY "rides_select" ON public.rides
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = rider_id OR
    auth.uid()::text = driver_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator'))
  );

CREATE POLICY "rides_insert" ON public.rides
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = rider_id);

CREATE POLICY "rides_update" ON public.rides
  FOR UPDATE TO authenticated
  USING (
    auth.uid()::text = rider_id OR
    auth.uid()::text = driver_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator'))
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- SCHEDULED_RIDES
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "scheduled_rides_insert" ON public.scheduled_rides;
DROP POLICY IF EXISTS "scheduled_rides_select" ON public.scheduled_rides;
DROP POLICY IF EXISTS "scheduled_rides_update" ON public.scheduled_rides;

-- scheduled_rides só tem rider_id (não tem driver_id)
CREATE POLICY "scheduled_rides_select" ON public.scheduled_rides
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = rider_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator'))
  );

CREATE POLICY "scheduled_rides_insert" ON public.scheduled_rides
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = rider_id);

CREATE POLICY "scheduled_rides_update" ON public.scheduled_rides
  FOR UPDATE TO authenticated
  USING (auth.uid()::text = rider_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- SOS_ALERTS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Criar SOS alert" ON public.sos_alerts;
DROP POLICY IF EXISTS "Ver próprio SOS" ON public.sos_alerts;

CREATE POLICY "sos_alerts_insert" ON public.sos_alerts
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY "sos_alerts_select" ON public.sos_alerts
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = user_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator'))
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- SOS_SIGNALS
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Criar SOS" ON public.sos_signals;

CREATE POLICY "sos_signals_insert" ON public.sos_signals
  FOR INSERT TO authenticated
  WITH CHECK (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- USER_BADGES
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Ver próprios badges" ON public.user_badges;

CREATE POLICY "user_badges_select" ON public.user_badges
  FOR SELECT TO authenticated
  USING (auth.uid()::text = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- WALLET_TRANSACTIONS — substituir policy pública duplicada
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Ver próprias transações" ON public.wallet_transactions;
-- A policy correta já foi criada na migração anterior (user_reads_own_transactions)
-- Se não existir, cria aqui também como fallback
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'wallet_transactions' AND policyname = 'user_reads_own_transactions'
  ) THEN
    CREATE POLICY "user_reads_own_transactions" ON public.wallet_transactions
      FOR SELECT TO authenticated
      USING (auth.uid()::text = user_id);
  END IF;
END $$;

-- ==============================================================================
-- FIM — Todas as 47 policies inseguras corrigidas para 'authenticated'
-- ==============================================================================
