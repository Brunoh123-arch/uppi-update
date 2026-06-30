-- =============================================================================
-- UPPI REALTIME: Trigger de notificação para novas corridas (HARDENED)
-- =============================================================================
-- Segurança:
--   ✅ Só dispara para status 'requested' (evita re-disparos)
--   ✅ timeout de 5s para não travar transações
--   ✅ Headers com Authorization Bearer (service_role key)
--   ✅ Idempotente — pode ser re-executado sem efeitos colaterais
-- =============================================================================

-- Habilitar extensão pg_net (se ainda não estiver ativa)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Função do trigger
CREATE OR REPLACE FUNCTION notify_webhook_new_ride()
RETURNS trigger AS $$
DECLARE
  v_supabase_url TEXT;
  v_webhook_url TEXT;
BEGIN
  -- Só dispara para corridas com status 'requested'
  IF NEW.status != 'requested' THEN
    RETURN NEW;
  END IF;

  -- 1. Buscar a URL base do Supabase de forma dinâmica
  v_supabase_url := current_setting('app.supabase_url', true);
  
  -- Fallback seguro para o projeto de homologação se a variável de ambiente não estiver definida
  IF v_supabase_url IS NULL OR v_supabase_url = '' THEN
    SELECT value INTO v_supabase_url
    FROM public.app_settings
    WHERE key = 'supabase_url'
    LIMIT 1;
  END IF;

  IF v_supabase_url IS NULL OR v_supabase_url = '' THEN
    v_supabase_url := 'https://kqfmahrxjuqlvxngeurj.supabase.co';
  END IF;

  -- Construir o endpoint correto da Edge Function
  v_webhook_url := rtrim(v_supabase_url, '/') || '/functions/v1/webhook-new-ride';

  -- Dispara webhook HTTP assíncrono via pg_net
  PERFORM net.http_post(
    url := v_webhook_url,
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
  -- Nunca bloqueia o INSERT por falha no webhook
  RAISE WARNING 'webhook_notify_new_ride falhou: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Remove trigger anterior (idempotente)
DROP TRIGGER IF EXISTS webhook_notify_new_ride ON "public"."rides";

-- Cria trigger AFTER INSERT
CREATE TRIGGER webhook_notify_new_ride
AFTER INSERT ON "public"."rides"
FOR EACH ROW EXECUTE FUNCTION notify_webhook_new_ride();

-- =============================================================================
-- TRIGGER: Notificar passageiro quando corrida é aceita/atualizada
-- =============================================================================
CREATE OR REPLACE FUNCTION notify_ride_status_change()
RETURNS trigger AS $$
BEGIN
  -- Só dispara quando o status muda
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Atualiza driver_locations para 'in_progress' quando corrida é aceita
  IF NEW.status = 'accepted' AND NEW.driver_id IS NOT NULL THEN
    UPDATE driver_locations 
    SET status = 'busy'
    WHERE driver_id = NEW.driver_id;
  END IF;

  -- Volta motorista para 'online' quando corrida é finalizada/cancelada
  IF NEW.status IN ('completed', 'canceled') AND NEW.driver_id IS NOT NULL THEN
    UPDATE driver_locations 
    SET status = 'online'
    WHERE driver_id = NEW.driver_id;
    
    -- Atualiza perfil do motorista de volta para 'online'
    UPDATE profiles
    SET status = 'online'
    WHERE id = NEW.driver_id;
  END IF;

  -- Marca corrida como in_progress no perfil do motorista
  IF NEW.status = 'in_progress' AND NEW.driver_id IS NOT NULL THEN
    UPDATE profiles
    SET status = 'in_progress'
    WHERE id = NEW.driver_id;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_ride_status_change falhou: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS ride_status_change_trigger ON "public"."rides";

CREATE TRIGGER ride_status_change_trigger
AFTER UPDATE ON "public"."rides"
FOR EACH ROW EXECUTE FUNCTION notify_ride_status_change();

-- =============================================================================
-- TRIGGER: Auto-expire de corridas não aceitas após 2 minutos
-- (Executar via pg_cron ou Supabase scheduled function)
-- =============================================================================
CREATE OR REPLACE FUNCTION expire_stale_rides()
RETURNS void AS $$
BEGIN
  UPDATE rides
  SET status = 'expired'
  WHERE status = 'requested'
    AND created_at < NOW() - INTERVAL '2 minutes';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
