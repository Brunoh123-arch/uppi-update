-- ==============================================================================
-- MIGRATION: Despacho Ponderado em Lote (Batching & Scored Dispatch)
-- Data: 2026-06-20
-- Autor: Antigravity
-- ==============================================================================

-- 1. Cria a função de despacho em lote com score ponderado (Algoritmo Húngaro Guloso Bipartido)
CREATE OR REPLACE FUNCTION public.rpc_batch_dispatch_scored()
RETURNS TABLE (
  ride_id UUID,
  driver_id TEXT,
  score FLOAT
) 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ride RECORD;
  v_best_driver_id TEXT;
  v_best_score FLOAT;
BEGIN
  -- Cria tabelas temporárias para armazenar os pools de corridas e motoristas
  CREATE TEMP TABLE temp_pending_rides ON COMMIT DROP AS
  SELECT r.id, r.pickup_lat, r.pickup_lng
  FROM public.rides r
  WHERE r.status = 'requested'
    AND r.created_at > now() - interval '20 minutes'
    AND NOT EXISTS (
      SELECT 1 
      FROM public.ride_offers ro 
      WHERE ro.ride_id = r.id 
        AND ro.status = 'offered' 
        AND ro.expires_at > now()
    );

  CREATE TEMP TABLE temp_available_drivers ON COMMIT DROP AS
  SELECT dl.driver_id, dl.lat, dl.lng, COALESCE(p.rating, 4.5)::FLOAT as rating
  FROM public.driver_locations dl
  LEFT JOIN public.profiles p ON p.id = dl.driver_id
  WHERE dl.status = 'online'
    -- Motorista não tem ofertas ativas
    AND NOT EXISTS (
      SELECT 1 
      FROM public.ride_offers ro 
      WHERE ro.driver_id = dl.driver_id 
        AND ro.status = 'offered' 
        AND ro.expires_at > now()
    )
    -- Motorista não está em corrida ativa
    AND NOT EXISTS (
      SELECT 1 
      FROM public.rides r 
      WHERE r.driver_id = dl.driver_id 
        AND r.status IN ('accepted', 'arrived', 'in_progress')
    );

  -- Loop guloso para encontrar o par ótimo de menor distância/maior score
  FOR v_ride IN SELECT * FROM temp_pending_rides LOOP
    -- Encontra o melhor motorista com base na fórmula de score geodésico + rating
    SELECT ad.driver_id, 
      (
        (1.0 / GREATEST(ST_Distance(
          ST_MakePoint(ad.lng::FLOAT, ad.lat::FLOAT)::geography,
          ST_MakePoint(v_ride.pickup_lng, v_ride.pickup_lat)::geography
        ) / 1000.0, 0.1)) * 0.4
        + ad.rating / 5.0 * 0.4
        + 0.2
      )::FLOAT AS calc_score INTO v_best_driver_id, v_best_score
    FROM temp_available_drivers ad
    WHERE NOT EXISTS (
      SELECT 1 
      FROM public.ride_rejected_drivers rr 
      WHERE rr.ride_id = v_ride.id 
        AND rr.driver_id = ad.driver_id
    )
    ORDER BY calc_score DESC
    LIMIT 1;

    -- Se um motorista elegível for encontrado, cria a oferta e retira o motorista do pool
    IF v_best_driver_id IS NOT NULL THEN
      -- Inserir nova oferta de 15 segundos
      INSERT INTO public.ride_offers (ride_id, driver_id, status, expires_at)
      VALUES (v_ride.id, v_best_driver_id, 'offered', now() + interval '15 seconds');

      -- Alterar status da corrida para 'searching'
      UPDATE public.rides
      SET status = 'searching',
          updated_at = now()
      WHERE id = v_ride.id;

      -- Remover motorista do pool temporário para evitar dupla oferta nesta rodada
      DELETE FROM temp_available_drivers WHERE temp_available_drivers.driver_id = v_best_driver_id;

      -- Retornar os dados do match
      ride_id := v_ride.id;
      driver_id := v_best_driver_id;
      score := v_best_score;
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$$;

