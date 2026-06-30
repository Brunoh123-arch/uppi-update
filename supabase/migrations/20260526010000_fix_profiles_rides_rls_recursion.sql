-- 1. Criar funções auxiliares SECURITY DEFINER para verificar papéis no profiles sem RLS
CREATE OR REPLACE FUNCTION public.is_driver(user_id text)
RETURNS boolean
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles WHERE id = user_id AND role = 'driver'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.is_admin_or_operator(user_id text)
RETURNS boolean
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles WHERE id = user_id AND role = ANY (ARRAY['admin'::text, 'operator'::text])
  );
END;
$$;

-- 2. Recriar políticas de SELECT e UPDATE na tabela 'rides' para usar as funções auxiliares
DROP POLICY IF EXISTS "rides_select_requested_for_drivers" ON public.rides;
CREATE POLICY "rides_select_requested_for_drivers" ON public.rides
  FOR SELECT TO authenticated
  USING (
    ((status = ANY (ARRAY['requested'::text, 'searching'::text])) AND public.is_driver(auth.uid()::text))
    OR auth.uid()::text = rider_id
    OR auth.uid()::text = driver_id
    OR public.is_admin_or_operator(auth.uid()::text)
  );

DROP POLICY IF EXISTS "rides_update" ON public.rides;
CREATE POLICY "rides_update" ON public.rides
  FOR UPDATE TO authenticated
  USING (
    auth.uid()::text = rider_id
    OR auth.uid()::text = driver_id
    OR public.is_admin_or_operator(auth.uid()::text)
  );

-- 3. Recriar política de UPDATE na tabela 'profiles' para usar is_admin_or_operator e evitar auto-referência
DROP POLICY IF EXISTS "update_own_or_admin_profiles" ON public.profiles;
CREATE POLICY "update_own_or_admin_profiles" ON public.profiles
  FOR UPDATE TO authenticated
  USING (
    id = auth.uid()::text
    OR public.is_admin_or_operator(auth.uid()::text)
  );
