/**
 * Mercado Pago API Helper — Compartilhado entre Edge Functions de pagamento
 */

/** Busca config do Mercado Pago do banco (app_settings key-value) */
export async function getMercadoPagoConfig(
  supa: ReturnType<typeof import('./supabase-client.ts').getServiceClient>,
): Promise<{ accessToken: string; publicKey: string; webhookSecret?: string }> {
  // Ler chaves do Mercado Pago da tabela key-value app_settings
  const { data: rows } = await supa
    .from('app_settings')
    .select('key, value')
    .in('key', ['mp_access_token', 'mp_public_key', 'mp_webhook_secret']);

  const settings: Record<string, string> = {};
  rows?.forEach((row: any) => {
    settings[row.key] = row.value;
  });

  // 1. Priorizar estritamente variáveis de ambiente protegidas (padrão de segurança recomendado)
  let accessToken = Deno.env.get('MERCADOPAGO_ACCESS_TOKEN') || '';
  let publicKey = Deno.env.get('MERCADOPAGO_PUBLIC_KEY') || '';
  let webhookSecret = Deno.env.get('MERCADOPAGO_WEBHOOK_SECRET') || '';

  // 2. Se não encontradas nas envs, buscar fallback no banco de dados e alertar sobre risco de segurança
  if (!accessToken || !publicKey) {
    const dbAccessToken = settings['mp_access_token'];
    const dbPublicKey = settings['mp_public_key'];

    if (dbAccessToken || dbPublicKey) {
      console.warn(
        "⚠️ AVISO DE SEGURANÇA (UPPI BRASIL): Chaves privadas do Mercado Pago carregadas da tabela app_settings no banco de dados. " +
        "Para mitigar riscos de vazamento de dados, migre-as imediatamente para variáveis de ambiente protegidas (MERCADOPAGO_ACCESS_TOKEN e MERCADOPAGO_PUBLIC_KEY)."
      );
      if (!accessToken) accessToken = dbAccessToken || '';
      if (!publicKey) publicKey = dbPublicKey || '';
    }
  }

  if (!webhookSecret) {
    webhookSecret = settings['mp_webhook_secret'] || '';
  }

  if (!accessToken) {
    throw new Error('Configuração do Mercado Pago não encontrada (defina a env MERCADOPAGO_ACCESS_TOKEN ou use o fallback mp_access_token em app_settings)');
  }

  return {
    accessToken,
    publicKey,
    webhookSecret,
  };
}

/** Fetch wrapper para API do Mercado Pago */
export async function mpFetch(
  endpoint: string,
  accessToken: string,
  method: 'GET' | 'POST' | 'PUT' = 'GET',
  // deno-lint-ignore no-explicit-any
  body?: any,
  // deno-lint-ignore no-explicit-any
): Promise<any> {
  const url = `https://api.mercadopago.com${endpoint}`;
  const options: RequestInit = {
    method,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      'X-Idempotency-Key': `${Date.now()}-${Math.random().toString(36).substring(2, 8)}`,
    },
  };
  if (body) options.body = JSON.stringify(body);

  const response = await fetch(url, options);
  const data = await response.json();

  if (!response.ok) {
    console.error('Mercado Pago API error:', data);
    throw new Error(`Mercado Pago erro: ${data.message || JSON.stringify(data)}`);
  }
  return data;
}
