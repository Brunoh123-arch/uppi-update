/**
 * UPDATE-FCM-TOKEN — Atualizar token FCM do dispositivo
 * Migrado de: functions/src/notifications/notification.functions.ts
 * 
 * 🛡️ SESSION KICK: Ao trocar de dispositivo, envia push de logout
 *    forçado para o dispositivo anterior via o token FCM antigo.
 */

import { getServiceClient, getSupabaseUser, cleanFcmToken } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm-client.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);
    const uid = user.id;

    const body = await req.json();
    const args = body.args ?? body;

    const hasTokenKey = ('token' in args) || ('fcmToken' in args);
    if (!hasTokenKey) {
      return errorResponse('token é obrigatório', 400);
    }

    const fcm = args.token !== undefined ? args.token : args.fcmToken;

    const supa = getServiceClient();

    // ── 🛡️ SESSION KICK: Buscar token anterior para invalidar sessão ──
    const { data: currentProfile } = await supa
      .from('profiles')
      .select('fcm_token')
      .eq('id', uid)
      .single();

    const oldToken = currentProfile?.fcm_token;

    // Se existe um token anterior E é diferente do novo → outro dispositivo
    if (oldToken && oldToken !== fcm) {
      try {
        const pushResult = await sendPush({
          token: oldToken,
          title: 'Sessão encerrada',
          body: 'Sua conta foi acessada em outro dispositivo. Este dispositivo foi desconectado.',
          data: { type: 'session_kick' },
          channelId: 'high_importance_channel',
        });

        if (pushResult.invalidToken) {
          // Token antigo já era inválido — limpar silenciosamente
          await cleanFcmToken(uid, oldToken);
        }

        console.log(`[update-fcm-token] Session kick enviado para dispositivo anterior do usuário ${uid}`);
      } catch (kickErr) {
        // Não bloquear o fluxo principal por falha no kick
        console.warn(`[update-fcm-token] Falha ao enviar session_kick: ${kickErr}`);
      }
    }

    // ── Salvar novo token ──
    await supa
      .from('profiles')
      .update({ fcm_token: fcm })
      .eq('id', uid);

    return jsonResponse({ success: true });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('update-fcm-token error:', msg);
    return errorResponse(msg);
  }
});
