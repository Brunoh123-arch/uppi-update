-- ==============================================================================
-- ADD RPC FOR ASSIGNING A DRIVER TO A RIDE
-- ==============================================================================

DROP FUNCTION IF EXISTS public.assign_driver_to_ride(UUID, TEXT);

CREATE OR REPLACE FUNCTION public.assign_driver_to_ride(
    p_ride_id UUID,
    p_driver_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_status TEXT;
BEGIN
    -- 1. Lock the ride row to prevent race conditions
    SELECT status INTO v_status
    FROM public.rides
    WHERE id = p_ride_id
    FOR UPDATE;

    -- 2. Check if the ride exists
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Corrida não encontrada (ID: %)', p_ride_id;
    END IF;

    -- 3. Check if the ride is still requested
    IF v_status <> 'requested' THEN
        RAISE EXCEPTION 'A corrida não está mais disponível (status atual: %)', v_status;
    END IF;

    -- 4. Update the ride
    UPDATE public.rides
    SET driver_id = p_driver_id,
        status = 'accepted',
        updated_at = now()
    WHERE id = p_ride_id;
END;
$$;
