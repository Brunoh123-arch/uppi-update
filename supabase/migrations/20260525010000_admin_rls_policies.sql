-- ==============================================================================
-- CONTROLE DE ACESSO ADMINISTRATIVO DINÂMICO VIA RLS - UPPI BRASIL (2026-05-25)
-- Objetivo: Garantir que o Admin Panel funcionando sob ANON_KEY tenha acesso a todas
-- as tabelas públicas (63+ chamadas diretas), enquanto mantém blindagem RLS total.
-- ==============================================================================

DO $$
DECLARE
  t TEXT;
BEGIN
  -- Iterar sobre todas as tabelas no schema public
  FOR t IN 
    SELECT table_name 
    FROM information_schema.tables 
    WHERE table_schema = 'public' 
      AND table_type = 'BASE TABLE'
      -- Evitar tabelas do sistema ou tabelas de log que tenham fluxo especial se necessário
      AND table_name NOT IN ('spatial_ref_sys') -- tabela do PostGIS
  LOOP
    -- 1. Garantir que RLS está ativado para a tabela
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t);
    
    -- 2. Remover qualquer política de admin anterior para evitar duplicados
    EXECUTE format('DROP POLICY IF EXISTS admin_all_access ON public.%I;', t);
    
    -- 3. Criar a política de super-acesso para administradores cadastrados na tabela public.admins
    EXECUTE format('
      CREATE POLICY admin_all_access ON public.%I
      FOR ALL TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.admins WHERE id = auth.uid()::text
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.admins WHERE id = auth.uid()::text
        )
      );
    ', t);
    
    RAISE NOTICE 'Política admin_all_access aplicada com sucesso na tabela public.%', t;
  END LOOP;
END $$;
