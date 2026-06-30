/**
 * Testes do validador de CPF.
 * Rodar: `deno test supabase/functions/_shared/`
 */

import { assertEquals } from "jsr:@std/assert@1";
import { isValidCpf } from "./cpf.ts";

Deno.test("aceita CPFs matematicamente válidos", () => {
  assertEquals(isValidCpf("11144477735"), true);
  assertEquals(isValidCpf("52998224725"), true);
  assertEquals(isValidCpf("12345678909"), true);
});

Deno.test("aceita CPF válido com máscara (pontos e traço)", () => {
  assertEquals(isValidCpf("529.982.247-25"), true);
});

Deno.test("rejeita dígito verificador incorreto", () => {
  assertEquals(isValidCpf("12345678900"), false);
  assertEquals(isValidCpf("52998224726"), false);
});

Deno.test("rejeita sequências de dígitos repetidos", () => {
  assertEquals(isValidCpf("11111111111"), false);
  assertEquals(isValidCpf("00000000000"), false);
});

Deno.test("rejeita tamanho incorreto e vazio", () => {
  assertEquals(isValidCpf("123"), false);
  assertEquals(isValidCpf(""), false);
  assertEquals(isValidCpf("111444777356"), false);
});
