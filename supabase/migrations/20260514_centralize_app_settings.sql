-- =============================================================================
-- MIGRATION: Adicionar colunas de configuração faltantes em app_settings
-- Para centralizar TODAS as configurações que antes estavam na tabela 'config'
-- =============================================================================

-- Taxa de cancelamento (antes hardcoded R$5)
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS cancellation_fee NUMERIC DEFAULT 5.00;

-- Surge pricing controls
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS surge_enabled BOOLEAN DEFAULT true;
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS surge_max_multiplier NUMERIC DEFAULT 2.5;

-- Mercado Pago credentials (antes na tabela 'config' como key-value)
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS mp_access_token TEXT DEFAULT '';
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS mp_public_key TEXT DEFAULT '';
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS mp_webhook_secret TEXT DEFAULT '';
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS mp_sandbox BOOLEAN DEFAULT false;

-- original_fare na tabela rides (tarifa antes do cupom — essencial para comissão)
ALTER TABLE rides ADD COLUMN IF NOT EXISTS original_fare NUMERIC DEFAULT 0;

-- Garantir que o campo commission_percentage existe nos profiles de motorista
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS commission_percentage NUMERIC DEFAULT NULL;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS commission_exempt_until TIMESTAMPTZ DEFAULT NULL;

-- =============================================================================
-- INDEX: Otimizar queries usadas pelas Edge Functions
-- =============================================================================

-- Index para busca de motoristas próximos por status
CREATE INDEX IF NOT EXISTS idx_driver_locations_status ON driver_locations(status);

-- Index para corridas ativas (usado por calculate-surge)
CREATE INDEX IF NOT EXISTS idx_rides_status ON rides(status);

-- Index para busca de cupom por código
CREATE INDEX IF NOT EXISTS idx_coupons_code_enabled ON coupons(code, is_enabled);

-- =============================================================================
-- COMMENT: Documentar a migração
-- =============================================================================
COMMENT ON COLUMN app_settings.cancellation_fee IS 'Taxa de cancelamento cobrada do passageiro (R$). Controlada pelo Painel Admin.';
COMMENT ON COLUMN app_settings.surge_enabled IS 'Habilitar/desabilitar surge pricing globalmente. Controlado pelo Painel Admin.';
COMMENT ON COLUMN app_settings.surge_max_multiplier IS 'Multiplicador máximo de surge pricing (ex: 2.5 = 250%). Controlado pelo Painel Admin.';
COMMENT ON COLUMN app_settings.mp_access_token IS 'Access token do Mercado Pago. Configurado pelo Painel Admin.';
COMMENT ON COLUMN rides.original_fare IS 'Tarifa original antes de cupons de desconto. Usada para calcular comissão justa do motorista.';
