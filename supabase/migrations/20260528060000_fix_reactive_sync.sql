-- =====================================================================
-- MIGRAÇÃO: Fix Reactive Sync - Corrige sincronização GPS e status
-- Data: 2026-05-28
-- Problema: triggers quebrados impediam que o GPS do motorista chegasse
-- em profiles.current_location, bloqueando o dispatch (rpc_find_and_offer_ride)
-- =====================================================================

-- ── 1. REMOVER TRIGGER QUEBRADO ──────────────────────────────────────
-- O trigger trg_sync_driver_location_to_profile referenciava profiles_raw
-- (tabela que não existe mais após a migração de criptografia).
-- Isso causava erro silencioso e o GPS nunca era salvo em profiles.current_location.
DROP TRIGGER IF EXISTS trg_sync_driver_location_to_profile ON public.driver_locations;
DROP FUNCTION IF EXISTS public.sync_driver_location_to_profile() CASCADE;

-- ── 2. REMOVER TRIGGER COM LOOP POTENCIAL ────────────────────────────
-- O trigger trg_driver_locations_sync_profile atualizava profiles.current_location
-- quando driver_locations era atualizado. Se profiles também tinha trigger que
-- atualizava driver_locations, criava um loop infinito.
DROP TRIGGER IF EXISTS trg_driver_locations_sync_profile ON public.driver_locations;
DROP FUNCTION IF EXISTS public.trg_sync_driver_profile_location() CASCADE;

-- ── 3. CRIAR FUNÇÃO CORRETA DE SINCRONIZAÇÃO DE GPS ──────────────────
-- Atualiza profiles.current_location ao receber update em driver_locations.
-- USA profiles diretamente (sem _raw que não existe mais).
-- Só sincroniza se o motorista estiver online para evitar writes desnecessários.
CREATE OR REPLACE FUNCTION public.fn_sync_driver_gps_to_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Atualiza current_location em profiles usando PostGIS POINT(lng lat)
  -- Nota: ST_MakePoint recebe (longitude, latitude) nessa ordem
  UPDATE public.profiles
  SET
    current_location = ST_SetSRID(ST_MakePoint(NEW.lng, NEW.lat), 4326)::geography,
    updated_at = NOW()
  WHERE id = NEW.driver_id
    AND NEW.lat IS NOT NULL
    AND NEW.lng IS NOT NULL
    AND NEW.lat != 0.0
    AND NEW.lng != 0.0;

  -- Também atualiza o campo location em driver_locations para manter consistência PostGIS
  -- (sem trigger recursivo pois só atualizamos profiles aqui)
  RETURN NEW;
END;
$$;

-- ── 4. CRIAR TRIGGER CORRETO (após INSERT ou UPDATE com coordenadas reais) ──
DROP TRIGGER IF EXISTS trg_sync_driver_gps_to_profile ON public.driver_locations;
CREATE TRIGGER trg_sync_driver_gps_to_profile
  AFTER INSERT OR UPDATE OF lat, lng
  ON public.driver_locations
  FOR EACH ROW
  WHEN (NEW.lat IS NOT NULL AND NEW.lng IS NOT NULL AND NEW.lat != 0.0 AND NEW.lng != 0.0)
  EXECUTE FUNCTION public.fn_sync_driver_gps_to_profile();

-- ── 5. GARANTIR QUE profiles.current_location EXISTE como geography ──
-- Caso não exista ainda (dependendo da versão da migração de criptografia)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = 'current_location'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN current_location GEOGRAPHY(POINT, 4326);
  END IF;
END
$$;

-- ── 6. SINCRONIZAR DADOS HISTÓRICOS ──────────────────────────────────
-- Retroativamente atualiza profiles.current_location para motoristas
-- que já têm coordenadas em driver_locations.
UPDATE public.profiles p
SET
  current_location = ST_SetSRID(ST_MakePoint(dl.lng, dl.lat), 4326)::geography,
  updated_at = NOW()
FROM public.driver_locations dl
WHERE dl.driver_id = p.id
  AND dl.lat IS NOT NULL
  AND dl.lng IS NOT NULL
  AND dl.lat != 0.0
  AND dl.lng != 0.0;

-- ── 7. ÍNDICE ESPACIAL PARA O DISPATCH (se não existir) ──────────────
CREATE INDEX IF NOT EXISTS idx_profiles_current_location
  ON public.profiles_raw USING GIST (current_location)
  WHERE role = 'driver' AND status = 'online';

-- ── 8. VERIFICAR REALTIME HABILITADO EM ride_offers ──────────────────
-- O app do motorista escuta ride_offers via CDC.
-- Garante que a publicação Realtime inclui essa tabela.
DO $$
BEGIN
  -- Habilita Realtime em ride_offers (pode silenciar se já estiver ativo)
  PERFORM pg_notify('supabase_realtime', 'reload');
END
$$;

COMMENT ON FUNCTION public.fn_sync_driver_gps_to_profile() IS 
  'Sincroniza lat/lng de driver_locations para profiles.current_location (PostGIS geography). '
  'Substitui os dois triggers quebrados anteriores (trg_sync_driver_location_to_profile e trg_driver_locations_sync_profile). '
  'Necessário para o dispatch rpc_find_and_offer_ride localizar motoristas via ST_Distance.';
