/**
 * cpf.ts — Validação matemática de CPF brasileiro (puro, sem I/O).
 *
 * Valida os dois dígitos verificadores via checksum (módulo 11). Usado em
 * fluxos de pagamento (ex.: create-pix-payment) onde um CPF inválido deve
 * ser barrado antes de chegar ao gateway. Mantém-se PURO e testável.
 */

/** Retorna `true` se o CPF (com ou sem máscara) for matematicamente válido. */
export function isValidCpf(cpf: string): boolean {
  const cleanCpf = cpf.replace(/\D/g, "");
  if (cleanCpf.length !== 11) return false;
  // Rejeita sequências de dígitos repetidos (ex.: 111.111.111-11), que passam
  // no checksum mas nunca são CPFs reais.
  if (/^(\d)\1{10}$/.test(cleanCpf)) return false;

  let sum = 0;
  let remainder: number;

  for (let i = 1; i <= 9; i++) {
    sum += parseInt(cleanCpf.substring(i - 1, i)) * (11 - i);
  }
  remainder = (sum * 10) % 11;
  if (remainder === 10 || remainder === 11) remainder = 0;
  if (remainder !== parseInt(cleanCpf.substring(9, 10))) return false;

  sum = 0;
  for (let i = 1; i <= 10; i++) {
    sum += parseInt(cleanCpf.substring(i - 1, i)) * (12 - i);
  }
  remainder = (sum * 10) % 11;
  if (remainder === 10 || remainder === 11) remainder = 0;
  if (remainder !== parseInt(cleanCpf.substring(10, 11))) return false;

  return true;
}
