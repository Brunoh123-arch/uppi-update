-- Migration: Secure public.rpc_get_or_create_ride_share_token against BOLA
-- Ensures only participants of the ride or admins can generate a sharing token.

CREATE OR REPLACE FUNCTION public.rpc_get_or_create_ride_share_token(
    p_ride_id UUID,
    p_user_id TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_token TEXT;
    v_exists_token TEXT;
    v_is_authorized BOOLEAN := false;
BEGIN
    -- 1. Verify authorization (BOLA check)
    SELECT EXISTS (
        SELECT 1 FROM public.rides
        WHERE id = p_ride_id
          AND (rider_id = auth.uid()::text OR driver_id = auth.uid()::text)
    ) INTO v_is_authorized;

    -- Allow admins to generate share tokens
    IF NOT v_is_authorized THEN
        SELECT EXISTS (
            SELECT 1 FROM public.admins
            WHERE id = auth.uid()::text
        ) INTO v_is_authorized;
    END IF;

    IF NOT v_is_authorized THEN
        RAISE EXCEPTION 'Operação não autorizada. Apenas participantes ou administradores podem gerar tokens de compartilhamento.';
    END IF;

    -- 2. Check if a valid token already exists
    SELECT share_token INTO v_exists_token
    FROM public.ride_tracking_shares
    WHERE ride_id = p_ride_id
      AND expires_at > now()
    LIMIT 1;

    IF v_exists_token IS NOT NULL THEN
        RETURN v_exists_token;
    END IF;

    -- 3. Generate new secure MD5 token
    v_token := md5(gen_random_uuid()::text || now()::text);

    -- 4. Insert securely using authenticated user ID (preventing p_user_id forging)
    INSERT INTO public.ride_tracking_shares (ride_id, share_token, created_by, expires_at)
    VALUES (p_ride_id, v_token, auth.uid()::text, now() + interval '2 hours');

    RETURN v_token;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_or_create_ride_share_token(UUID, TEXT) TO authenticated;
