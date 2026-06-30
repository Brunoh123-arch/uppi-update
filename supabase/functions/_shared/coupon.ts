/**
 * coupon.ts — Regras PURAS de cupom (validade + valor do desconto).
 *
 * Estas funções são a autoridade de cobrança de cupom no servidor (consumidas
 * por apply-coupon). NÃO confundir com `applyCoupon` de pricing.ts: aquela é a
 * versão simplificada de PREVIEW (retorna a tarifa pós-cupom, sem teto). Aqui
 * calculamos o VALOR do desconto efetivamente aplicado, com teto e trava na
 * tarifa. Mantém-se PURO — sem banco, sem rede.
 */

import { round2 } from "./pricing.ts";

export interface Coupon {
  discount?: number | null;
  discount_percent?: number | null;
  discount_flat?: number | null;
  discount_type?: string | null;
  /** Teto absoluto do desconto, aplicável apenas a cupons percentuais. */
  maximum_discount?: number | null;
  expiration_date?: string | null;
  max_uses?: number | null;
  used_by_riders?: string[] | null;
}

/** `true` se o cupom tem data de expiração já passada em relação a `now`. */
export function isCouponExpired(coupon: Coupon, now: Date): boolean {
  if (!coupon.expiration_date) return false;
  return new Date(coupon.expiration_date) < now;
}

/** `true` se o cupom já atingiu o limite global de usos. */
export function hasReachedMaxUses(coupon: Coupon): boolean {
  if (!coupon.max_uses) return false;
  return (coupon.used_by_riders ?? []).length >= coupon.max_uses;
}

/** `true` se este passageiro já usou o cupom (uso único por passageiro). */
export function wasUsedByRider(coupon: Coupon, riderId: string): boolean {
  return (coupon.used_by_riders ?? []).includes(riderId);
}

/**
 * Calcula o VALOR do desconto a ser aplicado sobre `fare`.
 *
 * Regras (preservadas de apply-coupon/index.ts):
 * - percentual: `fare · valor/100`, limitado por `maximum_discount` quando definido;
 * - fixo: o valor absoluto;
 * - nunca maior que a própria tarifa;
 * - arredondado para 2 casas.
 */
export function computeCouponDiscount(fare: number, coupon: Coupon): number {
  const value = Number(
    coupon.discount ?? coupon.discount_percent ?? coupon.discount_flat ?? 0,
  );
  const type = coupon.discount_type ||
    (Number(coupon.discount_percent ?? 0) > 0 ? "percentage" : "flat");

  let discount = 0;
  if (type === "percentage" || type === "percent") {
    discount = fare * (value / 100);
    if (coupon.maximum_discount && discount > Number(coupon.maximum_discount)) {
      discount = Number(coupon.maximum_discount);
    }
  } else {
    discount = value;
  }

  discount = Math.min(discount, fare);
  return round2(discount);
}
