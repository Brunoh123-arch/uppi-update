-- ==============================================================================
-- MIGRAÇÃO: Despacho Contínuo e Reativo de Corridas
-- Data: 2026-06-01
-- Objetivo: Garantir que corridas no status 'requested' sejam despachadas continuamente
-- e de forma reativa assim que os motoristas atualizarem localização ou status.
-- ==============================================================================

-- 1. ATUALIZAR SWEEP DE OFERTAS EXPIRADAS PARA SUPORTAR REDESPACHO CONTÍNUO (CRON JOB)
CREATE OR REPLACE FUNCTION public.rpc_sweep_expired_offers()
RETURNS TABLE (
    offer_id UUID,
    ride_id UUID,
    driver_id TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
    v_ride RECORD;
BEGIN
    -- 1a. Varre e expira ofertas que passaram do tempo limite de aceitação
    FOR r IN 
        SELECT ro.id, ro.ride_id, ro.driver_id
        FROM public.ride_offers ro
        WHERE ro.status = 'offered'
          AND ro.expires_at < now()
    LOOP
        -- Atualizar status da oferta para expirado
        UPDATE public.ride_offers
        SET status = 'expired'
        WHERE id = r.id AND status = 'offered';

        IF FOUND THEN
            -- Inserir motorista na lista de rejeitados para esta corrida para evitar novo loop imediato com o mesmo
            INSERT INTO public.ride_rejected_drivers (ride_id, driver_id)
            VALUES (r.ride_id, r.driver_id)
            ON CONFLICT (ride_id, driver_id) DO NOTHING;

            -- Tentar despachar instantaneamente para o próximo motorista geolocalizado
            PERFORM public.rpc_find_and_offer_ride(r.ride_id);

            -- Preencher valores de retorno
            offer_id := r.id;
            ride_id := r.ride_id;
            driver_id := r.driver_id;
            RETURN NEXT;
        END IF;
    END LOOP;

    -- 1b. REDESPACHO CONTÍNUO: Varrer corridas ativas travadas no status 'requested'
    -- (criadas nos últimos 20 minutos) que não possuem nenhuma oferta ativa pendente
    FOR v_ride IN
        SELECT r.id
        FROM public.rides r
        WHERE r.status = 'requested'
          AND r.created_at > now() - interval '20 minutes'
          AND NOT EXISTS (
              SELECT 1
              FROM public.ride_offers ro
              WHERE ro.ride_id = r.id
                AND ro.status = 'offered'
                AND ro.expires_at > now()
          )
    LOOP
        -- Tentar encontrar motoristas para essa corrida pendente
        PERFORM public.rpc_find_and_offer_ride(v_ride.id);
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.rpc_sweep_expired_offers() IS 'Expira ofertas ativas fora do tempo e executa varredura periódica para redespachar corridas pendentes travadas em requested.';

-- 2. CRIAR DISPARADOR DE DESPACHO REATIVO EM TEMPO REAL (TRIGGERS DE GEOLOCALIZAÇÃO/STATUS)
CREATE OR REPLACE FUNCTION public.trg_redispatch_on_driver_online_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ride RECORD;
    v_offered BOOLEAN;
BEGIN
    -- Se o motorista estiver online, tentar acoplar corridas pendentes na fila imediatamente
    IF NEW.status = 'online' THEN
        FOR v_ride IN
            SELECT r.id
            FROM public.rides r
            WHERE r.status = 'requested'
              AND r.created_at > now() - interval '20 minutes'
            ORDER BY r.created_at ASC
        LOOP
            -- Executa o algoritmo de despacho para a corrida pendente
            v_offered := public.rpc_find_and_offer_ride(v_ride.id);
            
            -- Se esse motorista específico acabou de ser selecionado e recebeu uma oferta ativamente,
            -- encerramos o loop de busca para ele (pois ele já está ocupado respondendo a uma oferta)
            IF EXISTS (
                SELECT 1
                FROM public.ride_offers ro
                WHERE ro.driver_id = NEW.driver_id
                  AND ro.ride_id = v_ride.id
                  AND ro.status = 'offered'
                  AND ro.expires_at > now()
            ) THEN
                EXIT;
            END IF;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.trg_redispatch_on_driver_online_fn() IS 'Verifica se há corridas requested pendentes e tenta despachá-las imediatamente assim que um motorista fica online ou move-se no mapa.';

-- Criar o trigger na tabela driver_locations
DROP TRIGGER IF EXISTS trg_redispatch_on_driver_online ON public.driver_locations;
CREATE TRIGGER trg_redispatch_on_driver_online
    AFTER INSERT OR UPDATE OF status, lat, lng ON public.driver_locations
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_redispatch_on_driver_online_fn();
