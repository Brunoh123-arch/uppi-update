DROP POLICY IF EXISTS "profiles_select_restricted" ON public.profiles;

CREATE POLICY "profiles_select_restricted" ON public.profiles
  FOR SELECT TO authenticated
  USING (
    -- 1. O próprio usuário pode ler seu próprio perfil
    auth.uid()::text = id
    
    -- 2. Administradores podem ler qualquer perfil
    OR EXISTS (
      SELECT 1 FROM public.admins WHERE id = auth.uid()::text
    )
    
    -- 3. Motoristas podem ver perfis de passageiros em suas corridas ativas/recentes/avaliação
    OR id IN (
      SELECT rider_id FROM public.rides
      WHERE driver_id = auth.uid()::text
      AND status IN ('accepted', 'arrived', 'in_progress', 'completed', 'waiting_for_post_pay', 'waiting_for_review', 'finished')
    )
    
    -- 4. Passageiros podem ver perfis de motoristas de suas corridas ativas/recentes/avaliação
    OR id IN (
      SELECT driver_id FROM public.rides
      WHERE rider_id = auth.uid()::text
      AND status IN ('accepted', 'arrived', 'in_progress', 'completed', 'waiting_for_post_pay', 'waiting_for_review', 'finished')
    )
    
    -- 5. Motoristas online podem ver passageiros de corridas que estão aguardando motorista ('requested')
    OR id IN (
      SELECT rider_id FROM public.rides
      WHERE status = 'requested'
    )
  );
