-- ==============================================================================
-- ADD RPC FOR FINDING NEARBY REQUESTED RIDES (RIDE CHAINING)
-- ==============================================================================

-- Drop if exists to ensure idempotency
DROP FUNCTION IF EXISTS public.find_nearby_requested_rides(float8, float8, float8);

-- Create the function
CREATE OR REPLACE FUNCTION public.find_nearby_requested_rides(
    lat float8,
    lng float8,
    radius_meters float8 DEFAULT 3000
)
RETURNS TABLE (
    id UUID,
    pickup_address TEXT,
    dropoff_address TEXT,
    fare DECIMAL,
    dist_meters FLOAT8
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        r.id,
        r.pickup_address,
        r.dropoff_address,
        r.fare,
        ST_Distance(
            r.pickup_location,
            ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography
        ) AS dist_meters
    FROM public.rides r
    WHERE r.status = 'requested'
      AND r.driver_id IS NULL
      AND ST_DWithin(
          r.pickup_location,
          ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography,
          radius_meters
      )
    ORDER BY dist_meters ASC
    LIMIT 1; -- We only need the best match for ride chaining
END;
$$;
