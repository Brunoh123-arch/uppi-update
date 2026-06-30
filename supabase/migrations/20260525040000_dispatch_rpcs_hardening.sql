-- Migration: Hardening Dispatch RPCs and Offer Notification Trigger
-- Proteger assign_driver_to_ride, reject_ride, rpc_find_and_offer_ride e rpc_sweep_expired_offers
-- Substituir o webhook de nova corrida para disparar no insert de ride_offers (status = 'offered')

-- 1. BLINDAR ASSIGN_DRIVER_TO_RIDE
CREATE OR REPLACE FUNCTION public.assign_driver_to_ride(
    p_ride_id UUID,
    p_driver_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_status TEXT;
    v_rows INT;
    v_driver_lat DOUBLE PRECISION;
    v_driver_lng DOUBLE PRECISION;
    v_pickup_lat DOUBLE PRECISION;
    v_pickup_lng DOUBLE PRECISION;
    v_dist_meters DOUBLE PRECISION;
    v_eta_minutes INTEGER;
    v_eta_pickup TIMESTAMP WITH TIME ZONE;
BEGIN
    -- [SEGURANÇA] Validar se o solicitante é de fato o motorista ou service_role
    IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR auth.uid()::text <> p_driver_id) THEN
        RAISE EXCEPTION 'Operação não autorizada. O motorista não corresponde ao usuário autenticado.';
    END IF;

    -- [SEGURANÇA] Bloquear linha da corrida para evitar conflitos concorrentes
    SELECT status, pickup_lat, pickup_lng INTO v_status, v_pickup_lat, v_pickup_lng
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Corrida não encontrada (ID: %)', p_ride_id;
    END IF;

    -- Agora aceitamos tanto 'requested' quanto 'searching'
    IF v_status NOT IN ('requested', 'searching') THEN
        RAISE EXCEPTION 'A corrida não está mais disponível para aceite (status atual: %)', v_status;
    END IF;

    -- [SEGURANÇA] Atualizar oferta específica deste motorista como 'accepted' e garantir que ela existia e estava ativa
    UPDATE public.ride_offers
    SET status = 'accepted'
    WHERE ride_id = p_ride_id AND driver_id = p_driver_id AND status = 'offered';
    
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 0 THEN
        RAISE EXCEPTION 'Você não possui uma oferta ativa para esta corrida.';
    END IF;

    -- Expirar as demais ofertas ativas para essa corrida
    UPDATE public.ride_offers
    SET status = 'expired'
    WHERE ride_id = p_ride_id AND driver_id <> p_driver_id AND status = 'offered';

    -- Calcular ETA dinâmico baseado no PostGIS
    SELECT lat, lng INTO v_driver_lat, v_driver_lng
    FROM public.driver_locations
    WHERE driver_id = p_driver_id;

    IF v_driver_lat IS NOT NULL AND v_pickup_lat IS NOT NULL THEN
        v_dist_meters := ST_Distance(
            ST_SetSRID(ST_MakePoint(v_driver_lng, v_driver_lat), 4326)::geography,
            ST_SetSRID(ST_MakePoint(v_pickup_lng, v_pickup_lat), 4326)::geography
        );
        v_eta_minutes := CEIL(v_dist_meters / 500.0); -- ~30km/h
        v_eta_pickup := NOW() + (v_eta_minutes * interval '1 minute');
    ELSE
        v_eta_pickup := NOW() + interval '5 minutes';
    END IF;

    -- Atribuir o motorista à corrida, passar o status para 'accepted', definir accepted_at e eta_pickup
    UPDATE public.rides
    SET driver_id = p_driver_id,
        status = 'accepted',
        accepted_at = NOW(),
        eta_pickup = v_eta_pickup,
        updated_at = NOW()
    WHERE id = p_ride_id;
END;
$$;

COMMENT ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) IS 'Atribui o motorista à corrida, marca a oferta como aceita e expira outras ofertas pendentes da mesma corrida. [Protegido via JWT e Validação de Oferta]';

-- 2. BLINDAR REJECT_RIDE
CREATE OR REPLACE FUNCTION public.reject_ride(
  p_ride_id UUID,
  p_driver_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- [SEGURANÇA] Validar se o solicitante é de fato o motorista ou service_role
  IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR auth.uid()::text <> p_driver_id) THEN
      RAISE EXCEPTION 'Operação não autorizada. O motorista não corresponde ao usuário autenticado.';
  END IF;

  -- Inserir nas rejeições de corridas para evitar nova oferta a este motorista
  INSERT INTO public.ride_rejected_drivers (ride_id, driver_id)
  VALUES (p_ride_id, p_driver_id)
  ON CONFLICT (ride_id, driver_id) DO NOTHING;

  -- Atualizar status da oferta para 'rejected'
  UPDATE public.ride_offers
  SET status = 'rejected'
  WHERE ride_id = p_ride_id AND driver_id = p_driver_id AND status = 'offered';

  -- Avançar o despacho para o próximo motorista imediatamente
  PERFORM public.rpc_find_and_offer_ride(p_ride_id);
END;
$$;

COMMENT ON FUNCTION public.reject_ride(UUID, TEXT) IS 'Registra a rejeição do motorista, atualiza a oferta para rejeitada e despacha instantaneamente para o próximo motorista geolocalizado. [Protegido via JWT]';

-- 3. RESTRINGIR PERMISSÕES DE FUNÇÕES DE BACKGROUND
REVOKE EXECUTE ON FUNCTION public.rpc_find_and_offer_ride(UUID) FROM authenticated, anon, public;
REVOKE EXECUTE ON FUNCTION public.rpc_sweep_expired_offers() FROM authenticated, anon, public;
GRANT EXECUTE ON FUNCTION public.rpc_find_and_offer_ride(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_sweep_expired_offers() TO service_role;

-- 4. ATUALIZAR TRIGGERS DE WEBHOOK DE NOTIFICAÇÃO
-- Remover o trigger de rides para evitar envio em massa
DROP TRIGGER IF EXISTS webhook_notify_new_ride ON "public"."rides";

-- Função do trigger na tabela ride_offers
CREATE OR REPLACE FUNCTION notify_webhook_new_offer()
RETURNS trigger AS $$
BEGIN
  -- Só dispara para ofertas com status 'offered'
  IF NEW.status != 'offered' THEN
    RETURN NEW;
  END IF;

  -- Dispara webhook HTTP assíncrono para a Edge Function webhook-new-ride
  PERFORM net.http_post(
    url := 'https://kqfmahrxjuqlvxngeurj.supabase.co/functions/v1/webhook-new-ride',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', current_setting('app.webhook_secret', true)
    ),
    body := json_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'schema', TG_TABLE_SCHEMA,
      'record', row_to_json(NEW),
      'timestamp', extract(epoch from now())
    )::jsonb,
    timeout_milliseconds := 5000
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Nunca bloqueia a inserção por falhas na notificação
  RAISE WARNING 'notify_webhook_new_offer falhou: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Criar trigger de ofertas
DROP TRIGGER IF EXISTS trg_on_ride_offer_created ON public.ride_offers;
CREATE TRIGGER trg_on_ride_offer_created
AFTER INSERT ON public.ride_offers
FOR EACH ROW EXECUTE FUNCTION notify_webhook_new_offer();
