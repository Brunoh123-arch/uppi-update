-- ==============================================================================
-- UPPI DB CLEANUP: Remoção da tabela obsoleta vehicle_categories
-- ==============================================================================
-- Motivo: Esta tabela está completamente órfã e sem nenhuma referência no
-- código do monorepo (frontend, backend ou outras migrations).
-- ==============================================================================

DROP TABLE IF EXISTS public.vehicle_categories CASCADE;
