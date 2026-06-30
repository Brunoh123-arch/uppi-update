-- =============================================================================
-- MIGRATION: ALLOW ADMIN PANEL TO WRITE AND READ AUDIT LOGS
-- =============================================================================

-- Drop the restrictive policy
DROP POLICY IF EXISTS "deny_all_anon_auth" ON public.admin_audit_log;

-- Allow authenticated users (Admin Panel users) to INSERT
CREATE POLICY "allow_authenticated_insert" ON public.admin_audit_log
    FOR INSERT 
    TO authenticated 
    WITH CHECK (true);

-- Allow authenticated users to SELECT (for viewing the logs in the future)
CREATE POLICY "allow_authenticated_select" ON public.admin_audit_log
    FOR SELECT 
    TO authenticated 
    USING (true);
