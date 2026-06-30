/**
 * APPLY-COUPON — Aplicar cupom a uma corrida (consumir uso)
 * Complementa validate-coupon: este realmente marca o cupom como usado
 */

import { getServiceClient, getSupabaseUser, verifyAdmin } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import {
  computeCouponDiscount,
  hasReachedMaxUses,
  isCouponExpired,
  wasUsedByRider,
} from '../_shared/coupon.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);
    const uid = user.id;

    const body = await req.json();
    const { coupon_id, ride_id, orderId, discount } = body.args ?? body;
    const rideId = ride_id || orderId;

    if (!coupon_id || !rideId) {
      return errorResponse('coupon_id e ride_id são obrigatórios', 400);
    }

    const supa = getServiceClient();

    // 1. Buscar cupom
    const { data: coupon } = await supa
      .from('coupons')
      .select('*')
      .eq('id', coupon_id)
      .eq('is_enabled', true)
      .single();

    if (!coupon) return errorResponse('Cupom não encontrado ou inativo', 404);

    // Re-verificar validade do cupom no servidor (regras puras em _shared/coupon.ts)
    const now = new Date();
    if (isCouponExpired(coupon, now)) {
      return errorResponse('Este cupom já expirou', 400);
    }
    if (hasReachedMaxUses(coupon)) {
      return errorResponse('Este cupom atingiu o limite máximo de usos', 400);
    }

    // 2. Buscar dados da corrida e verificar propriedade (C11)
    const { data: ride } = await supa
      .from('rides')
      .select('fare, rider_id')
      .eq('id', rideId)
      .maybeSingle();

    if (!ride) return errorResponse('Corrida não encontrada', 404);

    const isAdmin = await verifyAdmin(req).then(() => true).catch(() => false);
    if (ride.rider_id !== uid && !isAdmin) {
      return errorResponse('Não autorizado a aplicar cupom a esta corrida', 403);
    }

    // 3. Re-verificar que o cupom não foi usado por este passageiro
    if (wasUsedByRider(coupon, uid)) {
      return errorResponse('Cupom já utilizado por você', 400);
    }
    const usedBy: string[] = coupon.used_by_riders || [];

    // 4. Calcular o desconto de forma segura no servidor (regra pura, testável)
    const calculatedDiscount = computeCouponDiscount(Number(ride.fare), coupon);

    // 5. Marcar como usado com Optimistic Lock (evita race condition / duplo-uso simultâneo)
    usedBy.push(uid);
    const prevCount = coupon.used_count || 0;
    
    const { data: updatedCoupon, error: updateErr } = await supa
      .from('coupons')
      .update({
        used_by_riders: usedBy,
        used_count: usedBy.length,
      })
      .eq('id', coupon_id)
      .eq('used_count', prevCount) // Optimistic Lock
      .select()
      .maybeSingle();

    if (updateErr || !updatedCoupon) {
      return errorResponse('Falha ao aplicar cupom. Tente novamente.', 409);
    }

    // 6. Registrar uso na corrida com o valor calculado no servidor
    await supa
      .from('rides')
      .update({
        coupon_id,
        coupon_code: coupon.code,
        coupon_discount: calculatedDiscount,
      })
      .eq('id', rideId);

    // 7. Registrar log de uso
    await supa.from('coupon_usages').insert({
      coupon_id,
      user_id: uid,
      ride_id: rideId,
      discount_amount: calculatedDiscount,
    });

    return jsonResponse({
      success: true,
      coupon_code: coupon.code,
      discount: calculatedDiscount,
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('apply-coupon error:', msg);
    return errorResponse(msg);
  }
});
