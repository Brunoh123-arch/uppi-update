-- ==============================================================================
-- MIGRAÇÃO: Criptografia de CPF e Conta Bancária (LGPD & Security Hardening)
-- Data: 2026-05-26
-- Objetivo: Criptografar dados sensíveis de usuários (profiles.cpf) e motoristas
--            (payout_accounts.account_number) utilizando pgcrypto de forma transparente.
-- ==============================================================================

-- 1. HABILITAR A EXTENSÃO PGCRYPTO
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. FUNÇÕES DE SUPORTE À CRIPTOGRAFIA (SECURITY DEFINER)
-- Essas funções gerenciam a obtenção da chave simétrica e a criptografia.

CREATE OR REPLACE FUNCTION public.get_encryption_key()
RETURNS TEXT AS $$
DECLARE
  key_val TEXT;
BEGIN
  -- 1. Tentar ler da variável GUC (Grand Unified Configuration) de sessão
  key_val := current_setting('app.encryption_key', true);
  IF key_val IS NOT NULL AND key_val <> '' THEN
    RETURN key_val;
  END IF;

  -- 2. Tentar ler do Supabase Vault (se a tabela/view descriptografada existir)
  IF EXISTS (
    SELECT 1 FROM information_schema.views 
    WHERE table_schema = 'vault' AND table_name = 'decrypted_secrets'
  ) THEN
    BEGIN
      SELECT decrypted_secret INTO key_val
      FROM vault.decrypted_secrets
      WHERE name = 'app_encryption_key'
      LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      key_val := NULL;
    END;
  END IF;

  IF key_val IS NOT NULL AND key_val <> '' THEN
    RETURN key_val;
  END IF;

  -- 3. Em vez de usar fallback hardcoded, lançar erro explicativo para segurança
  RAISE EXCEPTION 'Chave de criptografia não configurada. Defina a variável app.encryption_key no GUC ou adicione o segredo app_encryption_key no Supabase Vault.';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.get_encryption_key() IS
  'Obtém a chave de criptografia do GUC de sessão, do Supabase Vault ou de um fallback de desenvolvimento.';

-- Wrapper seguro de criptografia
CREATE OR REPLACE FUNCTION public.encrypt_val(val TEXT)
RETURNS BYTEA AS $$
BEGIN
  IF val IS NULL OR val = '' THEN
    RETURN NULL;
  END IF;
  RETURN extensions.pgp_sym_encrypt(val, public.get_encryption_key());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Wrapper seguro de descriptografia
CREATE OR REPLACE FUNCTION public.decrypt_val(val BYTEA)
RETURNS TEXT AS $$
BEGIN
  IF val IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN extensions.pgp_sym_decrypt(val, public.get_encryption_key());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. PREPARAR AS DEPENDÊNCIAS DE VIEWS
-- Precisamos fazer o drop da view dependente high_risk_drivers temporariamente
DROP VIEW IF EXISTS public.high_risk_drivers CASCADE;

-- 4. RENOMEAR AS TABELAS FÍSICAS ORIGINAIS
ALTER TABLE public.profiles RENAME TO profiles_raw;
ALTER TABLE public.payout_accounts RENAME TO payout_accounts_raw;

-- 5. ADICIONAR COLUNAS CRIPTOGRAFADAS E MIGRAR OS DADOS
-- 5.1 Profiles: CPF
ALTER TABLE public.profiles_raw ADD COLUMN encrypted_cpf BYTEA;
UPDATE public.profiles_raw SET encrypted_cpf = public.encrypt_val(cpf) WHERE cpf IS NOT NULL;
ALTER TABLE public.profiles_raw DROP COLUMN cpf;

-- 5.2 Payout Accounts: Account Number
ALTER TABLE public.payout_accounts_raw ADD COLUMN encrypted_account_number BYTEA;
ALTER TABLE public.payout_accounts_raw DISABLE TRIGGER enforce_single_default_payout_account;
UPDATE public.payout_accounts_raw SET encrypted_account_number = public.encrypt_val(account_number) WHERE account_number IS NOT NULL;
ALTER TABLE public.payout_accounts_raw ENABLE TRIGGER enforce_single_default_payout_account;
ALTER TABLE public.payout_accounts_raw DROP COLUMN account_number;

-- 6. CRIAR AS VIEWS TRANSPARENTES (security_invoker = true)
-- Essas views substituem as tabelas originais e descriptografam os dados sob demanda,
-- respeitando as políticas de RLS das tabelas físicas subjacentes.

