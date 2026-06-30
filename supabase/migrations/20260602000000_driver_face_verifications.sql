-- =============================================================================
-- MIGRATION: Verificação facial de motoristas (anti-fraude)
-- Data: 2026-06-02
-- -----------------------------------------------------------------------------
-- Cria a tabela que recebe os resultados da verificação facial feita no APP do
-- motorista (selfie ao vivo + comparação com a foto de referência do cadastro).
-- O Painel Admin usa esta tabela como FILA DE REVISÃO dos casos duvidosos e
-- como HISTÓRICO. As notas de corte ficam em app_settings (key-value).
--
-- Fluxo de status:
--   auto_approved  -> semelhança >= face_auto_approve_threshold e liveness ok
--   auto_rejected  -> semelhança <  face_auto_reject_threshold  ou liveness falhou
--   needs_review   -> zona de dúvida (entre as duas notas) -> cai no painel
--   approved/rejected -> decisão MANUAL do admin sobre um needs_review
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.driver_face_verifications (
    id                UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    -- profiles é uma VIEW; a tabela real é profiles_raw (por isso o FK aponta p/ ela)
    driver_id         TEXT REFERENCES public.profiles_raw(id) ON DELETE CASCADE NOT NULL,
    selfie_url        TEXT,            -- selfie ao vivo capturada no app
    reference_url     TEXT,            -- foto de referência (cadastro/documento)
    similarity_score  NUMERIC,         -- 0..100 (% de semelhança do serviço de comparação)
    liveness_passed   BOOLEAN DEFAULT false,
    status            TEXT NOT NULL DEFAULT 'needs_review'
                        CHECK (status IN ('auto_approved','auto_rejected','needs_review','approved','rejected')),
    trigger_reason    TEXT DEFAULT 'periodic',  -- 'periodic' | 'pre_online' | 'manual' | 'random'
    decided_by        TEXT,            -- id do admin que decidiu (sem FK p/ não depender do tipo de 'admins')
    decision_reason   TEXT,
    created_at        TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    decided_at        TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_dfv_status  ON public.driver_face_verifications(status);
CREATE INDEX IF NOT EXISTS idx_dfv_driver  ON public.driver_face_verifications(driver_id);
CREATE INDEX IF NOT EXISTS idx_dfv_created ON public.driver_face_verifications(created_at DESC);

ALTER TABLE public.driver_face_verifications ENABLE ROW LEVEL SECURITY;

-- Motorista lê as próprias verificações; admin lê todas.
DROP POLICY IF EXISTS "dfv_select" ON public.driver_face_verifications;
CREATE POLICY "dfv_select" ON public.driver_face_verifications
    FOR SELECT TO authenticated USING (
        auth.uid()::text = driver_id
        OR EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

-- Motorista só insere verificação dele mesmo (o app envia o resultado).
DROP POLICY IF EXISTS "dfv_insert_own" ON public.driver_face_verifications;
CREATE POLICY "dfv_insert_own" ON public.driver_face_verifications
    FOR INSERT TO authenticated WITH CHECK (
        auth.uid()::text = driver_id
    );

-- Somente admins decidem (aprovar/rejeitar) os casos em revisão.
DROP POLICY IF EXISTS "dfv_admin_update" ON public.driver_face_verifications;
CREATE POLICY "dfv_admin_update" ON public.driver_face_verifications
    FOR UPDATE TO authenticated USING (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

-- Realtime: a fila aparece na hora no Painel Admin.
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_face_verifications;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Notas de corte / ativação (não sobrescreve se o admin já tiver ajustado).
INSERT INTO public.app_settings (key, value) VALUES
    ('face_verification_enabled',        'false'),  -- liga/desliga a exigência no app
    ('face_auto_approve_threshold',      '90'),     -- >= aprova automático
    ('face_auto_reject_threshold',       '70'),     -- <  bloqueia automático (entre os dois => revisão)
    ('face_verification_interval_days',  '7')       -- de quantos em quantos dias re-verificar
ON CONFLICT (key) DO NOTHING;

COMMENT ON TABLE public.driver_face_verifications IS
  'Verificações faciais de motoristas (anti-fraude). Preenchida pelo app do motorista; revisada no Painel Admin.';
