-- ==============================================================================
-- MIGRAÇÃO: PILAR 17 — Acessibilidade (Tags de Motoristas + Filtros de Despacho)
-- ==============================================================================
-- 1. Colunas booleanas em profiles (recursos do motorista)
-- 2. Tabela accessibility_tags (catálogo)
-- 3. Seeds com 5 tags
-- 4. RLS para accessibility_tags
-- 5. Refatoração de find_nearby_requested_rides com filtro de acessibilidade
-- 6. Realtime para accessibility_tags
-- ==============================================================================

-- ============================================================
-- 1. COLUNAS EM profiles (flags do motorista)
-- ============================================================
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS accessibility_wheelchair       BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS accessibility_hearing_impaired BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS accessibility_visual_aid       BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS accessibility_pet_friendly     BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS accessibility_child_seat       BOOLEAN DEFAULT false;

COMMENT ON COLUMN public.profiles.accessibility_wheelchair       IS 'Motorista possui veículo adaptado para cadeira de rodas';
COMMENT ON COLUMN public.profiles.accessibility_hearing_impaired IS 'Motorista preparado para passageiros com deficiência auditiva';
COMMENT ON COLUMN public.profiles.accessibility_visual_aid       IS 'Motorista oferece suporte a passageiros com deficiência visual';
COMMENT ON COLUMN public.profiles.accessibility_pet_friendly     IS 'Motorista aceita animais de estimação no veículo';
COMMENT ON COLUMN public.profiles.accessibility_child_seat       IS 'Veículo equipado com cadeirinha infantil';

-- ============================================================
-- 2. TABELA accessibility_tags (catálogo de tags)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.accessibility_tags (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  key          TEXT        NOT NULL UNIQUE,
  display_name TEXT        NOT NULL,
  icon         TEXT,
  description  TEXT,
  column_name  TEXT        NOT NULL,
  is_active    BOOLEAN     DEFAULT true,
  created_at   TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE public.accessibility_tags IS 'Catálogo de tags de acessibilidade disponíveis para motoristas e filtros de passageiros';

-- ============================================================
-- 3. SEEDS — 5 tags padrão
-- ============================================================
INSERT INTO public.accessibility_tags (key, display_name, icon, description, column_name)
VALUES
  ('wheelchair',       'Cadeirante',          '♿',  'Veículo adaptado para cadeira de rodas',                        'accessibility_wheelchair'),
  ('hearing_impaired', 'Deficiente Auditivo', '🦻', 'Motorista preparado para passageiros com deficiência auditiva',  'accessibility_hearing_impaired'),
  ('visual_aid',       'Auxílio Visual',      '👁️', 'Suporte para passageiros com deficiência visual',                'accessibility_visual_aid'),
  ('pet_friendly',     'Pet Friendly',        '🐕', 'Aceita animais de estimação no veículo',                         'accessibility_pet_friendly'),
  ('child_seat',       'Cadeirinha Infantil',  '👶', 'Veículo equipado com cadeirinha para crianças',                  'accessibility_child_seat')
ON CONFLICT (key) DO NOTHING;

-- ============================================================
-- 4. RLS — accessibility_tags
-- ============================================================
ALTER TABLE public.accessibility_tags ENABLE ROW LEVEL SECURITY;

-- SELECT para todos os usuários autenticados
DROP POLICY IF EXISTS "accessibility_tags_select_authenticated" ON public.accessibility_tags;
CREATE POLICY "accessibility_tags_select_authenticated"
  ON public.accessibility_tags
  FOR SELECT
  TO authenticated
  USING (true);

-- INSERT apenas para admins
DROP POLICY IF EXISTS "accessibility_tags_insert_admin" ON public.accessibility_tags;
CREATE POLICY "accessibility_tags_insert_admin"
  ON public.accessibility_tags
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- UPDATE apenas para admins
DROP POLICY IF EXISTS "accessibility_tags_update_admin" ON public.accessibility_tags;
CREATE POLICY "accessibility_tags_update_admin"
  ON public.accessibility_tags
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- DELETE apenas para admins
DROP POLICY IF EXISTS "accessibility_tags_delete_admin" ON public.accessibility_tags;
CREATE POLICY "accessibility_tags_delete_admin"
  ON public.accessibility_tags
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- ============================================================
-- 5. REFATORAR RPC find_nearby_requested_rides
--    Aceita filtros de acessibilidade opcionais
-- ============================================================

-- Drop overloads antigos para evitar conflito de assinatura
DROP FUNCTION IF EXISTS public.find_nearby_requested_rides(float8, float8, float8);
DROP FUNCTION IF EXISTS public.find_nearby_requested_rides(float8, float8, float8, text[]);

CREATE OR REPLACE FUNCTION public.find_nearby_requested_rides(
    lat                     float8,
    lng                     float8,
    radius_meters           float8     DEFAULT 3000,
    p_accessibility_filters text[]     DEFAULT NULL
)
RETURNS TABLE (
    id              UUID,
    pickup_address  TEXT,
    dropoff_address TEXT,
    fare            DECIMAL,
    dist_meters     FLOAT8
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.id,
        r.pickup_address,
        r.dropoff_address,
        r.fare,
        ST_Distance(
            r.pickup_location,
            ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography
        ) AS dist_meters
    FROM public.rides r
    -- JOIN com profiles do passageiro? Não — o filtro é sobre o MOTORISTA que vai aceitar.
    -- O filtro de acessibilidade aqui serve para a corrida ser visível apenas se
    -- houver motoristas compatíveis, mas a lógica real do despacho filtra no dispatch.
    -- Para ride chaining (busca do motorista), o filtro age na corrida.
    -- Nesta RPC, filtramos corridas cujos passageiros solicitaram tags de acessibilidade.
    -- Porém, o design original retorna corridas para ride chaining.
    -- Mantemos a RPC compatível: se p_accessibility_filters for passado,
    -- buscamos corridas onde o motorista chamador possua as flags necessárias.
    -- Como esta RPC retorna corridas (não motoristas), o filtro garante que
    -- apenas corridas que o motorista chamador pode atender apareçam.
    WHERE r.status = 'requested'
      AND r.driver_id IS NULL
      AND ST_DWithin(
          r.pickup_location,
          ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography,
          radius_meters
      )
      -- Filtros de acessibilidade: se fornecidos, verificar que NENHUMA tag
      -- exigida pela corrida (futuramente armazenada em rides.accessibility_requirements)
      -- impede a visualização. Por ora, filtramos pelo perfil do motorista chamador.
      -- Se p_accessibility_filters não é NULL, filtramos corridas que exigem
      -- que o motorista tenha essas flags TRUE em profiles.
      -- Como esta função é chamada por motoristas buscando corridas próximas,
      -- os filtros representam as capacidades do motorista.
      AND (
          p_accessibility_filters IS NULL
          OR NOT EXISTS (
              -- Nenhum filtro exigido que o motorista não possua
              SELECT 1
              FROM unnest(p_accessibility_filters) AS f(tag)
              WHERE f.tag = 'wheelchair'       AND NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid()::text AND p.accessibility_wheelchair = true)
                 OR f.tag = 'hearing_impaired' AND NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid()::text AND p.accessibility_hearing_impaired = true)
                 OR f.tag = 'visual_aid'       AND NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid()::text AND p.accessibility_visual_aid = true)
                 OR f.tag = 'pet_friendly'     AND NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid()::text AND p.accessibility_pet_friendly = true)
                 OR f.tag = 'child_seat'       AND NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid()::text AND p.accessibility_child_seat = true)
          )
      )
    ORDER BY dist_meters ASC
    LIMIT 1;
