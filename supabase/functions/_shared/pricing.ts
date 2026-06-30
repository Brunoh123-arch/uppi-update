/**
 * pricing.ts — Núcleo PURO de cálculo de tarifa.
 *
 * Sem I/O, sem banco, sem rede, sem `Deno.serve`. Toda a matemática de preço
 * vive aqui para ser testável de forma determinística e auditável — é o ponto
 * onde fraude de valor é prevenida (o servidor sempre recalcula).
 *
 * REGRA: este módulo deve permanecer PURO. Não adicione chamadas de banco,
 * fetch, datas (`Date.now()`) ou aleatoriedade. Passe tudo como parâmetro.
 *
 * Extraído de `calculate-fare/index.ts` preservando exatamente a ordem de
 * cálculo e o arredondamento monetário do comportamento original.
 */

export interface FareRates {
  baseFare: number;
  perKmRate: number;
  perMinuteRate: number;
  minimumFare: number;
}

/** Formato flexível de cupom, tolerante a esquemas legados do banco. */
export interface CouponLike {
  discount?: number | null;
  discount_percent?: number | null;
  discount_flat?: number | null;
  discount_type?: string | null;
}

export interface FareInput {
  distanceKm: number;
  durationMinutes: number;
  rates: FareRates;
  /** Multiplicador de tarifa dinâmica (surge). Padrão: 1.0. */
  surgeMultiplier?: number;
  coupon?: CouponLike | null;
  /** Percentual de desconto da assinatura do passageiro (0–100). */
  subscriptionDiscountPercent?: number;
  /** Gorjeta/incentivo — somada apenas ao total final, não à tarifa base. */
  tipIncentive?: number;
}

export interface FareBreakdown {
  fare: number;
  fareAfterCoupon: number;
  subscriptionDiscount: number;
  fareAfterSubscription: number;
  tip_incentive: number;
  total_fare: number;
}

/** Arredonda como dinheiro (idêntico a `parseFloat(x.toFixed(2))`). */
export function round2(value: number): number {
  return parseFloat(value.toFixed(2));
}

/**
 * Aplica um cupom sobre a tarifa. Tolerante a esquema:
 * - `discount_type` 'percentage'|'percent' → desconto percentual;
 * - caso contrário → desconto fixo (flat).
 * Sem `discount_type`, infere percentual quando `discount_percent > 0`.
 * Nunca retorna valor negativo.
 */
export function applyCoupon(fare: number, coupon?: CouponLike | null): number {
  if (!coupon) return fare;

  const discount = Number(
    coupon.discount ?? coupon.discount_percent ?? coupon.discount_flat ?? 0,
  );
  const type = coupon.discount_type ||
    (Number(coupon.discount_percent ?? 0) > 0 ? 'percentage' : 'flat');

  let result = fare;
  if (type === 'percentage' || type === 'percent') {
    result -= fare * (discount / 100);
  } else {
    result -= discount;
  }
  return result < 0 ? 0 : result;
}

/**
 * Calcula a tarifa completa de forma determinística.
 *
 * Ordem (preservada de `calculate-fare/index.ts`):
 *   1. tarifa = (base + km·perKm + min·perMin) · surge
 *   2. piso: nunca abaixo de `minimumFare`
 *   3. cupom (pode levar abaixo do piso, inclusive a 0)
 *   4. desconto de assinatura
 *   5. total = tarifa_pós_assinatura + gorjeta
 *
 * Os valores intermediários NÃO são arredondados; apenas os campos de saída
 * são arredondados para 2 casas — exatamente como o handler original.
 */
export function computeFare(input: FareInput): FareBreakdown {
  const {
    distanceKm,
    durationMinutes,
    rates,
    surgeMultiplier = 1.0,
    coupon = null,
    subscriptionDiscountPercent = 0,
    tipIncentive = 0,
  } = input;
  const { baseFare, perKmRate, perMinuteRate, minimumFare } = rates;

  let fare =
    (baseFare + distanceKm * perKmRate + durationMinutes * perMinuteRate) *
    surgeMultiplier;
  if (fare < minimumFare) fare = minimumFare;

  const fareAfterCoupon = applyCoupon(fare, coupon);

  const subscriptionDiscount = Number(subscriptionDiscountPercent ?? 0);
  let fareAfterSubscription = fareAfterCoupon;
  if (subscriptionDiscount > 0) {
    fareAfterSubscription = fareAfterCoupon * (1 - subscriptionDiscount / 100);
    if (fareAfterSubscription < 0) fareAfterSubscription = 0;
  }

  const tip = Number(tipIncentive ?? 0);

  return {
    fare: round2(fare),
    fareAfterCoupon: round2(fareAfterCoupon),
    subscriptionDiscount,
    fareAfterSubscription: round2(fareAfterSubscription),
    tip_incentive: tip,
    total_fare: round2(fareAfterSubscription + tip),
  };
}
