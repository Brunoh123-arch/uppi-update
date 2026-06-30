-- =====================================================================
-- MIGRAÇÃO: Colunas faltantes detectadas na auditoria de reatividade
-- Data: 2026-05-28
-- =====================================================================

-- 1. wallets: adicionar is_blocked e block_reason (necessário para create-order)
ALTER TABLE public.wallets
  ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS block_reason TEXT;

COMMENT ON COLUMN public.wallets.is_blocked IS 
  'Bloqueia o passageiro de solicitar novas corridas (ex: chargeback, fraude)';
COMMENT ON COLUMN public.wallets.block_reason IS 
  'Motivo do bloqueio da carteira, exibido ao passageiro.';

-- 2. profiles_raw: adicionar favorite_drivers (necessário para sync-profile + rate_order)
ALTER TABLE public.profiles_raw
  ADD COLUMN IF NOT EXISTS favorite_drivers TEXT[] DEFAULT '{}';

COMMENT ON COLUMN public.profiles_raw.favorite_drivers IS 
  'IDs dos motoristas marcados como favoritos pelo passageiro.';

-- 3. profiles_raw: adicionar is_blocked (lido pelo driver app no stream de perfil CDC)
ALTER TABLE public.profiles_raw
  ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN public.profiles_raw.is_blocked IS 
  'Bloqueia o motorista de ficar online e receber corridas.';

-- 4. Reconstruir a VIEW profiles para expor essas novas colunas
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
  public.decrypt_val(encrypted_cpf) AS cpf,
  favorite_drivers,
  is_blocked
FROM public.profiles_raw;

-- 5. Atualizar a função e trigger DML da VIEW profiles
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
      average_rating, rating_count, favorite_drivers, is_blocked, encrypted_cpf
    ) VALUES (
      NEW.id, NEW.role, NEW.full_name, NEW.phone_number, NEW.email, NEW.fcm_token, NEW.status, NEW.wallet_balance,
      NEW.search_radius, NEW.current_location, NEW.vehicle_details, NEW.created_at, NEW.updated_at,
      NEW.rating, NEW.review_count, NEW.commission_percentage, NEW.commission_exempt_until,
      NEW.subscription_expires_at, NEW.phone, NEW.documents, NEW.is_deleted, NEW.deleted_at,
      NEW.is_approved, NEW.vehicle_type, NEW.marker_url, NEW.certificate_number, NEW.search_distance,
      NEW.vehicle_plate_number, NEW.vehicle_production_year, NEW.vehicle_model_id, NEW.vehicle_color_id,
      NEW.bank_name, NEW.bank_account_number, NEW.bank_swift_code, NEW.bank_routing_number,
      NEW.address, NEW.gender, NEW.id_number, NEW.preset_avatar_number, NEW.total_rides, NEW.total_distance,
      NEW.average_rating, NEW.rating_count, NEW.favorite_drivers, NEW.is_blocked, public.encrypt_val(NEW.cpf)
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
      favorite_drivers = NEW.favorite_drivers,
      is_blocked = NEW.is_blocked,
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

-- 6. app_settings: valores padrão faltando
INSERT INTO public.app_settings (key, value) VALUES
  ('global_surge_multiplier', '1.0'),
  ('cancellation_fee', '5.00'),
  ('min_cancellation_grace_seconds', '120')
ON CONFLICT (key) DO NOTHING;