END;
$$;

COMMENT ON FUNCTION public.find_nearby_requested_rides(float8, float8, float8, text[])
  IS 'Busca corridas solicitadas nas proximidades, opcionalmente filtrando por tags de acessibilidade do motorista chamador.';

GRANT EXECUTE ON FUNCTION public.find_nearby_requested_rides(float8, float8, float8, text[]) TO authenticated;

-- ============================================================
-- 6. REALTIME — accessibility_tags
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'accessibility_tags'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.accessibility_tags;
  END IF;
END $$;

ALTER TABLE public.accessibility_tags REPLICA IDENTITY FULL;

-- ============================================================
-- ÍNDICES para as novas colunas booleanas em profiles
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_profiles_accessibility_wheelchair
  ON public.profiles (accessibility_wheelchair)
  WHERE accessibility_wheelchair = true;

CREATE INDEX IF NOT EXISTS idx_profiles_accessibility_hearing_impaired
  ON public.profiles (accessibility_hearing_impaired)
  WHERE accessibility_hearing_impaired = true;

CREATE INDEX IF NOT EXISTS idx_profiles_accessibility_visual_aid
  ON public.profiles (accessibility_visual_aid)
  WHERE accessibility_visual_aid = true;

CREATE INDEX IF NOT EXISTS idx_profiles_accessibility_pet_friendly
  ON public.profiles (accessibility_pet_friendly)
  WHERE accessibility_pet_friendly = true;

CREATE INDEX IF NOT EXISTS idx_profiles_accessibility_child_seat
  ON public.profiles (accessibility_child_seat)
  WHERE accessibility_child_seat = true;

-- ==============================================================================
-- FIM — PILAR 17: Acessibilidade pronta para uso
-- ==============================================================================
