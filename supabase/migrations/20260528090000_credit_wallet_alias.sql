-- =====================================================================
-- MIGRAÇÃO: Funções auxiliares faltando detectadas na auditoria
-- Data: 2026-05-28
-- =====================================================================

-- 1. credit_wallet: alias de increment_wallet com assinatura compatível
--    Usada em: finish-order (cashback), check-badge, e outros
CREATE OR REPLACE FUNCTION public.credit_wallet(
  p_user_id TEXT,
  p_amount NUMERIC
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM public.increment_wallet(p_user_id, p_amount);
END;
$$;

GRANT EXECUTE ON FUNCTION public.credit_wallet(TEXT, NUMERIC) TO service_role;
GRANT EXECUTE ON FUNCTION public.credit_wallet(TEXT, NUMERIC) TO postgres;

COMMENT ON FUNCTION public.credit_wallet IS 
  'Alias seguro de increment_wallet. Usada por finish-order para creditar cashback.';
