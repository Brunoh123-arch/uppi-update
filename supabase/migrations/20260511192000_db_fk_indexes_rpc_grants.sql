-- ==============================================================================
-- ORGANIZAÇÃO FINAL — PARTE 3
-- 1. Índices em Foreign Keys sem cobertura (causa lentidão em JOINs)
-- 2. Permissão na RPC get_driver_surgical_financials para admins
-- 3. Wallets automáticas para todos os perfis existentes sem carteira
-- 4. Índices compostos de alta prioridade em corridas e pagamentos
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. ÍNDICES EM FOREIGN KEYS SEM COBERTURA
--    15 FK detectadas sem índice — cada uma causa FULL TABLE SCAN em JOINs
-- ─────────────────────────────────────────────────────────────────────────────

-- complaints.user_id
CREATE INDEX IF NOT EXISTS idx_complaints_user_id
  ON public.complaints (user_id);

-- coupon_usages.coupon_id + ride_id + user_id
CREATE INDEX IF NOT EXISTS idx_coupon_usages_coupon_id
  ON public.coupon_usages (coupon_id);
CREATE INDEX IF NOT EXISTS idx_coupon_usages_ride_id
  ON public.coupon_usages (ride_id);
CREATE INDEX IF NOT EXISTS idx_coupon_usages_user_id
  ON public.coupon_usages (user_id);

-- feedbacks.rider_id (driver_id já tem índice via FK)
CREATE INDEX IF NOT EXISTS idx_feedbacks_rider_id
  ON public.feedbacks (rider_id);

-- gift_cards.redeemed_by
CREATE INDEX IF NOT EXISTS idx_gift_cards_redeemed_by
  ON public.gift_cards (redeemed_by)
  WHERE redeemed_by IS NOT NULL;

-- messages.sender_id
CREATE INDEX IF NOT EXISTS idx_messages_sender_id
  ON public.messages (sender_id);

-- payment_methods.driver_id + gateway_id
CREATE INDEX IF NOT EXISTS idx_payment_methods_driver_id
  ON public.payment_methods (driver_id)
  WHERE driver_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payment_methods_gateway_id
  ON public.payment_methods (gateway_id)
  WHERE gateway_id IS NOT NULL;

-- payout_accounts.driver_id + payout_method_id
CREATE INDEX IF NOT EXISTS idx_payout_accounts_driver_id
  ON public.payout_accounts (driver_id);
CREATE INDEX IF NOT EXISTS idx_payout_accounts_method_id
  ON public.payout_accounts (payout_method_id);

-- ride_messages.sender_id
CREATE INDEX IF NOT EXISTS idx_ride_messages_sender_id
  ON public.ride_messages (sender_id);

-- ride_reviews.reviewer_id
CREATE INDEX IF NOT EXISTS idx_ride_reviews_reviewer_id
  ON public.ride_reviews (reviewer_id);

-- sos_alerts.ride_id
CREATE INDEX IF NOT EXISTS idx_sos_alerts_ride_id
  ON public.sos_alerts (ride_id)
  WHERE ride_id IS NOT NULL;

-- sos_signals.submitted_by
CREATE INDEX IF NOT EXISTS idx_sos_signals_submitted_by
  ON public.sos_signals (submitted_by);

-- driver_locations: is_online (usada no índice composto abaixo)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='driver_locations' AND column_name='is_online') THEN
    ALTER TABLE public.driver_locations ADD COLUMN is_online BOOLEAN DEFAULT true;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. ÍNDICES COMPOSTOS DE ALTA PRIORIDADE
--    Queries mais comuns no painel admin e relatórios
-- ─────────────────────────────────────────────────────────────────────────────

-- Corridas por status + data (painel admin - "corridas de hoje")
CREATE INDEX IF NOT EXISTS idx_rides_status_created_at
  ON public.rides (status, created_at DESC);

-- Pagamentos PIX por data (relatório financeiro)
CREATE INDEX IF NOT EXISTS idx_pix_payments_created_at
  ON public.pix_payments (created_at DESC);

-- Pagamentos MP por data
CREATE INDEX IF NOT EXISTS idx_mp_payments_created_at
  ON public.mp_payments (created_at DESC);

-- Transações de carteira por tipo (filtro de extrato: entrada/saída)
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_type
  ON public.wallet_transactions (transaction_type);

-- Motoristas online (is_online + updated_at recente — busca frequente)
CREATE INDEX IF NOT EXISTS idx_driver_locations_online
  ON public.driver_locations (updated_at DESC)
  WHERE is_online = true;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. PERMISSÃO NA RPC get_driver_surgical_financials (admin only)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.routines
    WHERE routine_schema = 'public'
    AND routine_name = 'get_driver_surgical_financials'
  ) THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.get_driver_surgical_financials TO authenticated';
  END IF;
END $$;

-- Garantir que nearby_drivers e find_nearby_requested_rides também são acessíveis
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name = 'nearby_drivers') THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.nearby_drivers TO authenticated';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name = 'find_nearby_requested_rides') THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.find_nearby_requested_rides TO authenticated';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name = 'assign_driver_to_ride') THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.assign_driver_to_ride TO authenticated';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. INICIALIZAR WALLETS para todos os perfis existentes sem carteira
--    (garante que ninguém fica sem carteira no banco)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.wallets (user_id, balance, currency)
SELECT id, 0.00, 'BRL'
FROM public.profiles
WHERE id NOT IN (SELECT user_id FROM public.wallets)
ON CONFLICT (user_id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. COLUNAS FALTANDO — detectadas via edge functions
-- ─────────────────────────────────────────────────────────────────────────────

-- profiles: is_deleted e deleted_at (usados em delete-user-account)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='profiles' AND column_name='is_deleted') THEN
    ALTER TABLE public.profiles ADD COLUMN is_deleted BOOLEAN DEFAULT false;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='profiles' AND column_name='deleted_at') THEN
    ALTER TABLE public.profiles ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE;
  END IF;
END $$;

-- rides: cancel_reason_note (já adicionado antes, mas garantindo)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='rides' AND column_name='cancel_reason_note') THEN
    ALTER TABLE public.rides ADD COLUMN cancel_reason_note TEXT;
  END IF;
END $$;

-- driver_locations: is_online já criada na seção 1 (antes dos índices)

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. ÍNDICE PARCIAL SEGURO — filtro por perfis ativos/não deletados
-- ─────────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_profiles_active
  ON public.profiles (id, role)
  WHERE status = 'active' AND (is_deleted IS NULL OR is_deleted = false);

-- ==============================================================================
-- FIM — Banco de dados completamente otimizado e organizado
-- ==============================================================================
