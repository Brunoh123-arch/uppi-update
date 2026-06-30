-- ==============================================================================
-- MIGRAÇÃO PILAR 18 — DESPACHO PREDITIVO
-- Análise de Demanda Histórica + Push Preventivo para Motoristas
-- ==============================================================================
-- Tabelas: demand_forecasts, predictive_alerts
-- Functions: fn_analyze_demand_patterns(), fn_generate_predictive_alerts()
-- PG Cron: análise diária + alertas a cada 15 minutos
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. TABELA demand_forecasts — Previsões calculadas por análise histórica
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.demand_forecasts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    zone_key TEXT NOT NULL,                           -- ex: '123_456' (lat/lng index ~1km²)
    zone_lat FLOAT8 NOT NULL,
    zone_lng FLOAT8 NOT NULL,
    day_of_week INT NOT NULL CHECK (day_of_week >= 0 AND day_of_week <= 6),   -- 0=domingo
    hour_of_day INT NOT NULL CHECK (hour_of_day >= 0 AND hour_of_day <= 23),
    avg_rides NUMERIC(8,2) DEFAULT 0,
    predicted_demand NUMERIC(8,2) DEFAULT 0,
    confidence NUMERIC(5,2) DEFAULT 0,
    sample_weeks INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(zone_key, day_of_week, hour_of_day)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. TABELA predictive_alerts — Alertas gerados para push aos motoristas
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.predictive_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    zone_key TEXT NOT NULL,
    zone_lat FLOAT8 NOT NULL,
    zone_lng FLOAT8 NOT NULL,
    predicted_demand NUMERIC(8,2),
    available_drivers INT DEFAULT 0,
    alert_type TEXT DEFAULT 'high_demand' CHECK (alert_type IN ('high_demand', 'surge_predicted', 'low_supply')),
    message TEXT,
    sent_at TIMESTAMPTZ,                              -- NULL = pendente de envio
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Índices para consultas frequentes
CREATE INDEX IF NOT EXISTS idx_demand_forecasts_lookup
  ON public.demand_forecasts (day_of_week, hour_of_day, confidence);

