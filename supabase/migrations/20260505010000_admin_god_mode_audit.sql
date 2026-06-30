-- =============================================================================
-- MIGRATION: AUDIT LOGS AND FRAUD MANAGEMENT - UPPI BRASIL
-- =============================================================================

-- 1. Admin Audit Log Table (Surgical Tracking)
CREATE TABLE IF NOT EXISTS public.admin_audit_log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    admin_id TEXT NOT NULL,
    action_type TEXT NOT NULL,
    target_user_id TEXT,
    target_resource_id TEXT,
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_log_admin ON public.admin_audit_log(admin_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_target ON public.admin_audit_log(target_user_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON public.admin_audit_log(created_at DESC);

-- 2. High Risk Drivers View (Anti-Fraud)
CREATE OR REPLACE VIEW public.high_risk_drivers AS
SELECT
    d.id AS driver_id,
    d.full_name,
    d.phone_number,
    COUNT(r.id) AS total_rides,
    SUM(CASE WHEN r.status IN ('driver_canceled', 'rider_canceled') THEN 1 ELSE 0 END) AS canceled_rides,
    (SUM(CASE WHEN r.status IN ('driver_canceled', 'rider_canceled') THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(r.id), 0)) * 100 AS cancellation_rate
FROM public.profiles d
LEFT JOIN public.rides r ON r.driver_id = d.id::text
WHERE d.role = 'driver'
GROUP BY d.id, d.full_name, d.phone_number
HAVING COUNT(r.id) >= 5 AND (SUM(CASE WHEN r.status IN ('driver_canceled', 'rider_canceled') THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(r.id), 0)) > 0.3;

-- RLS for Audit Table (Only Service Role can insert)
ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "deny_all_anon_auth" ON public.admin_audit_log
    FOR ALL USING (false);

-- 3. Surgical Financial Function per Driver
CREATE OR REPLACE FUNCTION get_driver_surgical_financials()
RETURNS TABLE (
    driver_id TEXT,
    total_rides_completed INT,
    gross_revenue FLOAT,
    uppi_fee_despesas FLOAT,
    net_earnings FLOAT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT
        d.id::text AS driver_id,
        COUNT(r.id)::INT AS total_rides_completed,
        COALESCE(SUM(r.fare), 0)::FLOAT AS gross_revenue,
        COALESCE(SUM(r.platform_fee), 0)::FLOAT AS uppi_fee_despesas,
        COALESCE(SUM(r.fare - r.platform_fee), 0)::FLOAT AS net_earnings
    FROM public.profiles d
    LEFT JOIN public.rides r ON r.driver_id = d.id::text AND r.status = 'completed'
    WHERE d.role = 'driver'
    GROUP BY d.id;
$$;