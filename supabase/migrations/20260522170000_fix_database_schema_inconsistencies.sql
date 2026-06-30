-- BUG A: Garantir que a tabela driver_earnings exista para novas instalações
CREATE TABLE IF NOT EXISTS public.driver_earnings (
  id                  UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  driver_id           TEXT REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  ride_id             UUID REFERENCES public.rides(id) ON DELETE CASCADE,
  amount              NUMERIC(10,2),
  gross_amount        NUMERIC(10,2),
  commission_pct      NUMERIC(5,2),
  commission_amt      NUMERIC(10,2),
  platform_commission NUMERIC(10,2),
  net_amount          NUMERIC(10,2),
  payment_method      TEXT,
  tip_amount          NUMERIC(10,2),
  driver_amount       NUMERIC(10,2),
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

-- Garantir que RLS esteja ativado
ALTER TABLE public.driver_earnings ENABLE ROW LEVEL SECURITY;

-- Se a tabela já existia com ride_id como TEXT, converter para UUID e adicionar a Foreign Key
DO $$
BEGIN
  -- Verificar o tipo de dados atual da coluna ride_id
  IF (SELECT data_type FROM information_schema.columns 
      WHERE table_schema = 'public' AND table_name = 'driver_earnings' AND column_name = 'ride_id') = 'text' THEN
    
    -- Alterar tipo da coluna para UUID
    ALTER TABLE public.driver_earnings ALTER COLUMN ride_id TYPE UUID USING ride_id::uuid;
  END IF;

  -- Adicionar a constraint de chave estrangeira com segurança
  ALTER TABLE public.driver_earnings DROP CONSTRAINT IF EXISTS driver_earnings_ride_id_fkey;
  ALTER TABLE public.driver_earnings 
    ADD CONSTRAINT driver_earnings_ride_id_fkey 
    FOREIGN KEY (ride_id) REFERENCES public.rides(id) ON DELETE CASCADE;
END $$;


-- BUG B: Corrigir tipo de ride_id de TEXT para UUID em complaints e sos_signals
DO $$
BEGIN
  -- complaints
  IF (SELECT data_type FROM information_schema.columns 
      WHERE table_schema = 'public' AND table_name = 'complaints' AND column_name = 'ride_id') = 'text' THEN
    ALTER TABLE public.complaints ALTER COLUMN ride_id TYPE UUID USING ride_id::uuid;
  END IF;
  
  ALTER TABLE public.complaints DROP CONSTRAINT IF EXISTS complaints_ride_id_fkey;
  ALTER TABLE public.complaints 
    ADD CONSTRAINT complaints_ride_id_fkey 
    FOREIGN KEY (ride_id) REFERENCES public.rides(id) ON DELETE SET NULL;

  -- sos_signals
  IF (SELECT data_type FROM information_schema.columns 
      WHERE table_schema = 'public' AND table_name = 'sos_signals' AND column_name = 'ride_id') = 'text' THEN
    ALTER TABLE public.sos_signals ALTER COLUMN ride_id TYPE UUID USING ride_id::uuid;
  END IF;

  ALTER TABLE public.sos_signals DROP CONSTRAINT IF EXISTS sos_signals_ride_id_fkey;
  ALTER TABLE public.sos_signals 
    ADD CONSTRAINT sos_signals_ride_id_fkey 
    FOREIGN KEY (ride_id) REFERENCES public.rides(id) ON DELETE SET NULL;
END $$;


-- BUG C: Criar a RPC update_ride_status
CREATE OR REPLACE FUNCTION public.update_ride_status(
  p_ride_id  UUID,
  p_status   TEXT,
  p_actor_id TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  -- Atualizar o status da corrida
  UPDATE public.rides
     SET status = p_status,
         updated_at = NOW()
   WHERE id = p_ride_id;

  -- Se um ator foi fornecido, registrar a atividade correspondente
  IF p_actor_id IS NOT NULL THEN
    INSERT INTO public.ride_activities (ride_id, type, actor_id)
    VALUES (p_ride_id, p_status, p_actor_id);
  END IF;
END;
$$;

-- Conceder permissões de execução
GRANT EXECUTE ON FUNCTION public.update_ride_status TO authenticated, service_role;
