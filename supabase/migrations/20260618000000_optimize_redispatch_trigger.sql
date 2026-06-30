-- ==============================================================================
-- MIGRAÇÃO: Otimização do Trigger de Despacho (Redução de Carga no PostgreSQL)
-- Data: 2026-06-18
-- Ecossistema Uppi — Engenharia de Banco de Dados
-- ==============================================================================

-- 1. RECRIAR O TRIGGER PARA DISPARAR APENAS NA TRANSIÇÃO DE STATUS PARA 'online'
-- Isso evita que o trigger e a função PostGIS rodem em cada atualização de GPS (lat/lng) dos motoristas online.
DROP TRIGGER IF EXISTS trg_redispatch_on_driver_online ON public.driver_locations;

CREATE TRIGGER trg_redispatch_on_driver_online
    AFTER INSERT OR UPDATE OF status ON public.driver_locations
    FOR EACH ROW
    WHEN (NEW.status = 'online' AND (OLD.status IS DISTINCT FROM NEW.status OR OLD.status IS NULL))
    EXECUTE FUNCTION public.trg_redispatch_on_driver_online_fn();
