-- 1. Criar funções auxiliares SECURITY DEFINER para evitar recursão infinita
CREATE OR REPLACE FUNCTION public.is_admin(user_id text)
RETURNS boolean
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.admins WHERE id = user_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.is_superadmin(user_id text)
RETURNS boolean
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.admins WHERE id = user_id AND role = 'superadmin'
  );
END;
$$;

-- 2. Recriar políticas de SELECT e UPDATE na tabela 'admins' usando as novas funções
DROP POLICY IF EXISTS "admins_select_authenticated" ON public.admins;
CREATE POLICY "admins_select_authenticated" ON public.admins
  FOR SELECT TO authenticated
  USING (
    auth.uid()::text = id 
    OR public.is_admin(auth.uid()::text)
  );

DROP POLICY IF EXISTS "admins_update_self" ON public.admins;
CREATE POLICY "admins_update_self" ON public.admins
  FOR UPDATE TO authenticated
  USING (
    auth.uid()::text = id 
    OR public.is_superadmin(auth.uid()::text)
  )
  WITH CHECK (
    auth.uid()::text = id 
    OR public.is_superadmin(auth.uid()::text)
  );

-- 3. Recriar políticas na tabela 'app_settings' para utilizar a função is_admin
DROP POLICY IF EXISTS "app_settings_select" ON public.app_settings;
CREATE POLICY "app_settings_select" ON public.app_settings
  FOR SELECT USING (
    (NOT (key LIKE 'mp_%' OR key = 'google_map_api_key')) 
    OR public.is_admin(auth.uid()::text)
  );

DROP POLICY IF EXISTS "app_settings_write_admin" ON public.app_settings;
CREATE POLICY "app_settings_write_admin" ON public.app_settings
  FOR ALL TO authenticated
  USING (public.is_admin(auth.uid()::text))
  WITH CHECK (public.is_admin(auth.uid()::text));

-- 4. Remover a política redundante e perigosa admin_all_access da própria tabela admins
DROP POLICY IF EXISTS "admin_all_access" ON public.admins;