CREATE OR REPLACE VIEW public.profiles WITH (security_invoker = true) AS
SELECT
  id,
  role,
  full_name,
  phone_number,
  email,
  fcm_token,
  status,
  wallet_balance,
  search_radius,
  current_location,
  vehicle_details,
  created_at,
  updated_at,
  rating,
  review_count,
  commission_percentage,
  commission_exempt_until,
  subscription_expires_at,
  phone,
  documents,
  is_deleted,
  deleted_at,
  is_approved,
  vehicle_type,
  marker_url,
  certificate_number,
  search_distance,
  vehicle_plate_number,
  vehicle_production_year,
  vehicle_model_id,
  vehicle_color_id,
  bank_name,
  bank_account_number,
  bank_swift_code,
  bank_routing_number,
  address,
  gender,
  id_number,
  preset_avatar_number,
  total_rides,
  total_distance,
  average_rating,
  rating_count,
  public.decrypt_val(encrypted_cpf) AS cpf
FROM public.profiles_raw;

CREATE OR REPLACE VIEW public.payout_accounts WITH (security_invoker = true) AS
SELECT
  id,
  driver_id,
  payout_method_id,
  routing_number,
  account_holder_name,
  bank_name,
  is_default,
  account_holder_country,
  account_holder_city,
  account_holder_state,
  account_holder_address,
  account_holder_phone,
  account_holder_zip,
  created_at,
  public.decrypt_val(encrypted_account_number) AS account_number
FROM public.payout_accounts_raw;

-- 7. DEFINIR TRIGGERS DML PARA AS VIEWS (security_invoker)
-- Garante que operações de INSERT/UPDATE/DELETE direcionadas à view sejam encaminhadas
-- para a tabela física correta e criptografadas de forma transparente.
-- Por ser SECURITY INVOKER (padrão), o DML na tabela física executa com os privilégios
-- do chamador, garantindo que as políticas de RLS originais de profiles_raw e payout_accounts_raw sejam avaliadas.

CREATE OR REPLACE FUNCTION public.profiles_view_dml_trigger()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.profiles_raw (
      id, role, full_name, phone_number, email, fcm_token, status, wallet_balance,
      search_radius, current_location, vehicle_details, created_at, updated_at,
      rating, review_count, commission_percentage, commission_exempt_until,
      subscription_expires_at, phone, documents, is_deleted, deleted_at,
      is_approved, vehicle_type, marker_url, certificate_number, search_distance,
      vehicle_plate_number, vehicle_production_year, vehicle_model_id, vehicle_color_id,
      bank_name, bank_account_number, bank_swift_code, bank_routing_number,
      address, gender, id_number, preset_avatar_number, total_rides, total_distance,
      average_rating, rating_count, encrypted_cpf
    ) VALUES (
      NEW.id, NEW.role, NEW.full_name, NEW.phone_number, NEW.email, NEW.fcm_token, NEW.status, NEW.wallet_balance,
      NEW.search_radius, NEW.current_location, NEW.vehicle_details, NEW.created_at, NEW.updated_at,
      NEW.rating, NEW.review_count, NEW.commission_percentage, NEW.commission_exempt_until,
      NEW.subscription_expires_at, NEW.phone, NEW.documents, NEW.is_deleted, NEW.deleted_at,
      NEW.is_approved, NEW.vehicle_type, NEW.marker_url, NEW.certificate_number, NEW.search_distance,
      NEW.vehicle_plate_number, NEW.vehicle_production_year, NEW.vehicle_model_id, NEW.vehicle_color_id,
      NEW.bank_name, NEW.bank_account_number, NEW.bank_swift_code, NEW.bank_routing_number,
      NEW.address, NEW.gender, NEW.id_number, NEW.preset_avatar_number, NEW.total_rides, NEW.total_distance,
      NEW.average_rating, NEW.rating_count, public.encrypt_val(NEW.cpf)
    );
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    UPDATE public.profiles_raw SET
      role = NEW.role,
      full_name = NEW.full_name,
      phone_number = NEW.phone_number,
      email = NEW.email,
      fcm_token = NEW.fcm_token,
      status = NEW.status,
      wallet_balance = NEW.wallet_balance,
      search_radius = NEW.search_radius,
      current_location = NEW.current_location,
      vehicle_details = NEW.vehicle_details,
      created_at = NEW.created_at,
      updated_at = NEW.updated_at,
      rating = NEW.rating,
      review_count = NEW.review_count,
      commission_percentage = NEW.commission_percentage,
      commission_exempt_until = NEW.commission_exempt_until,
      subscription_expires_at = NEW.subscription_expires_at,
      phone = NEW.phone,
      documents = NEW.documents,
      is_deleted = NEW.is_deleted,
      deleted_at = NEW.deleted_at,
      is_approved = NEW.is_approved,
      vehicle_type = NEW.vehicle_type,
      marker_url = NEW.marker_url,
      certificate_number = NEW.certificate_number,
      search_distance = NEW.search_distance,
      vehicle_plate_number = NEW.vehicle_plate_number,
      vehicle_production_year = NEW.vehicle_production_year,
      vehicle_model_id = NEW.vehicle_model_id,
      vehicle_color_id = NEW.vehicle_color_id,
      bank_name = NEW.bank_name,
      bank_account_number = NEW.bank_account_number,
      bank_swift_code = NEW.bank_swift_code,
      bank_routing_number = NEW.bank_routing_number,
      address = NEW.address,
      gender = NEW.gender,
      id_number = NEW.id_number,
      preset_avatar_number = NEW.preset_avatar_number,
      total_rides = NEW.total_rides,
      total_distance = NEW.total_distance,
      average_rating = NEW.average_rating,
      rating_count = NEW.rating_count,
      encrypted_cpf = CASE 
        WHEN NEW.cpf IS DISTINCT FROM OLD.cpf THEN public.encrypt_val(NEW.cpf)
        ELSE encrypted_cpf
      END
    WHERE id = OLD.id;
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    DELETE FROM public.profiles_raw WHERE id = OLD.id;
    RETURN OLD;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profiles_view_dml
  INSTEAD OF INSERT OR UPDATE OR DELETE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.profiles_view_dml_trigger();

