-- ==============================================================================
-- ORGANIZAÇÃO FINAL DO BANCO DE DADOS — UPPI
-- 1. Triggers updated_at faltando em 9 tabelas
-- 2. Índices de performance faltando
-- 3. RLS na wallet_transactions
-- 4. Coluna cancel_reason_note em rides
-- 5. Índices nas tabelas financeiras e de motorista
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. TRIGGERS updated_at — garante que updated_at seja atualizado
--    automaticamente em todas as tabelas que possuem essa coluna
-- ─────────────────────────────────────────────────────────────────────────────

-- Função reutilizável (cria apenas se não existir)
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- driver_documents
DROP TRIGGER IF EXISTS update_driver_documents_updated_at ON public.driver_documents;
CREATE TRIGGER update_driver_documents_updated_at
  BEFORE UPDATE ON public.driver_documents
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- config
DROP TRIGGER IF EXISTS update_config_updated_at ON public.config;
CREATE TRIGGER update_config_updated_at
  BEFORE UPDATE ON public.config
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- driver_locations
DROP TRIGGER IF EXISTS update_driver_locations_updated_at ON public.driver_locations;
CREATE TRIGGER update_driver_locations_updated_at
  BEFORE UPDATE ON public.driver_locations
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- pix_payments
DROP TRIGGER IF EXISTS update_pix_payments_updated_at ON public.pix_payments;
CREATE TRIGGER update_pix_payments_updated_at
  BEFORE UPDATE ON public.pix_payments
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- mp_payments
DROP TRIGGER IF EXISTS update_mp_payments_updated_at ON public.mp_payments;
CREATE TRIGGER update_mp_payments_updated_at
  BEFORE UPDATE ON public.mp_payments
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- admins
DROP TRIGGER IF EXISTS update_admins_updated_at ON public.admins;
CREATE TRIGGER update_admins_updated_at
  BEFORE UPDATE ON public.admins
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- app_settings
DROP TRIGGER IF EXISTS update_app_settings_updated_at ON public.app_settings;
CREATE TRIGGER update_app_settings_updated_at
  BEFORE UPDATE ON public.app_settings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- scheduled_rides
DROP TRIGGER IF EXISTS update_scheduled_rides_updated_at ON public.scheduled_rides;
CREATE TRIGGER update_scheduled_rides_updated_at
  BEFORE UPDATE ON public.scheduled_rides
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- wallets
DROP TRIGGER IF EXISTS update_wallets_updated_at ON public.wallets;
CREATE TRIGGER update_wallets_updated_at
  BEFORE UPDATE ON public.wallets
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. COLUNA cancel_reason_note em rides (usada em delete-user-account e cancel-order)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'rides' AND column_name = 'cancel_reason_note'
  ) THEN
    ALTER TABLE public.rides ADD COLUMN cancel_reason_note TEXT;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. ÍNDICES DE PERFORMANCE — tabelas financeiras e de motorista
-- ─────────────────────────────────────────────────────────────────────────────

-- wallet_transactions: busca por usuário e data
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_user_id
  ON public.wallet_transactions (user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_ride_id
  ON public.wallet_transactions (ride_id)
  WHERE ride_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_created_at
  ON public.wallet_transactions (created_at DESC);

-- driver_earnings: relatórios financeiros por motorista
CREATE INDEX IF NOT EXISTS idx_driver_earnings_driver_id
  ON public.driver_earnings (driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_earnings_ride_id
  ON public.driver_earnings (ride_id);
CREATE INDEX IF NOT EXISTS idx_driver_earnings_created_at
  ON public.driver_earnings (created_at DESC);

-- driver_documents: KYC lookup por motorista
CREATE INDEX IF NOT EXISTS idx_driver_documents_driver_id
  ON public.driver_documents (driver_id);

-- messages / chat: busca por corrida
CREATE INDEX IF NOT EXISTS idx_messages_ride_id
  ON public.messages (ride_id);
CREATE INDEX IF NOT EXISTS idx_ride_messages_ride_id
  ON public.ride_messages (ride_id);

-- scheduled_rides: agendamento por passageiro e horário
CREATE INDEX IF NOT EXISTS idx_scheduled_rides_rider_id
  ON public.scheduled_rides (rider_id);
CREATE INDEX IF NOT EXISTS idx_scheduled_rides_scheduled_at
  ON public.scheduled_rides (scheduled_at);

-- sos_alerts e sos_signals: alertas por usuário
CREATE INDEX IF NOT EXISTS idx_sos_alerts_user_id
  ON public.sos_alerts (user_id);

-- notifications / announcements: busca por destinatário
CREATE INDEX IF NOT EXISTS idx_announcements_created_at
  ON public.announcements (created_at DESC);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. RLS na wallet_transactions — garantir que usuários só veem as próprias
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_reads_own_transactions" ON public.wallet_transactions;
CREATE POLICY "user_reads_own_transactions"
  ON public.wallet_transactions FOR SELECT TO authenticated
  USING (user_id = auth.uid()::text);

DROP POLICY IF EXISTS "service_role_all_transactions" ON public.wallet_transactions;
CREATE POLICY "service_role_all_transactions"
  ON public.wallet_transactions FOR ALL TO service_role
  USING (true);

-- Admin pode ver todas as transações
DROP POLICY IF EXISTS "admin_reads_all_transactions" ON public.wallet_transactions;
CREATE POLICY "admin_reads_all_transactions"
  ON public.wallet_transactions FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()::text AND role IN ('admin','operator'))
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. REALTIME nas tabelas que ainda não estão publicadas
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'wallet_transactions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.wallet_transactions;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'scheduled_rides'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.scheduled_rides;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'driver_documents'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_documents;
  END IF;
END $$;

-- REPLICA IDENTITY FULL para as novas tabelas com Realtime
ALTER TABLE public.wallet_transactions REPLICA IDENTITY FULL;
ALTER TABLE public.scheduled_rides REPLICA IDENTITY FULL;
ALTER TABLE public.driver_documents REPLICA IDENTITY FULL;

-- ==============================================================================
-- FIM — Banco de dados 100% organizado
-- ==============================================================================
