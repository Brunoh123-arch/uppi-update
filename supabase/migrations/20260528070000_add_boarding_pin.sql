-- =====================================================================
-- MIGRAÇÃO: Fix boarding_pin column + start-order relaxation
-- Data: 2026-05-28
-- =====================================================================

-- 1. Adicionar coluna boarding_pin em rides (necessária para accept-order e start-order)
ALTER TABLE public.rides ADD COLUMN IF NOT EXISTS boarding_pin TEXT;

COMMENT ON COLUMN public.rides.boarding_pin IS 
  'PIN de embarque de 4 dígitos gerado no aceite da corrida (accept-order). '
  'Exibido ao motorista para o passageiro confirmar que entrou no carro correto. '
  'Apagado após validação no start-order para não ser reutilizado.';

-- 2. Verificar status da Realtime para rides_offers (garantia)
-- ride_offers e rides já estão na publicação supabase_realtime (confirmado).
