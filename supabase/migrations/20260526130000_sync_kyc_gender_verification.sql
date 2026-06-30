-- =====================================================
-- MIGRAÇÃO: Pilar 21 (Uppi Mulher - Sincronização do Gênero Verificado no KYC)
-- Data: 2026-05-26
-- =====================================================

CREATE OR REPLACE FUNCTION public.sync_driver_profile_kyc()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.status = 'approved' THEN
        -- Motorista aprovado: status vai para 'offline' (pronto para ficar online)
        -- E o gênero é verificado automaticamente a partir dos documentos do KYC.
        UPDATE public.profiles
        SET is_approved = true,
            gender_verified = true,
            status = 'offline',
            updated_at = now()
        WHERE id = NEW.driver_id;
    ELSIF NEW.status = 'rejected' THEN
        -- Motorista rejeitado: status vai para 'blocked' e remove a verificação
        UPDATE public.profiles
        SET is_approved = false,
            gender_verified = false,
            status = 'blocked',
            updated_at = now()
        WHERE id = NEW.driver_id;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.sync_driver_profile_kyc IS 'Sincroniza automaticamente a tabela de perfis (profiles) com o histórico de KYC do motorista, ativando is_approved e gender_verified.';