-- 2. Atualiza a função rpc_find_and_offer_ride para usar get_nearby_drivers_scored
CREATE OR REPLACE FUNCTION public.rpc_find_and_offer_ride(p_ride_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pickup_lat FLOAT;
    v_pickup_lng FLOAT;
    v_ride_status TEXT;
    v_driver_id TEXT;
BEGIN
    -- Bloquear linha da corrida para evitar conflitos concorrentes
    SELECT status, pickup_lat, pickup_lng INTO v_ride_status, v_pickup_lat, v_pickup_lng
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    -- Se a corrida não existir ou já tiver sido aceita/cancelada, encerra o loop
    IF v_ride_status IS NULL OR v_ride_status NOT IN ('requested', 'searching') THEN
        RETURN FALSE;
    END IF;

    -- Buscar o motorista 'online' aprovado com o maior score via get_nearby_drivers_scored
    SELECT ds.driver_id INTO v_driver_id
    FROM public.get_nearby_drivers_scored(v_pickup_lat, v_pickup_lng, 5.0) ds
    WHERE NOT EXISTS (
        SELECT 1 
        FROM public.ride_rejected_drivers rr 
        WHERE rr.ride_id = p_ride_id 
          AND rr.driver_id = ds.driver_id
    )
    -- Evitar motoristas em corridas ativas
    AND NOT EXISTS (
        SELECT 1 
        FROM public.rides r 
        WHERE r.driver_id = ds.driver_id 
          AND r.status IN ('accepted', 'arrived', 'in_progress')
    )
    -- Evitar motoristas com ofertas de corrida ativas pendentes
    AND NOT EXISTS (
        SELECT 1
        FROM public.ride_offers ro
        WHERE ro.driver_id = ds.driver_id
          AND ro.status = 'offered'
          AND ro.expires_at > now()
    )
    ORDER BY ds.score DESC
    LIMIT 1;

    -- Se um motorista elegível for encontrado, criar a oferta e atualizar o status
    IF v_driver_id IS NOT NULL THEN
        -- Expirar ofertas anteriores ainda marcadas como 'offered' para esta corrida
        UPDATE public.ride_offers
        SET status = 'expired'
        WHERE ride_id = p_ride_id AND status = 'offered';

        -- Inserir nova oferta de 15 segundos
        INSERT INTO public.ride_offers (ride_id, driver_id, status, expires_at)
        VALUES (p_ride_id, v_driver_id, 'offered', now() + interval '15 seconds');

        -- Alterar status da corrida para 'searching'
        UPDATE public.rides
        SET status = 'searching',
            updated_at = now()
        WHERE id = p_ride_id;

        RETURN TRUE;
    ELSE
        -- Nenhum motorista encontrado na região: reverter status para 'requested'
        UPDATE public.rides
        SET status = 'requested',
            updated_at = now()
        WHERE id = p_ride_id AND status = 'searching';

        RETURN FALSE;
    END IF;
END;
$$;

-- 3. Atualizar rpc_sweep_expired_offers para usar o rpc_batch_dispatch_scored (despacho contínuo em lote)
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
BEGIN
    -- 1. Varre e expira ofertas que passaram do tempo limite de aceitação
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
            -- Inserir motorista na lista de rejeitados para esta corrida para evitar novo loop imediato
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

    -- 2. DISPARAR DESPACHO EM LOTE PONDERADO (BATCHING)
    -- Em vez de despachar um por um de forma FCFS simples, roda o algoritmo guloso bipartido.
    PERFORM public.rpc_batch_dispatch_scored();
END;
$$;

-- Privilégios
GRANT EXECUTE ON FUNCTION public.rpc_batch_dispatch_scored() TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_batch_dispatch_scored() TO service_role;
