/**
 * Testes das regras de cupom (validade + valor do desconto).
 * Rodar: `deno test supabase/functions/_shared/`
 */

import { assertEquals } from "jsr:@std/assert@1";
import {
  type Coupon,
  computeCouponDiscount,
  hasReachedMaxUses,
  isCouponExpired,
  wasUsedByRider,
} from "./coupon.ts";

// ===== computeCouponDiscount =====

Deno.test("desconto percentual sobre a tarifa", () => {
  assertEquals(
    computeCouponDiscount(50, { discount: 20, discount_type: "percentage" }),
    10,
  );
});

Deno.test("desconto percentual respeita o teto (maximum_discount)", () => {
  // 50% de 50 = 25, mas teto é 10 → 10
  assertEquals(
    computeCouponDiscount(50, {
      discount: 50,
      discount_type: "percentage",
      maximum_discount: 10,
    }),
    10,
  );
});

Deno.test("desconto fixo (flat) usa valor absoluto", () => {
  assertEquals(
    computeCouponDiscount(50, { discount: 15, discount_type: "flat" }),
    15,
  );
});

Deno.test("desconto nunca excede a tarifa", () => {
  assertEquals(
    computeCouponDiscount(50, { discount: 100, discount_type: "flat" }),
    50,
  );
});

Deno.test("desconto é arredondado para 2 casas", () => {
  // 20% de 33.33 = 6.666 → 6.67
  assertEquals(
    computeCouponDiscount(33.33, { discount: 20, discount_type: "percentage" }),
    6.67,
  );
});

Deno.test("cupom legado (discount_percent) é inferido como percentual", () => {
  assertEquals(computeCouponDiscount(50, { discount_percent: 10 }), 5);
});

// ===== isCouponExpired =====

Deno.test("cupom expirado é detectado", () => {
  const now = new Date("2026-06-01T00:00:00Z");
  assertEquals(
    isCouponExpired({ expiration_date: "2026-05-01T00:00:00Z" }, now),
    true,
  );
});

Deno.test("cupom no futuro não está expirado", () => {
  const now = new Date("2026-06-01T00:00:00Z");
  assertEquals(
    isCouponExpired({ expiration_date: "2026-07-01T00:00:00Z" }, now),
    false,
  );
});

Deno.test("cupom sem data de expiração nunca expira", () => {
  assertEquals(isCouponExpired({}, new Date()), false);
});

// ===== hasReachedMaxUses =====

Deno.test("limite de usos atingido é detectado", () => {
  const coupon: Coupon = { max_uses: 2, used_by_riders: ["a", "b"] };
  assertEquals(hasReachedMaxUses(coupon), true);
});

Deno.test("abaixo do limite de usos é permitido", () => {
  const coupon: Coupon = { max_uses: 5, used_by_riders: ["a", "b"] };
  assertEquals(hasReachedMaxUses(coupon), false);
});

Deno.test("sem max_uses não há limite", () => {
  assertEquals(hasReachedMaxUses({ used_by_riders: ["a", "b", "c"] }), false);
});

// ===== wasUsedByRider =====

Deno.test("passageiro que já usou é detectado", () => {
  assertEquals(
    wasUsedByRider({ used_by_riders: ["rider-1", "rider-2"] }, "rider-1"),
    true,
  );
});

Deno.test("passageiro novo não consta como usado", () => {
  assertEquals(
    wasUsedByRider({ used_by_riders: ["rider-1"] }, "rider-2"),
    false,
  );
});

Deno.test("lista de usos ausente trata como nunca usado", () => {
  assertEquals(wasUsedByRider({}, "rider-1"), false);
});
