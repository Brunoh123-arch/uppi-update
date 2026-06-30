-- ==============================================================================
-- MIGRAÇÃO — CORREÇÃO DOS PAPÉIS E POLÍTICAS DE ACESSO PARA ADMINISTRADORES
-- Data: 2026-06-04
-- Ecossistema Uppi — Engenharia de Banco de Dados
-- ==============================================================================
-- Esta migração aprimora a validação de administradores e operadores nas políticas RLS
-- e funções de auditoria, garantindo que contas criadas apenas na tabela 'admins' (sem 
-- correspondência na view de profiles) consigam operar o painel administrativo sem erros.
-- ==============================================================================

-- 1. ATUALIZAR FUNÇÃO is_admin_or_operator
-- Agora verifica a tabela física profiles_raw (para otimização e evitar recursão)
-- e também verifica se o ID existe na tabela public.admins.
CREATE OR REPLACE FUNCTION public.is_admin_or_operator(user_id text)
RETURNS boolean
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles_raw WHERE id = user_id AND role = ANY (ARRAY['admin'::text, 'operator'::text])
  ) OR EXISTS (
    SELECT 1 FROM public.admins WHERE id = user_id
  );
END;
$$;

COMMENT ON FUNCTION public.is_admin_or_operator(text) IS 
  'Verifica se o ID de usuário pertence a um administrador/operador na tabela profiles_raw ou admins.';

-- 2. ATUALIZAR FUNÇÃO is_driver PARA USAR A TABELA FÍSICA profiles_raw DIRETAMENTE
CREATE OR REPLACE FUNCTION public.is_driver(user_id text)
RETURNS boolean
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles_raw WHERE id = user_id AND role = 'driver'
  );
END;
$$;

COMMENT ON FUNCTION public.is_driver(text) IS 
  'Verifica se o ID de usuário pertence a um motorista diretamente na tabela física profiles_raw.';

-- 3. RECRIAR POLÍTICA DE SELEÇÃO DE LOGS DE AUDITORIA DE CHAT SOS
-- Agora utiliza a função is_admin_or_operator para autenticar admins de ambos os repositórios.
DROP POLICY IF EXISTS admin_audit_logs_select_policy ON public.admin_chat_audit_logs;
CREATE POLICY admin_audit_logs_select_policy ON public.admin_chat_audit_logs
    FOR SELECT
    TO authenticated
    USING (
        public.is_admin_or_operator(auth.uid()::text)
    );

-- 4. RECRIAR A RPC DE LEITURA DO CHAT SOS COM O NOVO CHECK DE SEGURANÇA
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
    -- A. Verificar se o usuário solicitante é de fato um Administrador ou Operador
    v_is_admin := public.is_admin_or_operator(auth.uid()::text);

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

GRANT EXECUTE ON FUNCTION public.rpc_get_sos_chat_context(UUID) TO authenticated;

COMMENT ON FUNCTION public.rpc_get_sos_chat_context(UUID) IS 
  'Retorna o histórico de chat de uma viagem específica de forma segura e auditada para administradores se houver um alerta SOS ativo.';
