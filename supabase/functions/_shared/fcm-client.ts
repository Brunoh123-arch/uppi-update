/**
 * FCM (Firebase Cloud Messaging) client para Deno/Supabase Edge Functions
 * Usa a API REST do FCM v1 com Google Service Account JWT
 * 
 * HARDENED: Cache de access token, retry com exponential backoff,
 * limpeza de tokens inválidos, e batching otimizado.
 */

// ── Google Auth via Service Account ──────────────────────────────────────────

interface ServiceAccount {
  project_id: string;
  private_key: string;
  client_email: string;
}

/** Cache do access token para evitar re-autenticação desnecessária */
let _cachedToken: string | null = null;
let _tokenExpiry: number = 0;

/** Decodifica a service account do env var FIREBASE_SERVICE_ACCOUNT_JSON */
function getServiceAccount(): ServiceAccount | null {
  try {
    const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
    if (!raw) {
      console.warn('FIREBASE_SERVICE_ACCOUNT_JSON not set. FCM notifications are disabled.');
      return null;
    }
    return JSON.parse(raw);
  } catch (err) {
    console.error('Failed to parse FIREBASE_SERVICE_ACCOUNT_JSON. FCM notifications are disabled. Error:', err);
    return null;
  }
}

/** Cria um JWT assinado para autenticar com a API do Google (FCM) */
async function getAccessToken(): Promise<string | null> {
  // Retorna token cacheado se ainda válido (com 5min de margem)
  const now = Math.floor(Date.now() / 1000);
  if (_cachedToken && _tokenExpiry > now + 300) {
    return _cachedToken;
  }

  const sa = getServiceAccount();
  if (!sa) return null;

  const header = { alg: 'RS256', typ: 'JWT' };
  const payload = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };

  const enc = (obj: unknown) =>
    btoa(JSON.stringify(obj)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

  const unsignedToken = `${enc(header)}.${enc(payload)}`;

  // Import private key
  const pemBody = sa.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\n/g, '');

  const binaryKey = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    'pkcs8',
    binaryKey,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsignedToken),
  );

  const sig64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');

  const jwt = `${unsignedToken}.${sig64}`;

  // Trocar JWT por access token
  const resp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  const data = await resp.json();
  if (!data.access_token) throw new Error(`FCM auth failed: ${JSON.stringify(data)}`);
  
  // Cache o token
  _cachedToken = data.access_token;
  _tokenExpiry = now + 3600;
  
  return data.access_token;
}

// ── FCM Send ─────────────────────────────────────────────────────────────────

export interface FcmMessage {
  token: string;
  title: string;
  body: string;
  data?: Record<string, string>;
  channelId?: string;
  /** URL pública HTTPS da imagem exibida na notificação expandida */
  imageUrl?: string;
}

/** Códigos de erro que indicam token inválido/expirado (deve ser removido do DB) */
const INVALID_TOKEN_ERRORS = [
  'UNREGISTERED',
  'INVALID_ARGUMENT',
  'NOT_FOUND',
];

export interface FcmSendResult {
  success: boolean;
  invalidToken: boolean;
  error?: string;
}

