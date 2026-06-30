/**
 * VALIDATE-COUPON — Validar e aplicar cupom de desconto
 * Migrado de: functions/src/coupons/coupon.functions.ts
 */

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);
    const uid = user.id;

    const body = await req.json();
    const { code, orderAmount, ride_id, orderId } = body.args ?? body;
    const rideId = ride_id || orderId;

    if (!code) return errorResponse('code é obrigatório', 400);
    if (!rideId) return errorResponse('ride_id é obrigatório para validar cupom', 400);

    const supa = getServiceClient();

    // 🛡️ Segurança: SEMPRE buscar a tarifa real do banco (nunca confiar no orderAmount do cliente)
    const { data: ride } = await supa
      .from('rides')
      .select('fare, rider_id')
      .eq('id', rideId)
      .single();

    if (!ride) return errorResponse('Corrida não encontrada', 404);
    if (ride.rider_id !== uid) return errorResponse('Corrida não pertence a você', 403);

    const amount = Number(ride.fare) || 0;

    // 1. Buscar cupom
    const { data: coupon } = await supa
      .from('coupons')
      .select('*')
      .eq('code', code.toUpperCase())
      .eq('is_enabled', true)
      .maybeSingle();

    if (!coupon) {
      return errorResponse('Cupom não encontrado ou inativo', 404);
    }

    // 2. Verificar validade temporal
    const now = new Date();
    if (coupon.start_date && new Date(coupon.start_date) > now) {
      return errorResponse('Cupom ainda não está ativo', 400);
    }
    if (coupon.expiration_date && new Date(coupon.expiration_date) < now) {
      return errorResponse('Cupom expirado', 400);
    }

    // 3. Verificar se já foi usado por este usuário
    const usedByRiders: string[] = coupon.used_by_riders || [];
    if (usedByRiders.includes(uid)) {
      return errorResponse('Cupom já utilizado', 400);
    }

    // 4. Verificar uso máximo
    if (coupon.max_uses && usedByRiders.length >= coupon.max_uses) {
      return errorResponse('Cupom atingiu o limite de usos', 400);
    }

    // 5. Verificar valor mínimo
    if (coupon.minimum_order_amount && amount < coupon.minimum_order_amount) {
      return errorResponse(`Valor mínimo: R$ ${coupon.minimum_order_amount.toFixed(2)}`, 400);
    }

    // 6. Calcular desconto
    let discount = 0;
    if (coupon.discount_percent && coupon.discount_percent > 0) {
      discount = (amount * coupon.discount_percent) / 100;
      if (coupon.maximum_discount && discount > coupon.maximum_discount) {
        discount = coupon.maximum_discount;
      }
    } else if (coupon.discount_flat && coupon.discount_flat > 0) {
      discount = coupon.discount_flat;
    }

    const finalAmount = Math.max(0, amount - discount);

    return jsonResponse({
      valid: true,
      coupon_id: coupon.id,
      code: coupon.code,
      discount: parseFloat(discount.toFixed(2)),
      final_amount: parseFloat(finalAmount.toFixed(2)),
      discount_type: coupon.discount_percent > 0 ? 'percent' : 'flat',
      discount_value: coupon.discount_percent > 0 ? coupon.discount_percent : coupon.discount_flat,
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('validate-coupon error:', msg);
    return errorResponse(msg);
  }
});
