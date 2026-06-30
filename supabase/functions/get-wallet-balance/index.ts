/**
 * GET-WALLET-BALANCE — Consultar saldo da carteira
 * Migrado de: functions/src/payments/payment.functions.ts (getWalletBalance)
 */

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);
    const uid = user.id;

    const supa = getServiceClient();

    // Buscar saldo do perfil
    const { data: walletData } = await supa
      .from('wallets')
      .select('balance')
      .eq('user_id', uid)
      .single();

    // Buscar histórico recente de transações
    const { data: transactions } = await supa
      .from('wallet_transactions')
      .select('id, amount, type, description, created_at, status, ref_type')
      .eq('user_id', uid)
      .order('created_at', { ascending: false })
      .limit(20);

    return jsonResponse({
      balance: Number(walletData?.balance) || 0,
      currency: 'BRL',
      transactions: transactions || [],
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('get-wallet-balance error:', msg);
    return errorResponse(msg);
  }
});
