-- ==============================================================================
-- MIGRATION: Adicionar campo mercado_pago_account_id para Split de Pagamento
-- Data: 2026-06-20
-- Autor: Antigravity
-- ==============================================================================

-- 1. Adicionar coluna na tabela base profiles_raw
ALTER TABLE public.profiles_raw
  ADD COLUMN IF NOT EXISTS mercado_pago_account_id TEXT;

COMMENT ON COLUMN public.profiles_raw.mercado_pago_account_id IS 'ID da conta Mercado Pago do motorista para recebimento direto de split de pagamento';

-- 2. Reconstruir a VIEW profiles para incluir a nova coluna
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
  is_blocked,
  identity_verification_status,
  identity_docs,
  cooldown_until,
  consecutive_rejections,
  accessibility_wheelchair,
  accessibility_hearing_impaired,
  accessibility_visual_aid,
  accessibility_pet_friendly,
  accessibility_child_seat,
  gender_verified,
  mercado_pago_account_id,
  boarding_pin_enabled
FROM public.profiles_raw;

-- 3. Atualizar a função de DML da VIEW profiles para repassar a nova coluna para a tabela base
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
      average_rating, rating_count, favorite_drivers, is_blocked, 
      identity_verification_status, identity_docs,
      cooldown_until, consecutive_rejections,
      accessibility_wheelchair, accessibility_hearing_impaired,
      accessibility_visual_aid, accessibility_pet_friendly,
      accessibility_child_seat, gender_verified,
      encrypted_cpf, mercado_pago_account_id, boarding_pin_enabled
    ) VALUES (
      NEW.id, NEW.role, NEW.full_name, NEW.phone_number, NEW.email, NEW.fcm_token, NEW.status, NEW.wallet_balance,
      NEW.search_radius, NEW.current_location, NEW.vehicle_details, NEW.created_at, NEW.updated_at,
      NEW.rating, NEW.review_count, NEW.commission_percentage, NEW.commission_exempt_until,
      NEW.subscription_expires_at, NEW.phone, NEW.documents, NEW.is_deleted, NEW.deleted_at,
      NEW.is_approved, NEW.vehicle_type, NEW.marker_url, NEW.certificate_number, NEW.search_distance,
      NEW.vehicle_plate_number, NEW.vehicle_production_year, NEW.vehicle_model_id, NEW.vehicle_color_id,
      NEW.bank_name, NEW.bank_account_number, NEW.bank_swift_code, NEW.bank_routing_number,
      NEW.address, NEW.gender, NEW.id_number, NEW.preset_avatar_number, NEW.total_rides, NEW.total_distance,
      NEW.average_rating, NEW.rating_count, NEW.favorite_drivers, NEW.is_blocked, 
      NEW.identity_verification_status, NEW.identity_docs,
      NEW.cooldown_until, NEW.consecutive_rejections,
      NEW.accessibility_wheelchair, NEW.accessibility_hearing_impaired,
      NEW.accessibility_visual_aid, NEW.accessibility_pet_friendly,
      NEW.accessibility_child_seat, NEW.gender_verified,
      public.encrypt_val(NEW.cpf), NEW.mercado_pago_account_id, NEW.boarding_pin_enabled
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
      identity_verification_status = NEW.identity_verification_status,
      identity_docs = NEW.identity_docs,
      cooldown_until = NEW.cooldown_until,
      consecutive_rejections = NEW.consecutive_rejections,
      accessibility_wheelchair = NEW.accessibility_wheelchair,
      accessibility_hearing_impaired = NEW.accessibility_hearing_impaired,
      accessibility_visual_aid = NEW.accessibility_visual_aid,
      accessibility_pet_friendly = NEW.accessibility_pet_friendly,
      accessibility_child_seat = NEW.accessibility_child_seat,
      gender_verified = NEW.gender_verified,
      mercado_pago_account_id = NEW.mercado_pago_account_id,
      boarding_pin_enabled = NEW.boarding_pin_enabled,
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
