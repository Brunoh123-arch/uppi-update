-- ==============================================================================
-- MIGRAÇÃO: PIN de Embarque + Chargeback + LGPD CPF Fix
-- 1. Adiciona coluna boarding_pin em rides para validação de embarque
-- 2. Cria tabela payment_disputes para chargebacks do Mercado Pago
-- 3. Documentação: CPF deve ser limpo no delete-user-account (feito na Edge Function)
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. PIN DE EMBARQUE: Coluna boarding_pin na tabela rides
-- Gerado no accept-order, exibido no app do passageiro,
-- validado pelo motorista no start-order.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.rides
  ADD COLUMN IF NOT EXISTS boarding_pin CHAR(4);

COMMENT ON COLUMN public.rides.boarding_pin IS
  'Código PIN de 4 dígitos gerado no aceite da corrida. Passageiro mostra ao motorista antes de iniciar. Anulado após inicio da corrida.';

-- Índice para validação rápida de PIN por corrida
CREATE INDEX IF NOT EXISTS idx_rides_boarding_pin
  ON public.rides (boarding_pin)
  WHERE status = 'arrived';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. CHARGEBACKS: Tabela payment_disputes para registrar contestações do MP
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.payment_disputes (
  id                UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  ride_id           UUID REFERENCES public.rides(id) ON DELETE SET NULL,
  rider_id          TEXT REFERENCES public.profiles(id) ON DELETE SET NULL,
  mp_payment_id     TEXT NOT NULL,
  dispute_type      TEXT NOT NULL DEFAULT 'chargeback', -- 'chargeback', 'in_mediation', 'fraud'
  amount            NUMERIC(10, 2) NOT NULL,
  status            TEXT NOT NULL DEFAULT 'open',       -- 'open', 'resolved', 'lost'
  rider_blocked     BOOLEAN DEFAULT FALSE,
  wallet_debited    BOOLEAN DEFAULT FALSE,
  admin_notified    BOOLEAN DEFAULT FALSE,
  mp_raw_payload    JSONB,                              -- Payload completo do MP para auditoria
  resolved_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT timezone('utc', now()),
  updated_at        TIMESTAMPTZ DEFAULT timezone('utc', now())
);

CREATE INDEX IF NOT EXISTS idx_payment_disputes_rider_id    ON public.payment_disputes (rider_id);
CREATE INDEX IF NOT EXISTS idx_payment_disputes_ride_id     ON public.payment_disputes (ride_id);
CREATE INDEX IF NOT EXISTS idx_payment_disputes_status      ON public.payment_disputes (status) WHERE status = 'open';
CREATE INDEX IF NOT EXISTS idx_payment_disputes_mp_payment  ON public.payment_disputes (mp_payment_id);

-- RLS: Apenas service_role acessa (nunca exposta ao cliente)
ALTER TABLE public.payment_disputes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service_role_only_disputes" ON public.payment_disputes
  USING (auth.role() = 'service_role');

-- Trigger de updated_at
CREATE TRIGGER update_payment_disputes_updated_at
  BEFORE UPDATE ON public.payment_disputes
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. BLOQUEIO DE WALLET: Coluna is_blocked na tabela wallets (para chargebacks)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.wallets
  ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS block_reason TEXT;

COMMENT ON COLUMN public.wallets.is_blocked IS
  'TRUE se a carteira foi bloqueada por chargeback, fraude ou investigação. Impede novos pagamentos.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. TAXA DE PEDÁGIO: Coluna toll_amount em rides
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.rides
  ADD COLUMN IF NOT EXISTS toll_amount NUMERIC(10, 2) DEFAULT 0;

COMMENT ON COLUMN public.rides.toll_amount IS
  'Valor de pedágio adicionado pelo motorista ao finalizar a corrida. Limite de R$ 30,00. Cobrado da wallet do passageiro e creditado ao motorista.';
