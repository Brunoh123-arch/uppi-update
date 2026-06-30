-- Migration: Adicionar colunas de controle de formas de pagamento em app_settings
-- Permite que o admin ative/desative cash (dinheiro) e wallet (carteira) globalmente.

-- 1. Adicionar colunas
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS cash_enabled BOOLEAN DEFAULT true;
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS wallet_enabled BOOLEAN DEFAULT true;

-- 2. Atualizar a linha global_config com os novos defaults
UPDATE public.app_settings
SET cash_enabled = true, wallet_enabled = true
WHERE key = 'global_config';

-- 3. Inserir chaves correspondentes como key-value (para compatibilidade com SettingsScreen de ler individualmente)
INSERT INTO public.app_settings (key, value)
VALUES 
  ('cash_enabled', 'true'),
  ('wallet_enabled', 'true')
ON CONFLICT (key) DO NOTHING;

COMMENT ON COLUMN public.app_settings.cash_enabled IS 'Indica se a forma de pagamento em Dinheiro (Cash) está ativa globalmente.';
COMMENT ON COLUMN public.app_settings.wallet_enabled IS 'Indica se a forma de pagamento via Saldo da Carteira (Wallet) está ativa globalmente.';
