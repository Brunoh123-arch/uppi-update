-- ==============================================================================
-- MIGRAÇÃO: Isolamento do Módulo de Segurança (Esquema 'safety')
-- 1. Criar esquema safety
-- 2. Criar tabela safety.suspicious_devices e migrar dados existentes
-- 3. Habilitar RLS e políticas
-- 4. Atualizar RPC pública rpc_flag_suspicious_device
-- ==============================================================================

-- 1. CRIAR O ESQUEMA DE SEGURANÇA
CREATE SCHEMA IF NOT EXISTS safety;

-- 2. CRIAR A TABELA NO NOVO ESQUEMA
CREATE TABLE IF NOT EXISTS safety.suspicious_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id TEXT REFERENCES public.profiles_raw(id) ON DELETE CASCADE,
    threat_type TEXT NOT NULL CHECK (threat_type IN ('root_jailbreak', 'emulator', 'fake_gps')),
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Mover dados se a tabela antiga existir
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'suspicious_devices') THEN
        INSERT INTO safety.suspicious_devices (id, profile_id, threat_type, details, created_at)
        SELECT id, profile_id, threat_type, details, created_at FROM public.suspicious_devices
        ON CONFLICT (id) DO NOTHING;
        
        DROP TABLE public.suspicious_devices CASCADE;
    END IF;
END $$;

-- 3. HABILITAR RLS E POLÍTICAS NO NOVO ESQUEMA
ALTER TABLE safety.suspicious_devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow authenticated users to insert security logs" ON safety.suspicious_devices;
CREATE POLICY "Allow authenticated users to insert security logs"
    ON safety.suspicious_devices
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid()::text = profile_id);

DROP POLICY IF EXISTS "Allow authenticated users to select their own logs" ON safety.suspicious_devices;
CREATE POLICY "Allow authenticated users to select their own logs"
    ON safety.suspicious_devices
    FOR SELECT
    TO authenticated
    USING (auth.uid()::text = profile_id);

-- Permitir leitura completa para administradores
DROP POLICY IF EXISTS "Allow admins to read all security logs" ON safety.suspicious_devices;
CREATE POLICY "Allow admins to read all security logs"
    ON safety.suspicious_devices
    FOR ALL
    TO authenticated
    USING (
        EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
    );

-- 4. ATUALIZAR A RPC PÚBLICA PARA ESCREVER NO ESQUEMA SAFETY (Retrocompatibilidade)
CREATE OR REPLACE FUNCTION public.rpc_flag_suspicious_device(p_threat_type TEXT, p_details JSONB)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Insere o log no esquema safety
  INSERT INTO safety.suspicious_devices (profile_id, threat_type, details)
  VALUES (auth.uid()::text, p_threat_type, p_details);

  -- Bloqueia o motorista no esquema public
  UPDATE public.profiles
  SET status = 'blocked',
      is_approved = false,
      updated_at = now()
  WHERE id = auth.uid()::text;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_flag_suspicious_device(TEXT, JSONB) TO authenticated;
