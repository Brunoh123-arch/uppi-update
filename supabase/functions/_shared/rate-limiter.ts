/**
 * Rate Limiter in-memory para Supabase Edge Functions.
 * 
 * Protege endpoints contra abuso (ex: spam de create_order).
 * Funciona per-instance (cada cold start reseta o mapa).
 * Para proteção distribuída em alta escala, considere Redis/Upstash.
 * 
 * Uso:
 *   const limiter = new RateLimiter(10, 60_000); // 10 req/min
 *   if (limiter.isRateLimited(userId)) return errorResponse('Too many requests', 429);
 */

interface RateLimitEntry {
  count: number;
  resetAt: number;
}

export class RateLimiter {
  private store = new Map<string, RateLimitEntry>();
  private maxRequests: number;
  private windowMs: number;

  /**
   * @param maxRequests Máximo de requisições permitidas na janela
   * @param windowMs Janela de tempo em milissegundos (ex: 60_000 = 1 minuto)
   */
  constructor(maxRequests: number, windowMs: number) {
    this.maxRequests = maxRequests;
    this.windowMs = windowMs;
  }

  /**
   * Verifica e registra uma requisição para o identificador dado.
   * @returns true se o limite foi excedido (deve bloquear), false se pode prosseguir
   */
  isRateLimited(identifier: string): boolean {
    const now = Date.now();
    const entry = this.store.get(identifier);

    // Limpar entradas expiradas periodicamente (a cada 100 chamadas)
    if (this.store.size > 1000) {
      this.cleanup(now);
    }

    if (!entry || now > entry.resetAt) {
      // Nova janela
      this.store.set(identifier, {
        count: 1,
        resetAt: now + this.windowMs,
      });
      return false;
    }

    entry.count++;
    if (entry.count > this.maxRequests) {
      return true; // Bloqueado
    }

    return false;
  }

  /** Retorna quantas requisições restam na janela atual */
  remaining(identifier: string): number {
    const entry = this.store.get(identifier);
    if (!entry || Date.now() > entry.resetAt) return this.maxRequests;
    return Math.max(0, this.maxRequests - entry.count);
  }

  private cleanup(now: number): void {
    for (const [key, entry] of this.store.entries()) {
      if (now > entry.resetAt) {
        this.store.delete(key);
      }
    }
  }
}

// ── Rate limiters pré-configurados para endpoints críticos ──────────────────

/** Criar corrida: máx 5 por minuto por usuário */
export const orderLimiter = new RateLimiter(5, 60_000);

/** Atualizar localização: máx 120 por minuto (2/seg) por motorista */
export const locationLimiter = new RateLimiter(120, 60_000);

/** Login/Auth: máx 10 por minuto por IP */
export const authLimiter = new RateLimiter(10, 60_000);

/** SOS Alerts: máx 3 por minuto por usuário (para evitar spam emergencial) */
export const sosLimiter = new RateLimiter(3, 60_000);

/** Gorjetas: máx 5 por minuto por usuário (para evitar double charge acidental) */
export const tipLimiter = new RateLimiter(5, 60_000);

/** Cancelamentos: máx 5 por minuto por usuário */
export const cancelLimiter = new RateLimiter(5, 60_000);

/** Admin Actions: máx 30 por minuto por admin */
export const adminLimiter = new RateLimiter(30, 60_000);

/** Endpoints genéricos: máx 30 por minuto por usuário */
export const defaultLimiter = new RateLimiter(30, 60_000);