CREATE OR REPLACE FUNCTION public.payout_accounts_view_dml_trigger()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.payout_accounts_raw (
      id, driver_id, payout_method_id, routing_number, account_holder_name, bank_name,
      is_default, account_holder_country, account_holder_city, account_holder_state,
      account_holder_address, account_holder_phone, account_holder_zip, created_at,
      encrypted_account_number
    ) VALUES (
      COALESCE(NEW.id, gen_random_uuid()), NEW.driver_id, NEW.payout_method_id, NEW.routing_number, NEW.account_holder_name, NEW.bank_name,
      NEW.is_default, NEW.account_holder_country, NEW.account_holder_city, NEW.account_holder_state,
      NEW.account_holder_address, NEW.account_holder_phone, NEW.account_holder_zip, NEW.created_at,
      public.encrypt_val(NEW.account_number)
    );
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    UPDATE public.payout_accounts_raw SET
      driver_id = NEW.driver_id,
      payout_method_id = NEW.payout_method_id,
      routing_number = NEW.routing_number,
      account_holder_name = NEW.account_holder_name,
      bank_name = NEW.bank_name,
      is_default = NEW.is_default,
      account_holder_country = NEW.account_holder_country,
      account_holder_city = NEW.account_holder_city,
      account_holder_state = NEW.account_holder_state,
      account_holder_address = NEW.account_holder_address,
      account_holder_phone = NEW.account_holder_phone,
      account_holder_zip = NEW.account_holder_zip,
      created_at = NEW.created_at,
      encrypted_account_number = CASE 
        WHEN NEW.account_number IS DISTINCT FROM OLD.account_number THEN public.encrypt_val(NEW.account_number)
        ELSE encrypted_account_number
      END
    WHERE id = OLD.id;
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    DELETE FROM public.payout_accounts_raw WHERE id = OLD.id;
    RETURN OLD;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER payout_accounts_view_dml
  INSTEAD OF INSERT OR UPDATE OR DELETE ON public.payout_accounts
  FOR EACH ROW EXECUTE FUNCTION public.payout_accounts_view_dml_trigger();

-- 8. RECOMPILAR DEPENDÊNCIAS DE VIEWS
-- Recriamos a view high_risk_drivers exatamente como antes, mas agora ela aponta para a view public.profiles.

CREATE OR REPLACE VIEW public.high_risk_drivers AS
SELECT
  p.id AS driver_id,
  p.full_name,
  p.phone,
  COUNT(r.id) AS total_rides,
  COUNT(r.id) FILTER (WHERE r.status IN ('driver_canceled', 'rider_canceled') AND r.driver_id = p.id) AS canceled_rides,
  CASE
    WHEN COUNT(r.id) > 0 THEN
      ROUND(
        (COUNT(r.id) FILTER (WHERE r.status IN ('driver_canceled', 'rider_canceled') AND r.driver_id = p.id)::NUMERIC /
        COUNT(r.id)::NUMERIC) * 100,
        1
      )
    ELSE 0
  END AS cancellation_rate
FROM public.profiles p
LEFT JOIN public.rides r ON r.driver_id = p.id
WHERE p.role = 'driver'
GROUP BY p.id, p.full_name, p.phone
HAVING COUNT(r.id) >= 5
   AND (COUNT(r.id) FILTER (WHERE r.status IN ('driver_canceled', 'rider_canceled') AND r.driver_id = p.id)::NUMERIC /
        NULLIF(COUNT(r.id)::NUMERIC, 0)) > 0.30
ORDER BY cancellation_rate DESC;

-- 9. GARANTIR GRANTS PARA AS VIEWS
-- Garante que as views herdem as permissões de acesso corretas.

GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated, service_role, postgres;
GRANT SELECT ON public.profiles TO anon;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.payout_accounts TO authenticated, service_role, postgres;

GRANT SELECT ON public.high_risk_drivers TO authenticated;
GRANT SELECT ON public.high_risk_drivers TO service_role;
