-- ==============================================================================
-- MIGRAÇÃO DE SEGURANÇA E PROTEÇÃO CONTRA FRAUDES — UPPI BRASIL
-- Criado em: 2026-05-26
-- Objetivo:
-- 1. Restringir acesso de leitura a driver_locations via RLS (bloquear colheita de GPS)
-- 2. Impedir fraude de alteração de tarifas calculando e sobrescrevendo 'fare' no servidor
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- PARTE 1: Hardening de RLS para driver_locations
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Anyone can read driver locations" ON public.driver_locations;
DROP POLICY IF EXISTS "driver_locations_select" ON public.driver_locations;

-- Restringe o SELECT a si mesmo, admins ou passageiros com corrida ativa vinculada
CREATE POLICY "driver_locations_select" ON public.driver_locations
  FOR SELECT TO authenticated
  USING (
    -- 1. O próprio motorista pode ler sua localização
    auth.uid()::text = driver_id
    
    -- 2. Administradores podem ler qualquer localização
    OR EXISTS (
      SELECT 1 FROM public.admins WHERE id = auth.uid()::text
    )
    
    -- 3. Passageiro associado à corrida ativa com este motorista
    OR driver_id IN (
      SELECT driver_id FROM public.rides
      WHERE rider_id = auth.uid()::text
        AND status IN ('accepted', 'arrived', 'in_progress', 'waiting_for_post_pay')
    )
  );

-- Nota: A busca pública por raio de motoristas próximos via nearby_drivers() 
-- continuará funcionando perfeitamente porque a função está definida como SECURITY DEFINER,
-- o que ignora RLS da tabela interna no momento da execução, protegendo os dados reais
-- de acessos arbitrários ao mesmo tempo.

-- ─────────────────────────────────────────────────────────────────────────────
-- PARTE 2: Proteção de Tarifa (Anti-Proxy / Charles Intercept)
-- ─────────────────────────────────────────────────────────────────────────────

-- Função de trigger para cálculo e sobrescrita automática de preço
CREATE OR REPLACE FUNCTION public.calculate_and_override_ride_fare()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_service RECORD;
  v_base_fare NUMERIC;
  v_per_km NUMERIC;
  v_per_min NUMERIC;
  v_min_fare NUMERIC;
  v_distance_km NUMERIC;
  v_duration_min NUMERIC;
  v_calculated_fare NUMERIC;
  v_surge_calc JSONB;
BEGIN
  -- 1. Identificar o tipo de serviço (Regular, Premium, etc.)
  IF NEW.service_id IS NOT NULL THEN
    SELECT * INTO v_service FROM public.services WHERE id = NEW.service_id;
  ELSIF NEW.service_type IS NOT NULL THEN
    SELECT * INTO v_service FROM public.services WHERE name = NEW.service_type;
  END IF;

  -- Fallback para o serviço 'Regular' se não encontrado
  IF v_service.id IS NULL THEN
    SELECT * INTO v_service FROM public.services WHERE name = 'Regular' LIMIT 1;
  END IF;

  -- Obter parâmetros de precificação do serviço
  v_base_fare := COALESCE(v_service.base_fare, 5.00);
  v_per_km := COALESCE(v_service.per_km_fare, 2.00);
  v_per_min := COALESCE(v_service.per_minute_fare, 0.50);
  v_min_fare := COALESCE(v_service.minimum_fare, 7.00);

  -- 2. Calcular distância em KM e duração em minutos
  v_distance_km := COALESCE(NEW.distance, (NEW.distance_meters::numeric / 1000.0), 0);
  v_duration_min := COALESCE(NEW.duration, (NEW.duration_seconds::numeric / 60.0), 0);

  -- 3. Calcular a tarifa base do serviço
  v_calculated_fare := v_base_fare + (v_distance_km * v_per_km) + (v_duration_min * v_per_min);

  -- Garantir tarifa mínima
  IF v_calculated_fare < v_min_fare THEN
    v_calculated_fare := v_min_fare;
  END IF;

  -- 4. Aplicar preço dinâmico (Surge Zones) se houver coordenadas de pickup/dropoff
  IF NEW.pickup_lat IS NOT NULL AND NEW.pickup_lng IS NOT NULL AND NEW.dropoff_lat IS NOT NULL AND NEW.dropoff_lng IS NOT NULL THEN
    BEGIN
      v_surge_calc := public.rpc_calculate_ride_fare(
        NEW.pickup_lat::float8,
        NEW.pickup_lng::float8,
        NEW.dropoff_lat::float8,
        NEW.dropoff_lng::float8,
        v_calculated_fare
      );
      v_calculated_fare := (v_surge_calc->>'final_fare')::numeric;
    EXCEPTION WHEN OTHERS THEN
      -- Em caso de erro na RPC de preço dinâmico, mantém a tarifa base calculada
    END;
  END IF;

  -- 5. Sobrescrever com o valor calculado no servidor para evitar manipulação de proxy
  NEW.fare := ROUND(v_calculated_fare, 2);
  NEW.original_fare := NEW.fare;

  RETURN NEW;
END;
$$;

-- Registrar trigger BEFORE INSERT na tabela rides
DROP TRIGGER IF EXISTS trg_override_ride_fare ON public.rides;
CREATE TRIGGER trg_override_ride_fare
  BEFORE INSERT ON public.rides
  FOR EACH ROW
  EXECUTE FUNCTION public.calculate_and_override_ride_fare();
