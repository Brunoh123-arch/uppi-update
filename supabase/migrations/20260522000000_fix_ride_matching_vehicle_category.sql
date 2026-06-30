-- Migration: Fix Ride Matching by Vehicle Category
-- Updates rpc_find_and_offer_ride to match profiles.vehicle_type with services.vehicle_category

CREATE OR REPLACE FUNCTION public.rpc_find_and_offer_ride(p_ride_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pickup_loc GEOGRAPHY(POINT);
    v_ride_status TEXT;
    v_service_type TEXT;
    v_driver_id TEXT;
    v_offer_id UUID;
    v_search_radius INTEGER;
BEGIN
    -- 1. Bloquear linha da corrida para evitar conflitos de concorrência
    SELECT status, pickup_location, service_type INTO v_ride_status, v_pickup_loc, v_service_type
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    -- Se a corrida não existir ou já tiver sido aceita/cancelada, encerra o loop
    IF v_ride_status IS NULL OR v_ride_status NOT IN ('requested', 'searching') THEN
        RETURN FALSE;
    END IF;

    -- 2. Buscar o motorista 'online' aprovado mais próximo que ainda não rejeitou esta corrida, não esteja ocupado e tenha categoria compatível
    SELECT p.id, COALESCE(p.search_radius, 5000) INTO v_driver_id, v_search_radius
    FROM public.profiles p
    WHERE p.role = 'driver'
      AND p.status = 'online'
      AND p.current_location IS NOT NULL
      -- Filtrar por categoria do veículo correspondente ao serviço solicitado na corrida
      AND (
          v_service_type IS NULL OR
          p.vehicle_type IS NULL OR
          p.vehicle_type = COALESCE(
              (SELECT s.vehicle_category FROM public.services s WHERE s.name = v_service_type LIMIT 1),
              'carro'
          )
      )
      -- Evitar motoristas que já rejeitaram ou expiraram esta corrida
      AND NOT EXISTS (
          SELECT 1 
          FROM public.ride_rejected_drivers rr 
          WHERE rr.ride_id = p_ride_id 
            AND rr.driver_id = p.id
      )
      -- Evitar motoristas em corridas ativas
      AND NOT EXISTS (
          SELECT 1 
          FROM public.rides r 
          WHERE r.driver_id = p.id 
            AND r.status IN ('accepted', 'arrived', 'in_progress')
      )
      -- Evitar motoristas com ofertas de corrida ativas pendentes (de qualquer corrida)
      AND NOT EXISTS (
          SELECT 1
          FROM public.ride_offers ro
          WHERE ro.driver_id = p.id
            AND ro.status = 'offered'
            AND ro.expires_at > now()
      )
    ORDER BY ST_Distance(p.current_location, v_pickup_loc) ASC
    LIMIT 1;

    -- 3. Se um motorista elegível for encontrado, criar a oferta e atualizar o status
    IF v_driver_id IS NOT NULL THEN
        -- Expirar ofertas anteriores ainda marcadas como 'offered' para esta corrida
        UPDATE public.ride_offers
        SET status = 'expired'
        WHERE ride_id = p_ride_id AND status = 'offered';

        -- Inserir nova oferta de 15 segundos
        INSERT INTO public.ride_offers (ride_id, driver_id, status, expires_at)
        VALUES (p_ride_id, v_driver_id, 'offered', now() + interval '15 seconds')
        RETURNING id INTO v_offer_id;

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
