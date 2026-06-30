-- ==============================================================================
-- MIGRAÇÃO: SISTEMA AUTOMATIZADO DE INDICAÇÃO (REFERRALS)
-- ==============================================================================

-- 1. Colunas adicionais na tabela profiles
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS referral_code TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS referred_by_id TEXT REFERENCES public.profiles(id);

COMMENT ON COLUMN public.profiles.referral_code IS 'Código de indicação exclusivo gerado para o perfil.';
COMMENT ON COLUMN public.profiles.referred_by_id IS 'ID do usuário indicador que indicou este perfil.';

-- 2. Tabela de controle de indicações
CREATE TABLE IF NOT EXISTS public.referrals (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id   TEXT REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    referred_id   TEXT REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    reward_amount NUMERIC(10, 2) DEFAULT 0.00,
    status        TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'completed')),
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    completed_at  TIMESTAMP WITH TIME ZONE,
    CONSTRAINT unique_referred UNIQUE (referred_id)
);

ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

-- Políticas de RLS para a tabela referrals
DROP POLICY IF EXISTS "allow_users_select_own_referrals" ON public.referrals;
CREATE POLICY "allow_users_select_own_referrals" ON public.referrals
    FOR SELECT TO authenticated
    USING (
        auth.uid()::text = referrer_id OR 
        auth.uid()::text = referred_id OR 
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

DROP POLICY IF EXISTS "allow_admin_manage_referrals" ON public.referrals;
CREATE POLICY "allow_admin_manage_referrals" ON public.referrals
    FOR ALL TO authenticated
    USING (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

-- Habilitar replicação em tempo real para referrals
BEGIN;
  ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public.referrals;
  ALTER PUBLICATION supabase_realtime ADD TABLE public.referrals;
COMMIT;

-- 3. Função e Trigger para gerar código de indicação único automaticamente
CREATE OR REPLACE FUNCTION generate_referral_code()
RETURNS TRIGGER AS $$
DECLARE
  v_code TEXT;
  v_exists BOOLEAN;
BEGIN
  IF NEW.role IN ('rider', 'driver') AND NEW.referral_code IS NULL THEN
    LOOP
      -- Gera um código curto de 8 caracteres baseado no MD5
      v_code := 'UPPI' || UPPER(substring(md5(random()::text) from 1 for 6));
      SELECT EXISTS(SELECT 1 FROM public.profiles WHERE referral_code = v_code) INTO v_exists;
      EXIT WHEN NOT v_exists;
    END LOOP;
    NEW.referral_code := v_code;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER tr_generate_referral_code
  BEFORE INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION generate_referral_code();

-- 4. Função e Trigger para registrar indicação pendente na criação do profile
CREATE OR REPLACE FUNCTION create_referral_on_profile_insert()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.referred_by_id IS NOT NULL THEN
    INSERT INTO public.referrals (referrer_id, referred_id, status)
    VALUES (NEW.referred_by_id, NEW.id, 'pending')
    ON CONFLICT (referred_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER tr_create_referral_on_profile_insert
  AFTER INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION create_referral_on_profile_insert();

-- 5. Função e Trigger para processar recompensas quando a corrida for concluída
CREATE OR REPLACE FUNCTION process_referral_on_ride_complete()
RETURNS TRIGGER AS $$
DECLARE
  v_referrer_id TEXT;
  v_ref_status TEXT;
  v_bonus_referrer NUMERIC;
  v_bonus_referred NUMERIC;
  v_enabled TEXT;
BEGIN
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    -- Busca quem indicou o passageiro que finalizou a corrida
    SELECT referred_by_id INTO v_referrer_id 
    FROM public.profiles 
    WHERE id = NEW.rider_id;
    
    IF v_referrer_id IS NOT NULL THEN
      -- Confere se a indicação está pendente
      SELECT status INTO v_ref_status 
      FROM public.referrals 
      WHERE referred_id = NEW.rider_id;
      
      IF v_ref_status = 'pending' THEN
        -- Verifica se o programa de indicações está ativo
        SELECT COALESCE(value, 'false') INTO v_enabled FROM public.app_settings WHERE key = 'referral_enabled';
        
        IF v_enabled = 'true' THEN
          -- Carrega valores das recompensas
          SELECT COALESCE(value::numeric, 10.00) INTO v_bonus_referrer FROM public.app_settings WHERE key = 'referral_bonus_referrer';
          SELECT COALESCE(value::numeric, 5.00) INTO v_bonus_referred FROM public.app_settings WHERE key = 'referral_bonus_referred';
          
          -- 1. Atualiza indicação para concluída
          UPDATE public.referrals
          SET status = 'completed',
              reward_amount = v_bonus_referrer,
              completed_at = now()
          WHERE referred_id = NEW.rider_id;
          
          -- 2. Credita indicador
          UPDATE public.profiles
          SET wallet_balance = wallet_balance + v_bonus_referrer
          WHERE id = v_referrer_id;
          
          INSERT INTO public.wallet_transactions (user_id, amount, transaction_type, description, ride_id)
          VALUES (v_referrer_id, v_bonus_referrer, 'topup', 'Bônus de Indicação Uppi (Indicou um passageiro)', NEW.id);
          
          -- 3. Credita indicado
          UPDATE public.profiles
          SET wallet_balance = wallet_balance + v_bonus_referred
          WHERE id = NEW.rider_id;
          
          INSERT INTO public.wallet_transactions (user_id, amount, transaction_type, description, ride_id)
          VALUES (NEW.rider_id, v_bonus_referred, 'topup', 'Bônus de Indicação Uppi (Utilizou código de indicação)', NEW.id);
        END IF;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER tr_process_referral_on_ride_complete
  AFTER UPDATE ON public.rides
  FOR EACH ROW
  EXECUTE FUNCTION process_referral_on_ride_complete();

-- 6. Parâmetros iniciais de configuração do sistema
INSERT INTO public.app_settings (key, value)
VALUES 
  ('referral_enabled', 'true'),
  ('referral_bonus_referrer', '10.00'),
  ('referral_bonus_referred', '5.00')
ON CONFLICT (key) DO NOTHING;
