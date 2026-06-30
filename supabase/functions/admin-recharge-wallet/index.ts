/**
 * ADMIN-RECHARGE-WALLET — Recarga de carteira pelo admin
 * Migrado de: functions/src/payments/payment.functions.ts (rechargeWallet)
 */

import { getServiceClient, verifyAdmin } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { adminLimiter } from '../_shared/rate-limiter.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    // 🛡️ Segurança: Validar privilégios de administrador
    let adminUid: string;
    try {
      adminUid = await verifyAdmin(req);
    } catch (err: any) {
      return errorResponse(err.message, 403);
    }

    // 🛡️ Segurança: Rate limiting estrito para admins
    if (adminLimiter.isRateLimited(adminUid)) {
      return errorResponse('Muitas tentativas. Aguarde.', 429);
    }

    const body = await req.json();
    const { userId, amount, currency, description } = body.args ?? body;

    if (!userId || amount === undefined || amount === null) {
      return errorResponse('userId e amount são obrigatórios', 400);
    }

    const numericAmount = Number(amount);
    if (isNaN(numericAmount) || numericAmount === 0) {
      return errorResponse('Valor de recarga inválido', 400);
    }

    // 🛡️ Segurança: Impor limites rígidos de valor (máx R$ 10.000 e mín R$ -10.000)
    if (numericAmount > 10000 || numericAmount < -10000) {
      return errorResponse('O valor de recarga deve estar entre -10.000 e 10.000', 400);
    }

    const supa = getServiceClient();
    const cur = currency || 'BRL';

    // Atualizar saldo
    const { data: walletData, error: walletError } = await supa.rpc('increment_wallet', {
      target_user_id: userId,
      amount_to_add: numericAmount
    });

    if (walletError) {
      console.error('Erro no RPC increment_wallet:', walletError);
      return errorResponse('Erro ao atualizar saldo', 500);
    }
    
    // Buscar saldo atualizado
    const { data: updatedWallet } = await supa
      .from('wallets')
      .select('balance')
      .eq('user_id', userId)
      .single();

    const newBalance = Number(updatedWallet?.balance) || 0;

    // Registrar transação
    await supa.from('wallet_transactions').insert({
      user_id: userId,
      amount: numericAmount,
      type: numericAmount > 0 ? 'recharge' : 'deduction',
      description: description || 'Recarga pelo admin',
      status: 'completed',
    });

    console.log(`Admin wallet recharge: user ${userId} | R$ ${amount} | New balance: R$ ${newBalance}`);

    return jsonResponse({
      success: true,
      newBalance,
      currency: cur,
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('admin-recharge-wallet error:', msg);
    return errorResponse(msg);
  }
});
