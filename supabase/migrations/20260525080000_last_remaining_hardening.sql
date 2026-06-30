-- Migration: Last remaining hardening items
-- Resolves: 
-- 1. Issue 3: reviews_insert policy hardening on public.reviews to strictly enforce ride participation.
-- 2. Issue 4: Revokes public/authenticated execution permissions on finish_ride financial transaction.

-- 1. Tighten reviews_insert policy to verify that the reviewer was a participant of the ride (rider or driver)
DROP POLICY IF EXISTS "reviews_insert" ON public.reviews;

CREATE POLICY "reviews_insert" ON public.reviews
    FOR INSERT TO authenticated
    WITH CHECK (
        auth.uid()::text = reviewer_id AND 
        EXISTS (
            SELECT 1 FROM public.rides r 
            WHERE r.id = ride_id AND (r.rider_id = auth.uid()::text OR r.driver_id = auth.uid()::text)
        )
    );

-- 2. Revoke PUBLIC, authenticated and anon execution permissions from the finish_ride financial function
REVOKE EXECUTE ON FUNCTION public.finish_ride(uuid, text, numeric) FROM PUBLIC, anon, authenticated;

-- Explicitly grant execute only to the service_role (which is used by our Deno Edge Function finish-order)
GRANT EXECUTE ON FUNCTION public.finish_ride(uuid, text, numeric) TO service_role;
