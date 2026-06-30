import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Unauthorized', 401);

    const body = await req.json();
    const { code } = body;

    if (!code) {
      return errorResponse('O código do gift card é obrigatório', 400);
    }

    const supa = getServiceClient();

    // 1. Atualização atômica para evitar condições de corrida (Race Conditions)
    const now = new Date().toISOString();
    const { data: giftCard, error: updateError } = await supa
      .from('gift_cards')
      .update({
        is_redeemed: true,
        redeemed_by: user.id,
        redeemed_at: now,
      })
      .eq('code', code.toUpperCase())
      .eq('is_redeemed', false)
      .select()
      .maybeSingle();

    if (updateError) throw updateError;
    if (!giftCard) return errorResponse('Gift card inválido, inexistente ou já resgatado', 400);

    // 3. Adicionar saldo à carteira do usuário de forma atômica
    const amount = Number(giftCard.amount);
    
    // Incrementa usando RPC
    await supa.rpc('increment_wallet', { target_user_id: user.id, amount_to_add: amount });

    // 4. Registrar a transação
    await supa.from('wallet_transactions').insert({
      user_id: user.id,
      amount: amount,
      currency: giftCard.currency || 'BRL',
      type: 'gift_card',
      transaction_type: 'topup',
      status: 'completed',
      description: `Resgate de Gift Card: ${code}`,
    });

    return jsonResponse({
      success: true,
      amount: amount,
      currency: giftCard.currency || 'BRL',
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error("redeem-gift-card error:", msg);
    return errorResponse(msg);
  }
});
