/**
 * Testes do núcleo de precificação.
 *
 * Rodar: `deno test supabase/functions/_shared/`
 *
 * Estes testes são a especificação executável da regra de tarifa. Se um número
 * mudar aqui, é porque a regra de cobrança mudou — e isso deve ser intencional
 * e revisado, nunca um efeito colateral acidental.
 */

import { assertEquals } from "jsr:@std/assert@1";
import { applyCoupon, computeFare, round2, type FareRates } from "./pricing.ts";

/** Tabela padrão usada na maioria dos casos: base R$5, R$2/km, R$0,50/min, mín R$7. */
const RATES: FareRates = {
  baseFare: 5.0,
  perKmRate: 2.0,
  perMinuteRate: 0.5,
  minimumFare: 7.0,
};

Deno.test("round2 arredonda como dinheiro (2 casas)", () => {
  assertEquals(round2(11.666), 11.67);
  assertEquals(round2(11.664), 11.66);
  assertEquals(round2(10), 10);
});

Deno.test("tarifa padrão: base + distância + tempo", () => {
  // 5 + 10km*2 + 20min*0.5 = 5 + 20 + 10 = 35
  const r = computeFare({ distanceKm: 10, durationMinutes: 20, rates: RATES });
  assertEquals(r.fare, 35);
  assertEquals(r.fareAfterCoupon, 35);
  assertEquals(r.fareAfterSubscription, 35);
  assertEquals(r.total_fare, 35);
});

Deno.test("piso mínimo: corrida curta nunca cobra abaixo do mínimo", () => {
  // 5 + 0 + 0 = 5, mas mínimo é 7 → cobra 7
  const r = computeFare({ distanceKm: 0, durationMinutes: 0, rates: RATES });
  assertEquals(r.fare, 7);
});

Deno.test("surge é aplicado ANTES do piso mínimo", () => {
  // base 5 * surge 0.5 = 2.5 < 7 → piso 7
  const r = computeFare({
    distanceKm: 0,
    durationMinutes: 0,
    rates: RATES,
    surgeMultiplier: 0.5,
  });
  assertEquals(r.fare, 7);
});

Deno.test("surge multiplica a tarifa cheia", () => {
  // 35 * 1.5 = 52.5
  const r = computeFare({
    distanceKm: 10,
    durationMinutes: 20,
    rates: RATES,
    surgeMultiplier: 1.5,
  });
  assertEquals(r.fare, 52.5);
});

Deno.test("cupom percentual desconta corretamente", () => {
  // fare 35; cupom 20% → 35 - 7 = 28
  const r = computeFare({
    distanceKm: 10,
    durationMinutes: 20,
    rates: RATES,
    coupon: { discount: 20, discount_type: "percentage" },
  });
  assertEquals(r.fare, 35);
  assertEquals(r.fareAfterCoupon, 28);
});

Deno.test("cupom fixo (flat) desconta valor absoluto", () => {
  // fare 35; cupom flat 15 → 20
  const r = computeFare({
    distanceKm: 10,
    durationMinutes: 20,
    rates: RATES,
    coupon: { discount: 15, discount_type: "flat" },
  });
  assertEquals(r.fareAfterCoupon, 20);
});

Deno.test("cupom nunca deixa a tarifa negativa (trava em 0)", () => {
  // fare 35; cupom flat 100 → 0, não -65
  const r = computeFare({
    distanceKm: 10,
    durationMinutes: 20,
    rates: RATES,
    coupon: { discount: 100, discount_type: "flat" },
  });
  assertEquals(r.fareAfterCoupon, 0);
});

Deno.test("cupom legado (discount_percent sem discount_type) é inferido como %", () => {
  // fare 35; discount_percent 10 → infere percentual → 35 - 3.5 = 31.5
  const r = computeFare({
    distanceKm: 10,
    durationMinutes: 20,
    rates: RATES,
    coupon: { discount_percent: 10 },
  });
  assertEquals(r.fareAfterCoupon, 31.5);
});

Deno.test("assinatura aplica desconto recorrente sobre a tarifa pós-cupom", () => {
  // fare 35; assinatura 10% → 31.5
  const r = computeFare({
    distanceKm: 10,
    durationMinutes: 20,
    rates: RATES,
    subscriptionDiscountPercent: 10,
  });
  assertEquals(r.subscriptionDiscount, 10);
  assertEquals(r.fareAfterSubscription, 31.5);
});

Deno.test("gorjeta entra só no total, não na tarifa", () => {
  // fare 35; gorjeta 5 → total 40, mas fare permanece 35
  const r = computeFare({
    distanceKm: 10,
    durationMinutes: 20,
    rates: RATES,
    tipIncentive: 5,
  });
  assertEquals(r.fare, 35);
  assertEquals(r.tip_incentive, 5);
  assertEquals(r.total_fare, 40);
});

Deno.test("cenário combinado: surge + cupom + assinatura + gorjeta", () => {
  // fare = 35 * 1.5 = 52.5
  // após cupom 20% = 52.5 - 10.5 = 42
  // após assinatura 10% = 42 * 0.9 = 37.8
  // total = 37.8 + 5 = 42.8
  const r = computeFare({
    distanceKm: 10,
    durationMinutes: 20,
    rates: RATES,
    surgeMultiplier: 1.5,
    coupon: { discount: 20, discount_type: "percentage" },
    subscriptionDiscountPercent: 10,
    tipIncentive: 5,
  });
  assertEquals(r.fare, 52.5);
  assertEquals(r.fareAfterCoupon, 42);
  assertEquals(r.fareAfterSubscription, 37.8);
  assertEquals(r.total_fare, 42.8);
});

Deno.test("saída é arredondada para 2 casas decimais", () => {
  // 5 + 3.333km*2 = 5 + 6.666 = 11.666 → 11.67
  const r = computeFare({
    distanceKm: 3.333,
    durationMinutes: 0,
    rates: { baseFare: 5, perKmRate: 2, perMinuteRate: 0.5, minimumFare: 0 },
  });
  assertEquals(r.fare, 11.67);
});

Deno.test("applyCoupon: sem cupom retorna a tarifa intacta", () => {
  assertEquals(applyCoupon(35, null), 35);
  assertEquals(applyCoupon(35, undefined), 35);
});

Deno.test("applyCoupon: campo 'discount_flat' legado é respeitado", () => {
  // sem discount/discount_percent, usa discount_flat como flat
  assertEquals(applyCoupon(35, { discount_flat: 10 }), 25);
});
