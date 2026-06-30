-- =====================================================
-- MIGRAÇÃO: Pilares 19 (Cashback) e 21 (Uppi Mulher)
-- Data: 2026-05-26
-- =====================================================

-- ══════════════════════════════════════════════════════
-- PILAR 21: UPPI MULHER — TRAVA ESTRITA DE GÊNERO
-- ══════════════════════════════════════════════════════

-- 1. Coluna gender_required na tabela services
-- Quando 'female', APENAS motoristas com gender='female' verificado podem receber a corrida
ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS gender_required TEXT;

COMMENT ON COLUMN public.services.gender_required IS 'Restrição de gênero para este serviço. NULL = sem restrição, ''female'' = apenas motoristas mulheres, ''male'' = apenas motoristas homens.';

-- 2. Flag de gênero verificado em profiles (KYC)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS gender_verified BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN public.profiles.gender_verified IS 'Indica se o gênero informado foi verificado no processo de KYC/aprovação documental pelo admin.';

-- 3. Reescrever rpc_find_and_offer_ride COM filtro de gênero estrito
CREATE OR REPLACE FUNCTION public.rpc_find_and_offer_ride(p_ride_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pickup_loc GEOGRAPHY(POINT);
    v_ride_status TEXT;
    v_service_type TEXT;
    v_gender_required TEXT;
    v_driver_id TEXT;
    v_offer_id UUID;
    v_search_radius INTEGER;
BEGIN
    -- 1. Bloquear linha da corrida para evitar conflitos de concorrência
    SELECT status, pickup_location, service_type INTO v_ride_status, v_pickup_loc, v_service_type
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    -- Se a corrida não existir ou já tiver sido aceita/cancelada, encerra o loop
    IF v_ride_status IS NULL OR v_ride_status NOT IN ('requested', 'searching') THEN
        RETURN FALSE;
    END IF;

    -- 2. Resolver restrição de gênero do serviço selecionado
    SELECT s.gender_required INTO v_gender_required
    FROM public.services s
    WHERE s.name = v_service_type OR s.id::text = v_service_type
    LIMIT 1;

    -- 3. Buscar o motorista 'online' aprovado mais próximo
    SELECT p.id, COALESCE(p.search_radius, 5000) INTO v_driver_id, v_search_radius
    FROM public.profiles p
    WHERE p.role = 'driver'
      AND p.status = 'online'
      AND p.current_location IS NOT NULL
      -- ─── ANTI CHERRY-PICKING: Excluir motoristas em cooldown ───
      AND (p.cooldown_until IS NULL OR p.cooldown_until < NOW())
      -- ═══ UPPI MULHER: Filtro estrito de gênero no servidor ═══
      -- Se o serviço exige gênero específico, SOMENTE motoristas com
      -- gênero verificado e correspondente podem receber a corrida.
      AND (
          v_gender_required IS NULL
          OR (p.gender = v_gender_required AND p.gender_verified = TRUE)
      )
      -- Filtrar por categoria do veículo correspondente ao serviço
      AND (
          v_service_type IS NULL OR
          p.vehicle_type IS NULL OR
          p.vehicle_type = COALESCE(
              (SELECT s.vehicle_category FROM public.services s WHERE s.name = v_service_type LIMIT 1),
              'carro'
          )
      )
      -- Evitar motoristas que já rejeitaram ou expiraram esta corrida
      AND NOT EXISTS (
          SELECT 1 
          FROM public.ride_rejected_drivers rr 
          WHERE rr.ride_id = p_ride_id 
            AND rr.driver_id = p.id
      )
      -- Evitar motoristas em corridas ativas
      AND NOT EXISTS (
          SELECT 1 
          FROM public.rides r 
          WHERE r.driver_id = p.id 
            AND r.status IN ('accepted', 'arrived', 'in_progress')
      )
      -- Evitar motoristas com ofertas de corrida ativas pendentes
      AND NOT EXISTS (
          SELECT 1
          FROM public.ride_offers ro
          WHERE ro.driver_id = p.id
            AND ro.status = 'offered'
            AND ro.expires_at > now()
      )
    ORDER BY 
      ST_Distance(p.current_location, v_pickup_loc) * 
      (1.0 + COALESCE(p.consecutive_rejections, 0) * 0.15)
    ASC
    LIMIT 1;

    -- 4. Se um motorista elegível for encontrado, criar a oferta
    IF v_driver_id IS NOT NULL THEN
        UPDATE public.ride_offers
        SET status = 'expired'
        WHERE ride_id = p_ride_id AND status = 'offered';

        INSERT INTO public.ride_offers (ride_id, driver_id, status, expires_at)
        VALUES (p_ride_id, v_driver_id, 'offered', now() + interval '15 seconds')
        RETURNING id INTO v_offer_id;

        UPDATE public.rides
        SET status = 'searching',
            updated_at = now()
        WHERE id = p_ride_id;

        RETURN TRUE;
    ELSE
        UPDATE public.rides
        SET status = 'requested',
            updated_at = now()
        WHERE id = p_ride_id AND status = 'searching';

        RETURN FALSE;
    END IF;
END;
$$;

COMMENT ON FUNCTION public.rpc_find_and_offer_ride(UUID) IS 'Busca o motorista disponível mais próximo com filtro estrito de gênero (Uppi Mulher), anti cherry-picking (cooldown), e penalização por rejeições recentes.';


-- ══════════════════════════════════════════════════════
-- PILAR 19: MOTOR DE CASHBACK DINÂMICO
-- ══════════════════════════════════════════════════════

-- Tabela de regras de cashback configuráveis pelo admin
CREATE TABLE IF NOT EXISTS public.cashback_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    percentage NUMERIC(5,2) NOT NULL CHECK (percentage > 0 AND percentage <= 50),
    day_of_week INTEGER,                -- 0=domingo, 1=segunda ... 6=sábado. NULL = todos os dias
    min_fare NUMERIC(10,2) DEFAULT 0,   -- Tarifa mínima para qualificar
    max_cashback NUMERIC(10,2) DEFAULT 50.00, -- Teto máximo de cashback por corrida
    is_active BOOLEAN DEFAULT TRUE,
    start_at TIMESTAMP WITH TIME ZONE,  -- NULL = sem data de início
    end_at TIMESTAMP WITH TIME ZONE,    -- NULL = sem data de fim
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.cashback_rules ENABLE ROW LEVEL SECURITY;

-- Apenas admins (via service_role) podem gerenciar; leitura pública para o motor de cálculo
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='cashback_rules' AND policyname='cashback_rules_read') THEN
    CREATE POLICY "cashback_rules_read" ON public.cashback_rules FOR SELECT TO authenticated USING (TRUE);
  END IF;
