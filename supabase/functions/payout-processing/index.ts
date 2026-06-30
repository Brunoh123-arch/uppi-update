import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);
    const uid = user.id;

    const body = await req.json().catch(() => ({}));
    const { amount, payout_account_id, pix_key, bank_name } = body.args ?? body;

    if (!amount || Number(amount) <= 0) {
      return errorResponse('Valor inválido para saque', 400);
    }

    const supa = getServiceClient();

    // 1. Verificar se o usuário é motorista
    const { data: profile, error: profileError } = await supa
      .from('profiles')
      .select('role, full_name')
      .eq('id', uid)
      .single();

    if (profileError || !profile || profile.role !== 'driver') {
      return errorResponse('Apenas motoristas podem solicitar saques', 403);
    }

    let targetAccountId = payout_account_id;

    // 2. Se payout_account_id não for informado, encontrar ou criar uma conta padrão
    if (!targetAccountId) {
      const { data: defaultAccount } = await supa
        .from('payout_accounts')
        .select('id')
        .eq('driver_id', uid)
        .eq('is_default', true)
        .maybeSingle();

      if (defaultAccount) {
        targetAccountId = defaultAccount.id;
      } else {
        // Obter primeiro método de saque ativo
        const { data: payoutMethod } = await supa
          .from('payout_methods')
          .select('id')
          .eq('is_active', true)
          .limit(1)
          .maybeSingle();

        // Criar uma nova conta padrão temporária/pix
        const { data: newAccount, error: insertAccError } = await supa
          .from('payout_accounts')
          .insert({
            driver_id: uid,
            payout_method_id: payoutMethod?.id || null,
            account_number: pix_key || 'Chave Pix',
            bank_name: bank_name || 'Carteira Uppi',
            account_holder_name: profile.full_name,
            is_default: true,
          })
          .select('id')
          .single();

        if (insertAccError || !newAccount) {
          return errorResponse('Erro ao criar conta de saque padrão: ' + (insertAccError?.message ?? 'erro desconhecido'), 400);
        }
        targetAccountId = newAccount.id;
      }
    }

    // 3. Inserir a solicitação de saque (a trigger handle_payout_request_insert irá verificar saldo, debitar e criar transação)
    const { data: payout, error: payoutError } = await supa
      .from('payout_requests')
      .insert({
        driver_id: uid,
        payout_account_id: targetAccountId,
        amount: Number(amount),
        status: 'pending',
      })
      .select('id, status, amount')
      .single();

    if (payoutError) {
      return errorResponse('Erro ao processar saque: ' + payoutError.message, 400);
    }

    return jsonResponse({
      success: true,
      payout_id: payout.id,
      amount: payout.amount,
      status: payout.status,
      message: 'Saque solicitado com sucesso. O saldo foi retido na sua carteira.',
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('payout-processing error:', msg);
    return errorResponse(msg);
  }
});
