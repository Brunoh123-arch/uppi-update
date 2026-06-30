-- ==============================================================================
-- MIGRAÇÃO: Despacho Automático de Corridas Agendadas (booked)
-- 1. rpc_dispatch_scheduled_rides()
-- 2. Cron job 'dispatch-scheduled-rides' (a cada minuto)
-- 3. Atualizar cron job 'cleanup-expired-rides' para respeitar expected_at
-- ==============================================================================

-- 1. FUNÇÃO DE DESPACHO DE AGENDAMENTOS
CREATE OR REPLACE FUNCTION public.rpc_dispatch_scheduled_rides()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
BEGIN
    -- Busca corridas agendadas ('booked') que devem ser iniciadas nos próximos 15 minutos
    FOR r IN 
        SELECT id 
        FROM public.rides 
        WHERE status = 'booked' 
          AND expected_at IS NOT NULL 
          AND expected_at <= now() + interval '15 minutes'
    LOOP
        -- Atualiza para 'requested', o que dispara automaticamente o trigger trg_on_ride_requested
        UPDATE public.rides
        SET status = 'requested',
            updated_at = now()
        WHERE id = r.id;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.rpc_dispatch_scheduled_rides() IS 'Varre as corridas agendadas (booked) e altera o status para requested faltando 15 minutos para o horário esperado, acionando o loop geolocalizado de despacho.';

-- 2. AGENDAR DESPACHO NO PG_CRON (a cada minuto)
SELECT cron.unschedule('dispatch-scheduled-rides') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dispatch-scheduled-rides');
SELECT cron.schedule(
  'dispatch-scheduled-rides',
  '* * * * *',
  $$
    SELECT public.rpc_dispatch_scheduled_rides();
  $$
);

-- 3. AJUSTAR CRON DE LIMPEZA EXISTENTE PARA RESPEITAR EXPECTED_AT
SELECT cron.unschedule('cleanup-expired-rides') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup-expired-rides');
SELECT cron.schedule(
  'cleanup-expired-rides',
  '*/5 * * * *',
  $$
    UPDATE public.rides
    SET status = 'expired', updated_at = now()
    WHERE status = 'requested'
      AND driver_id IS NULL
      AND COALESCE(expected_at, created_at) < now() - interval '3 minutes';
  $$
);

-- Garantir privilégios
GRANT EXECUTE ON FUNCTION public.rpc_dispatch_scheduled_rides() TO authenticated;
