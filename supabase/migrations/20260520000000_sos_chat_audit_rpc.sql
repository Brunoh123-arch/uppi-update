-- ==============================================================================
-- BLINDAGEM DE SEGURANÇA E PRIVACIDADE — ECOSSISTEMA UPPI
-- Criação de tabela de auditoria e RPC segura para leitura de chat sob SOS
-- ==============================================================================

-- 1. Tabela de logs de auditoria de acessos administrativos
CREATE TABLE IF NOT EXISTS public.admin_chat_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id TEXT NOT NULL,
    ride_id UUID NOT NULL,
    accessed_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    reason TEXT DEFAULT 'Acesso de emergência sob alerta SOS ativo' NOT NULL
);

-- Habilitar RLS na tabela de auditoria
ALTER TABLE public.admin_chat_audit_logs ENABLE ROW LEVEL SECURITY;

-- Apenas admins autenticados podem ver os logs de auditoria
CREATE POLICY admin_audit_logs_select_policy ON public.admin_chat_audit_logs
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid()::text AND role = 'admin'
        )
    );

-- 2. RPC segura para leitura do chat da corrida sob SOS ativo
CREATE OR REPLACE FUNCTION public.rpc_get_sos_chat_context(p_ride_id UUID)
RETURNS TABLE (
    message_id UUID,
    ride_id UUID,
    content TEXT,
    sent_by_driver BOOLEAN,
    created_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_admin BOOLEAN;
    v_has_active_sos BOOLEAN;
BEGIN
    -- A. Verificar se o usuário solicitante é de fato um Administrador
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()::text AND role = 'admin'
    ) INTO v_is_admin;

    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'Acesso negado: Apenas administradores autorizados podem realizar esta operação.';
    END IF;

    -- B. Verificar se a corrida possui algum SOS ativo associado na tabela sos_alerts
    SELECT EXISTS (
        SELECT 1 FROM public.sos_alerts
        WHERE ride_id = p_ride_id AND status = 'active'
    ) INTO v_has_active_sos;

    IF NOT v_has_active_sos THEN
        RAISE EXCEPTION 'Acesso negado: Este chat privado de viagem não possui nenhum alerta SOS ativo associado.';
    END IF;

    -- C. Registrar o log de auditoria permanente do acesso administrativo
    INSERT INTO public.admin_chat_audit_logs (admin_id, ride_id)
    VALUES (auth.uid()::text, p_ride_id);

    -- D. Retornar as mensagens do chat da viagem com segurança
    RETURN QUERY
    SELECT 
        m.id::UUID,
        m.ride_id::UUID,
        m.content::TEXT,
        m.sent_by_driver::BOOLEAN,
        m.created_at::TIMESTAMP WITH TIME ZONE
    FROM public.ride_messages m
    WHERE m.ride_id = p_ride_id
    ORDER BY m.created_at ASC;
END;
$$;

-- Garantir permissões de execução
GRANT EXECUTE ON FUNCTION public.rpc_get_sos_chat_context(UUID) TO authenticated;

COMMENT ON FUNCTION public.rpc_get_sos_chat_context(UUID) IS 'Retorna o histórico de chat de uma viagem específica de forma segura e auditada apenas se houver um alerta SOS ativo.';