CREATE INDEX IF NOT EXISTS idx_predictive_alerts_pending
  ON public.predictive_alerts (sent_at, expires_at)
  WHERE sent_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_predictive_alerts_zone_created
  ON public.predictive_alerts (zone_key, created_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. FUNCTION fn_analyze_demand_patterns() — Análise histórica de demanda
-- ─────────────────────────────────────────────────────────────────────────────
-- Analisa corridas dos últimos 30 dias, agrupa por zona geográfica (~1km²),
-- dia da semana e hora, e calcula médias + previsões com margem de 10%.
-- Usa a mesma lógica de getNormalizedZoneKey do heatmap (corrige distorção lng).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_analyze_demand_patterns()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
BEGIN
  -- Iterar sobre agregações de corridas completadas/em revisão nos últimos 30 dias
  FOR rec IN
    SELECT
      -- Zona geográfica normalizada (~1km²)
      -- lat_index = ROUND(pickup_lat / 0.01)
      ROUND(r.pickup_lat / 0.01)::INT AS lat_index,
      -- lng_step = 0.01 / COS(RADIANS(pickup_lat))
      -- lng_index = ROUND(pickup_lng / lng_step)
      ROUND(r.pickup_lng / (0.01 / GREATEST(COS(RADIANS(r.pickup_lat)), 0.1)))::INT AS lng_index,
      -- Usar o centro da zona para lat/lng representativo
      ROUND(r.pickup_lat / 0.01)::INT * 0.01 AS representative_lat,
      ROUND(r.pickup_lng / (0.01 / GREATEST(COS(RADIANS(r.pickup_lat)), 0.1)))::INT
        * (0.01 / GREATEST(COS(RADIANS(r.pickup_lat)), 0.1)) AS representative_lng,
      -- Dia da semana (0=domingo) e hora (fuso de Belém)
      EXTRACT(DOW FROM r.created_at)::INT AS dow,
      EXTRACT(HOUR FROM r.created_at AT TIME ZONE 'America/Belem')::INT AS hod,
      -- Métricas
      COUNT(*)::INT AS total_rides,
      COUNT(DISTINCT DATE(r.created_at))::INT AS sample_days
    FROM public.rides r
    WHERE r.status IN ('completed', 'waiting_for_review')
      AND r.created_at >= now() - INTERVAL '30 days'
      AND r.pickup_lat IS NOT NULL
      AND r.pickup_lng IS NOT NULL
    GROUP BY
      ROUND(r.pickup_lat / 0.01)::INT,
      ROUND(r.pickup_lng / (0.01 / GREATEST(COS(RADIANS(r.pickup_lat)), 0.1)))::INT,
      ROUND(r.pickup_lat / 0.01)::INT * 0.01,
      ROUND(r.pickup_lng / (0.01 / GREATEST(COS(RADIANS(r.pickup_lat)), 0.1)))::INT
        * (0.01 / GREATEST(COS(RADIANS(r.pickup_lat)), 0.1)),
      EXTRACT(DOW FROM r.created_at)::INT,
      EXTRACT(HOUR FROM r.created_at AT TIME ZONE 'America/Belem')::INT
  LOOP
    INSERT INTO public.demand_forecasts (
      zone_key, zone_lat, zone_lng,
      day_of_week, hour_of_day,
      avg_rides, predicted_demand, confidence, sample_weeks,
      updated_at
    ) VALUES (
      rec.lat_index || '_' || rec.lng_index,
      rec.representative_lat,
      rec.representative_lng,
      rec.dow,
      rec.hod,
      rec.total_rides::NUMERIC / GREATEST(rec.sample_days, 1),
      (rec.total_rides::NUMERIC / GREATEST(rec.sample_days, 1)) * 1.1,   -- margem de 10%
      LEAST(rec.sample_days::NUMERIC / 28.0 * 100, 100),                 -- % de semanas com dados
      rec.sample_days,
      now()
    )
    ON CONFLICT (zone_key, day_of_week, hour_of_day)
    DO UPDATE SET
      zone_lat         = EXCLUDED.zone_lat,
      zone_lng         = EXCLUDED.zone_lng,
      avg_rides        = EXCLUDED.avg_rides,
      predicted_demand = EXCLUDED.predicted_demand,
      confidence       = EXCLUDED.confidence,
      sample_weeks     = EXCLUDED.sample_weeks,
      updated_at       = now();
  END LOOP;

  RAISE NOTICE '[fn_analyze_demand_patterns] Análise concluída com sucesso';
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. FUNCTION fn_generate_predictive_alerts() — Gera alertas de demanda
-- ─────────────────────────────────────────────────────────────────────────────
-- Para a hora ATUAL + 1 (previsão 1h à frente) e dia da semana atual:
--   1. Busca previsões com confidence >= 50
--   2. Conta motoristas online por zona
--   3. Se predicted_demand >= 2 * available_drivers → gera alerta
--   4. Não gera duplicatas (mesmo zone_key nos últimos 60 minutos)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_generate_predictive_alerts()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target_hour INT;
  v_target_dow  INT;
  rec           RECORD;
  v_drivers     INT;
  v_existing    INT;
  v_alert_type  TEXT;
  v_message     TEXT;
BEGIN
  -- Hora alvo = hora atual em Belém + 1 (previsão 1h à frente)
  v_target_hour := EXTRACT(HOUR FROM (now() AT TIME ZONE 'America/Belem') + INTERVAL '1 hour')::INT;
  v_target_dow  := EXTRACT(DOW FROM now() AT TIME ZONE 'America/Belem')::INT;

  -- Iterar previsões com confiança suficiente para a hora/dia alvo
  FOR rec IN
    SELECT zone_key, zone_lat, zone_lng, predicted_demand, avg_rides
    FROM public.demand_forecasts
    WHERE day_of_week = v_target_dow
      AND hour_of_day = v_target_hour
      AND confidence >= 50
      AND predicted_demand > 0
    ORDER BY predicted_demand DESC
  LOOP
    -- Contar motoristas online nesta zona
    -- Usa a mesma lógica de zone_key para mapear coordenadas de motoristas
    SELECT COUNT(*) INTO v_drivers
    FROM public.driver_locations dl
    WHERE dl.status = 'online'
      AND (
        ROUND(dl.lat / 0.01)::INT || '_' ||
        ROUND(dl.lng / (0.01 / GREATEST(COS(RADIANS(dl.lat)), 0.1)))::INT
      ) = rec.zone_key;

    -- Verificar se a demanda prevista é >= 2x os motoristas disponíveis
    IF rec.predicted_demand >= 2 * GREATEST(v_drivers, 0) THEN

      -- Verificar se já existe alerta recente (últimos 60 min) para esta zona
      SELECT COUNT(*) INTO v_existing
      FROM public.predictive_alerts pa
      WHERE pa.zone_key = rec.zone_key
        AND pa.created_at >= now() - INTERVAL '60 minutes';

      IF v_existing = 0 THEN
        -- Determinar tipo de alerta
        IF v_drivers = 0 THEN
          v_alert_type := 'low_supply';
          v_message := format(
            '📍 Sem motoristas na região! Previsão de %.0f corridas entre %sh-%sh. Dirija-se à zona para garantir corridas!',
            rec.predicted_demand, v_target_hour, (v_target_hour + 1) % 24
          );
        ELSIF rec.predicted_demand >= 3 * v_drivers THEN
          v_alert_type := 'surge_predicted';
          v_message := format(
            '🔥 Pico de demanda previsto! ~%.0f corridas esperadas entre %sh-%sh, apenas %s motoristas na região. Aproveite!',
            rec.predicted_demand, v_target_hour, (v_target_hour + 1) % 24, v_drivers
          );
        ELSE
          v_alert_type := 'high_demand';
          v_message := format(
            '📈 Alta demanda prevista! ~%.0f corridas entre %sh-%sh com %s motoristas na zona. Bom momento para ficar online!',
            rec.predicted_demand, v_target_hour, (v_target_hour + 1) % 24, v_drivers
          );
        END IF;

        INSERT INTO public.predictive_alerts (
          zone_key, zone_lat, zone_lng,
          predicted_demand, available_drivers, alert_type,
          message, expires_at
        ) VALUES (
          rec.zone_key, rec.zone_lat, rec.zone_lng,
          rec.predicted_demand, v_drivers, v_alert_type,
          v_message, now() + INTERVAL '90 minutes'
        );
      END IF;
    END IF;
  END LOOP;

  RAISE NOTICE '[fn_generate_predictive_alerts] Geração de alertas concluída';
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. RLS — Row Level Security
-- ─────────────────────────────────────────────────────────────────────────────

-- demand_forecasts: SELECT para motoristas e admins
ALTER TABLE public.demand_forecasts ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='demand_forecasts' AND policyname='Motoristas e admins leem previsoes') THEN
    CREATE POLICY "Motoristas e admins leem previsoes" ON public.demand_forecasts
      FOR SELECT TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid()::text AND p.role = 'driver'
        )
        OR EXISTS (
          SELECT 1 FROM public.admins a
          WHERE a.id = auth.uid()::text
        )
      );
  END IF;
