-- Migration: Create suspicious_devices table and rpc_flag_suspicious_device function
-- Created at: 2026-05-26 15:00:00

-- Create suspicious_devices table
CREATE TABLE IF NOT EXISTS public.suspicious_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id TEXT REFERENCES public.profiles(id) ON DELETE CASCADE,
    threat_type TEXT NOT NULL CHECK (threat_type IN ('root_jailbreak', 'emulator', 'fake_gps')),
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.suspicious_devices ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to insert security logs
DROP POLICY IF EXISTS "Allow authenticated users to insert security logs" ON public.suspicious_devices;
CREATE POLICY "Allow authenticated users to insert security logs"
    ON public.suspicious_devices
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid()::text = profile_id);

-- Allow authenticated users to select their own logs
DROP POLICY IF EXISTS "Allow authenticated users to select their own logs" ON public.suspicious_devices;
CREATE POLICY "Allow authenticated users to select their own logs"
    ON public.suspicious_devices
    FOR SELECT
    TO authenticated
    USING (auth.uid()::text = profile_id);

-- Create RPC function to log alert and block profile
CREATE OR REPLACE FUNCTION public.rpc_flag_suspicious_device(p_threat_type TEXT, p_details JSONB)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Insert log
  INSERT INTO public.suspicious_devices (profile_id, threat_type, details)
  VALUES (auth.uid()::text, p_threat_type, p_details);

  -- Block driver profile
  UPDATE public.profiles
  SET status = 'blocked',
      is_approved = false,
      updated_at = now()
  WHERE id = auth.uid()::text;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_flag_suspicious_device(TEXT, JSONB) TO authenticated;