END $$;

COMMENT ON TABLE public.cashback_rules IS 'Regras de cashback configuráveis pelo admin. Saldo de cashback fica travado na wallet do passageiro para uso exclusivo dentro do app.';

-- Índice para consulta rápida de regras ativas
CREATE INDEX IF NOT EXISTS idx_cashback_rules_active
  ON public.cashback_rules (is_active, day_of_week)
  WHERE is_active = TRUE;


-- ══════════════════════════════════════════════════════
-- PILAR 22: CHAT TEMPORÁRIO 24H PÓS-CORRIDA
-- ══════════════════════════════════════════════════════

-- Flag para reabertura de chat pós-corrida (24h)
ALTER TABLE public.rides
  ADD COLUMN IF NOT EXISTS chat_reopened_at TIMESTAMP WITH TIME ZONE;

COMMENT ON COLUMN public.rides.chat_reopened_at IS 'Timestamp de reabertura do chat para objetos esquecidos. Canal expira 24h após esta data.';

-- Status de encerramento com isenção nos support_tickets
-- (o campo status TEXT já existe, apenas documentamos o valor especial)
COMMENT ON TABLE public.support_tickets IS 'Tickets de suporte. Status especial: closed_disclaimer = encerrado com isenção de responsabilidade (sem investigação).';