END $$;

-- demand_forecasts: INSERT/UPDATE/DELETE somente service_role (sem policy = bloqueado por RLS)
-- service_role bypassa RLS automaticamente, então não é necessária policy adicional

-- predictive_alerts: SELECT para motoristas e admins
ALTER TABLE public.predictive_alerts ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='predictive_alerts' AND policyname='Motoristas e admins leem alertas') THEN
    CREATE POLICY "Motoristas e admins leem alertas" ON public.predictive_alerts
      FOR SELECT TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid()::text AND p.role = 'driver'
        )
        OR EXISTS (
          SELECT 1 FROM public.admins a
          WHERE a.id = auth.uid()::text
        )
      );
  END IF;
END $$;

-- predictive_alerts: INSERT/UPDATE somente service_role (sem policy = bloqueado por RLS)

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. REALTIME — predictive_alerts para push em tempo real
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'predictive_alerts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.predictive_alerts;
  END IF;
END $$;

ALTER TABLE public.predictive_alerts REPLICA IDENTITY FULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. PG CRON — Agendamentos automáticos
-- ─────────────────────────────────────────────────────────────────────────────
-- Garantir extensão pg_cron
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 7a. Análise de demanda diária às 03:00 UTC
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'analyze_demand_daily') THEN
    PERFORM cron.schedule(
      'analyze_demand_daily',
      '0 3 * * *',
      $job$SELECT public.fn_analyze_demand_patterns()$job$
    );
  END IF;
END $$;

-- 7b. Geração de alertas preditivos a cada 15 minutos
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'predictive_alerts_15min') THEN
    PERFORM cron.schedule(
      'predictive_alerts_15min',
      '*/15 * * * *',
      $job$SELECT public.fn_generate_predictive_alerts()$job$
    );
  END IF;
END $$;

-- ==============================================================================
-- FIM DA MIGRAÇÃO PILAR 18 — DESPACHO PREDITIVO
-- ==============================================================================
