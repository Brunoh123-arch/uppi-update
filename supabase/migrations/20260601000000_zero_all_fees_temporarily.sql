-- Migration: Zerar TODAS as taxas e comissões temporariamente
-- Decisão de negócio: Taxa zero por 1 mês (a partir de 2026-06-01)
-- Para reativar, basta alterar os valores na tabela app_settings via Admin Panel.

-- 1. Comissão da plataforma → 0%
INSERT INTO public.app_settings (key, value)
VALUES ('commission_rate', '0')
ON CONFLICT (key) DO UPDATE SET value = '0';

-- 2. Taxa de cancelamento → R$ 0,00
INSERT INTO public.app_settings (key, value)
VALUES ('cancellation_fee', '0')
ON CONFLICT (key) DO UPDATE SET value = '0';

-- 3. Isentar TODOS os motoristas existentes de comissão por 30 dias
-- Isso garante que mesmo que haja comissão individual, será 0
UPDATE public.profiles
SET commission_exempt_until = NOW() + INTERVAL '30 days'
WHERE id IN (
    SELECT DISTINCT driver_id FROM public.driver_locations
)
AND (commission_exempt_until IS NULL OR commission_exempt_until < NOW());
