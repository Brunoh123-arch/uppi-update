/**
 * GET-WALLET-HISTORY — Extrato completo da carteira
 * Complementa get-wallet-balance com histórico de transações
 */

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);
    const uid = user.id;

    const body = await req.json().catch(() => ({}));
    const { limit: limitParam, offset: offsetParam, type } = body.args ?? body;

    const maxLimit = Math.min(Number(limitParam) || 20, 50);
    const offset = Number(offsetParam) || 0;

    const supa = getServiceClient();

    // Saldo atual
    const { data: walletData } = await supa
      .from('wallets')
      .select('balance')
      .eq('user_id', uid)
      .single();

    // Histórico de transações
    let query = supa
      .from('wallet_transactions')
      .select('id, amount, type, description, ride_id, status, created_at')
      .eq('user_id', uid)
      .order('created_at', { ascending: false })
      .range(offset, offset + maxLimit - 1);

    if (type) {
      query = query.eq('type', type);
    }

    const { data: transactions } = await query;

    // Resumo por tipo
    const { data: allTxns } = await supa
      .from('wallet_transactions')
      .select('amount, type')
      .eq('user_id', uid)
      .eq('status', 'completed');

    const summary: Record<string, number> = {};
    for (const txn of allTxns || []) {
      summary[txn.type] = (summary[txn.type] || 0) + Number(txn.amount);
    }

    return jsonResponse({
      balance: Number(walletData?.balance) || 0,
      transactions: transactions || [],
      summary,
      limit: maxLimit,
      offset,
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('get-wallet-history error:', msg);
    return errorResponse(msg);
  }
});
