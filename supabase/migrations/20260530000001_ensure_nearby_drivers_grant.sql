-- =====================================================
-- MIGRAÇÃO: Garantir permissões de nearby_drivers
-- Data: 2026-05-30
-- =====================================================

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name = 'nearby_drivers') THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.nearby_drivers TO authenticated';
  END IF;
END $$;
