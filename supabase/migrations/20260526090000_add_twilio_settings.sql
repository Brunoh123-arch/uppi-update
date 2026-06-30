-- =============================================================================
-- MIGRATION: Adicionar colunas de configuração do Twilio em app_settings
-- Para suportar as Edge Functions send-sms-otp e mask-call
-- =============================================================================

ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS twilio_account_sid TEXT DEFAULT '';
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS twilio_auth_token TEXT DEFAULT '';
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS twilio_messaging_service_sid TEXT DEFAULT '';
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS twilio_phone_number TEXT DEFAULT '';

COMMENT ON COLUMN public.app_settings.twilio_account_sid IS 'Account SID do Twilio para envio de SMS e chamadas de voz.';
COMMENT ON COLUMN public.app_settings.twilio_auth_token IS 'Auth Token do Twilio para autenticação básica.';
COMMENT ON COLUMN public.app_settings.twilio_messaging_service_sid IS 'Messaging Service SID do Twilio para envio de SMS.';
COMMENT ON COLUMN public.app_settings.twilio_phone_number IS 'Número de telefone do Twilio para mascaramento de chamadas de voz.';
