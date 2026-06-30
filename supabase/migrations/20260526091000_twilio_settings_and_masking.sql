-- ==============================================================================
-- MIGRAÇÃO: Configurações do Twilio e Mascaramento de Número de Telefone
-- 1. Colunas twilio_account_sid, twilio_auth_token, twilio_messaging_service_sid, twilio_phone_number em public.app_settings
-- 2. Valores padrão vazios na row global_config
-- 3. Atualização da política RLS public.app_settings_select para ocultar chaves do Twilio
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. ADICIONAR COLUNAS DE CONFIGURAÇÃO DO TWILIO
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.app_settings 
    ADD COLUMN IF NOT EXISTS twilio_account_sid text DEFAULT '',
    ADD COLUMN IF NOT EXISTS twilio_auth_token text DEFAULT '',
    ADD COLUMN IF NOT EXISTS twilio_messaging_service_sid text DEFAULT '',
    ADD COLUMN IF NOT EXISTS twilio_phone_number text DEFAULT '';

COMMENT ON COLUMN public.app_settings.twilio_account_sid IS 'Twilio Account SID para envio de SMS e mascaramento de número. Restrito a administradores.';
COMMENT ON COLUMN public.app_settings.twilio_auth_token IS 'Twilio Auth Token para autenticação. Restrito a administradores.';
COMMENT ON COLUMN public.app_settings.twilio_messaging_service_sid IS 'Twilio Messaging Service SID. Restrito a administradores.';
COMMENT ON COLUMN public.app_settings.twilio_phone_number IS 'Twilio Phone Number (número de envio). Restrito a administradores.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. GARANTIR VALORES PADRÃO VAZIOS NA ROW 'global_config'
-- ─────────────────────────────────────────────────────────────────────────────
UPDATE public.app_settings
SET 
    twilio_account_sid = '',
    twilio_auth_token = '',
    twilio_messaging_service_sid = '',
    twilio_phone_number = ''
WHERE key = 'global_config';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. ATUALIZAR POLÍTICA RLS PARA RESTRIÇÃO DO TWILIO
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "app_settings_select" ON public.app_settings;
CREATE POLICY "app_settings_select" ON public.app_settings
    FOR SELECT USING (
        (NOT (key LIKE 'mp_%' OR key = 'google_map_api_key' OR key LIKE 'twilio_%')) 
        OR EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );
