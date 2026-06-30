-- ==============================================================================
-- MIGRAÇÃO: Separação de Credenciais e Segredos (Security Hardening - Item 38)
-- Data: 2026-05-27
-- Objetivo: Criar a tabela 'app_secrets' para armazenar chaves e credenciais
--            de API sensíveis (Mercado Pago, Twilio, Google Maps) de forma 
--            isolada das configurações comuns (app_settings), restringindo 
--            o acesso de leitura estritamente à role 'service_role'.
-- ==============================================================================

-- 1. CRIAR A TABELA DE SEGREDOS
CREATE TABLE IF NOT EXISTS public.app_secrets (
    key          TEXT PRIMARY KEY,
    secret_val   TEXT NOT NULL,
    description  TEXT,
    updated_at   TIMESTAMPTZ DEFAULT now(),
    updated_by   TEXT
);

-- 2. HABILITAR ROW LEVEL SECURITY (RLS)
ALTER TABLE public.app_secrets ENABLE ROW LEVEL SECURITY;

-- 3. CRIAR POLÍTICA RESTRITIVA DE LEITURA (APENAS SERVICE_ROLE)
-- Apenas a service_role (usada pelas Edge Functions backend) ou superadmins podem ler.
-- Usuários comuns, motoristas e admins operacionais não têm privilégios.
DROP POLICY IF EXISTS "app_secrets_select_service_role_only" ON public.app_secrets;
CREATE POLICY "app_secrets_select_service_role_only" ON public.app_secrets
    FOR SELECT TO service_role
    USING (true);

DROP POLICY IF EXISTS "app_secrets_select_superadmin" ON public.app_secrets;
CREATE POLICY "app_secrets_select_superadmin" ON public.app_secrets
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.admins 
            WHERE id = auth.uid()::text AND role = 'superadmin'
        )
    );

-- 4. CRIAR POLÍTICAS DE ESCRITA (APENAS SUPERADMINS E SERVICE_ROLE)
DROP POLICY IF EXISTS "app_secrets_write_superadmin" ON public.app_secrets;
CREATE POLICY "app_secrets_write_superadmin" ON public.app_secrets
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.admins 
            WHERE id = auth.uid()::text AND role = 'superadmin'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.admins 
            WHERE id = auth.uid()::text AND role = 'superadmin'
        )
    );

-- 5. MIGRAR SEGREDO EXISTENTES DE app_settings PARA app_secrets (SE EXISTIREM)
-- Isso evita perda de dados durante o hardening operacional.
INSERT INTO public.app_secrets (key, secret_val, description)
SELECT 
    key, 
    value, 
    'Segredo migrado da tabela antiga app_settings' 
FROM public.app_settings
WHERE key IN ('mp_access_token', 'mp_webhook_secret')
ON CONFLICT (key) DO NOTHING;

-- 6. REMOVER CHAVES PRIVADAS DA TABELA PÚBLICA app_settings
DELETE FROM public.app_settings
WHERE key IN ('mp_access_token', 'mp_webhook_secret');

-- 7. COMENTAR E DOCUMENTAR A TABELA
COMMENT ON TABLE public.app_secrets IS 
    'Tabela ultra-protegida para chaves criptográficas e credenciais privadas de API. Bloqueada contra leitura client-side.';
COMMENT ON COLUMN public.app_secrets.key IS 'Identificador do segredo (ex: mp_access_token).';
COMMENT ON COLUMN public.app_secrets.secret_val IS 'Valor confidencial do segredo.';
