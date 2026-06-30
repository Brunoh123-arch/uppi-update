-- Migration: Admin Full Access to Support Tickets
-- Date: 2026-05-26 18:00:00

-- Ensure RLS is active
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

-- Drop policy if it exists
DROP POLICY IF EXISTS admin_all_access ON public.support_tickets;

-- Create policy for admin access
CREATE POLICY admin_all_access ON public.support_tickets
FOR ALL TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.admins WHERE id = auth.uid()::text
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.admins WHERE id = auth.uid()::text
  )
);

COMMENT ON POLICY admin_all_access ON public.support_tickets IS 'Permite que administradores tenham acesso total a todos os tickets de suporte para fins de gestão.';