/** Envia uma notificação push via FCM v1 API com retry */
export async function sendPush(msg: FcmMessage, maxRetries = 2): Promise<FcmSendResult> {
  const sa = getServiceAccount();
  if (!sa) {
    console.error(`[FCM ERROR] Cannot send push notification: FIREBASE_SERVICE_ACCOUNT_JSON environment variable is not configured. Title: "${msg.title}", Body: "${msg.body}"`);
    return { success: false, invalidToken: false, error: 'FCM disabled: Service account not set or invalid' };
  }
  
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const accessToken = await getAccessToken();
      if (!accessToken) {
        return { success: false, invalidToken: false, error: 'FCM disabled: Access token generation failed' };
      }

      const resp = await fetch(
        `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: msg.token,
              // Imagem no nível raiz — exibida em Android 12+ e iOS (com NSE instalada)
              notification: {
                title: msg.title,
                body: msg.body,
                ...(msg.imageUrl ? { image: msg.imageUrl } : {}),
              },
              data: msg.data ?? {},
              android: {
                priority: 'HIGH',
                ttl: '86400s', // 24h TTL para garantir entrega
                notification: {
                  channel_id: msg.channelId ?? 'high_importance_channel',
                  icon: 'notification_icon',
                  sound: 'default',
                  default_vibrate_timings: true,
                  visibility: 'PUBLIC',
                  notification_priority: 'PRIORITY_MAX',
                  // Android: imagem exibida ao expandir a notificação
                  ...(msg.imageUrl ? { image: msg.imageUrl } : {}),
                },
              },
              apns: {
                headers: {
                  'apns-priority': '10',
                  'apns-push-type': 'alert',
                },
                payload: {
                  aps: {
                    sound: 'default',
                    'content-available': 1,
                    // mutable-content: 1 é OBRIGATÓRIO para a Notification Service Extension
                    // baixar e anexar a imagem antes de exibir (iOS)
                    'mutable-content': 1,
                  },
                  // Passa a URL para a NSE do iOS buscar e exibir
                  ...(msg.imageUrl ? { fcm_options: { image: msg.imageUrl } } : {}),
                },
                ...(msg.imageUrl ? {
                  fcm_options: { image: msg.imageUrl },
                } : {}),
              },
              webpush: {
                headers: {
                  Urgency: 'high',
                },
                notification: {
                  icon: '/icons/icon-192x192.png',
                  requireInteraction: true,
                  // Web: imagem exibida abaixo do texto da notificação
                  ...(msg.imageUrl ? { image: msg.imageUrl } : {}),
                },
              },
            },
          }),
        },
      );

      if (resp.ok) {
        return { success: true, invalidToken: false };
      }

      const errText = await resp.text();
      
      // Token inválido — marcar para remoção
      const isInvalidToken = INVALID_TOKEN_ERRORS.some(code => errText.includes(code));
      if (isInvalidToken) {
        console.warn(`FCM token inválido (será removido): ${msg.token.substring(0, 20)}...`);
        return { success: false, invalidToken: true, error: errText };
      }

      // 429 ou 500+ → retry com backoff
      if (resp.status === 429 || resp.status >= 500) {
        if (attempt < maxRetries) {
          const delay = Math.pow(2, attempt) * 500; // 500ms, 1s, 2s
          console.warn(`FCM retry ${attempt + 1}/${maxRetries} após ${delay}ms`);
          await new Promise(r => setTimeout(r, delay));
          // Invalida cache do token em caso de erro de auth
          if (resp.status === 401) {
            _cachedToken = null;
            _tokenExpiry = 0;
          }
          continue;
        }
      }

      console.error('FCM send error:', errText);
      return { success: false, invalidToken: false, error: errText };
    } catch (e) {
      if (attempt < maxRetries) {
        const delay = Math.pow(2, attempt) * 500;
        await new Promise(r => setTimeout(r, delay));
        continue;
      }
      console.error('FCM send exception:', e);
      return { success: false, invalidToken: false, error: String(e) };
    }
  }

  return { success: false, invalidToken: false, error: 'max retries exceeded' };
}

/** Envia push para múltiplos tokens com limpeza automática de tokens inválidos */
export async function sendMulticast(
  tokens: string[],
  title: string,
  body: string,
  data?: Record<string, string>,
  channelId?: string,
  imageUrl?: string,
): Promise<{ totalSent: number; totalFailed: number; invalidTokens: string[] }> {
  let totalSent = 0;
  let totalFailed = 0;
  const invalidTokens: string[] = [];

  // Deduplica tokens
  const uniqueTokens = [...new Set(tokens.filter(Boolean))];
  
  if (uniqueTokens.length === 0) {
    return { totalSent: 0, totalFailed: 0, invalidTokens: [] };
  }

  // Processar em lotes de 50 para não sobrecarregar
  for (let i = 0; i < uniqueTokens.length; i += 50) {
    const batch = uniqueTokens.slice(i, i + 50);
    const results = await Promise.allSettled(
      batch.map(async (token) => {
        const result = await sendPush({ token, title, body, data, channelId, imageUrl });
        if (result.success) {
          totalSent++;
        } else {
          totalFailed++;
          if (result.invalidToken) {
            invalidTokens.push(token);
          }
        }
      })
    );
    
    // Log falhas inesperadas (rejections)
    results.forEach((r, idx) => {
      if (r.status === 'rejected') {
        console.error(`Batch item ${i + idx} rejected:`, r.reason);
      }
    });
  }

  return { totalSent, totalFailed, invalidTokens };
}
