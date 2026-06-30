/**
 * SEND-MULTICAST-PUSH — Envia notificação push para múltiplos tokens via FCM v1
 * Requer role admin
 */

import { getServiceClient, verifyAdmin, cleanMultipleFcmTokens } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { sendMulticast } from '../_shared/fcm-client.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    // Verificar se é admin
    await verifyAdmin(req);

    const body = await req.json();
    const { title, body: msgBody, tokens, targetRole, imageUrl } = body.args ?? body;

    // Se tokens não fornecidos, buscar por role
    let targetTokens = tokens;
    if (!targetTokens || !Array.isArray(targetTokens) || targetTokens.length === 0) {
      if (!targetRole) return errorResponse('tokens ou targetRole são obrigatórios', 400);

      const supa = getServiceClient();
      const { data: profiles } = await supa
        .from('profiles')
        .select('fcm_token')
        .eq('role', targetRole)
        .not('fcm_token', 'is', null);

      targetTokens = (profiles || [])
        .map((p: { fcm_token: string | null }) => p.fcm_token)
        .filter(Boolean) as string[];
    }

    if (!title || !msgBody) {
      return errorResponse('title e body são obrigatórios', 400);
    }

    if (targetTokens.length === 0) {
      return jsonResponse({ success: true, sent: 0, failed: 0, total: 0 });
    }

    // Validar imageUrl se fornecida
    if (imageUrl && typeof imageUrl === 'string') {
      if (!imageUrl.startsWith('https://')) {
        return errorResponse('imageUrl deve começar com https://', 400);
      }
    }

    const result = await sendMulticast(targetTokens, title, msgBody, undefined, undefined, imageUrl || undefined);
    if (result.invalidTokens && result.invalidTokens.length > 0) {
      await cleanMultipleFcmTokens(result.invalidTokens);
    }

    return jsonResponse({
      success: true,
      ...result,
      total: targetTokens.length,
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('send-multicast-push error:', msg);
    return errorResponse(msg);
  }
});
