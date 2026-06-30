/**
 * CORS helpers compartilhados entre todas as Edge Functions
 */

export function getCorsHeaders(req?: Request) {
  const origin = req?.headers.get('origin');
  
  // Whitelist de origens autorizadas (web app de produção + localhost para desenvolvimento/testes)
  const allowedOrigins = [
    'https://uppibrazil.web.app',
    'https://uppi.app',
    'http://localhost:3000',
    'http://localhost:5000',
    'http://localhost:8080'
  ];

  let corsOrigin = 'https://uppi.app';
  if (origin && (
    allowedOrigins.includes(origin) || 
    origin.startsWith('http://localhost:') || 
    origin.startsWith('http://127.0.0.1:')
  )) {
    corsOrigin = origin;
  }

  return {
    'Access-Control-Allow-Origin': corsOrigin,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  };
}

// Mantido para compatibilidade com importações antigas e segurança extra (sem wildcard *)
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
};

export function jsonResponse(data: unknown, status = 200, req?: Request) {
  const headers = req ? getCorsHeaders(req) : corsHeaders;
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });
}

export function errorResponse(message: string, status = 500, req?: Request) {
  const headers = req ? getCorsHeaders(req) : corsHeaders;
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });
}

export function optionsResponse(req?: Request) {
  const headers = req ? getCorsHeaders(req) : corsHeaders;
  return new Response('ok', { headers });
}
