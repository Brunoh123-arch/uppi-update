-- Migration: Add vehicle_category to services table and populate default values
-- Establishes vehicle categorization for ride dispatch matching

-- ============================================================
-- BUG F: Adicionar vehicle_category em services
-- ============================================================
ALTER TABLE public.services ADD COLUMN IF NOT EXISTS vehicle_category TEXT;

-- Preencher valores padrão para os serviços existentes baseados no name
UPDATE public.services SET vehicle_category = 'carro' 
WHERE name ILIKE '%uppi x%' OR name ILIKE '%standard%' OR name ILIKE '%econom%';

UPDATE public.services SET vehicle_category = 'moto' 
WHERE name ILIKE '%moto%';

UPDATE public.services SET vehicle_category = 'suv' 
WHERE name ILIKE '%suv%';

UPDATE public.services SET vehicle_category = 'executivo' 
WHERE name ILIKE '%executivo%' OR name ILIKE '%premium%' OR name ILIKE '%black%';

-- Fallback para os serviços que não bateram em nenhuma regra acima
UPDATE public.services SET vehicle_category = 'carro' 
WHERE vehicle_category IS NULL;
