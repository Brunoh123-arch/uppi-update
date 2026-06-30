/**
 * SEND-NOTIFICATION — Enviar notificação push para usuário específico
 * Migrado de: functions/src/notifications/notification.functions.ts
 */

import { getServiceClient, getSupabaseUser, verifyAdmin, cleanMultipleFcmTokens } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { sendPush, sendMulticast } from '../_shared/fcm-client.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    // 🛡️ Segurança (Crítico 2): Restringir exclusivamente para Administradores
    try {
      await verifyAdmin(req);
    } catch (e) {
      return errorResponse('Acesso negado — requer privilégios de administrador', 403);
    }

    // 🛡️ Healthcheck (Item 19): Validar se credenciais do FCM estão configuradas
    if (!Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON')) {
      console.error('[send-notification] ERRO: FIREBASE_SERVICE_ACCOUNT_JSON não configurado no Deno');
      return errorResponse('Serviço de notificações FCM temporariamente indisponível (configuração ausente)', 500);
    }

    const body = await req.json();
    const {
      userId, userIds, topic,
      title, message, data, channelId, imageUrl,
    } = body.args ?? body;

    if (!title || !message) {
      return errorResponse('title e message são obrigatórios', 400);
    }

    const supa = getServiceClient();

    // Caso 1: Enviar para um usuário específico
    if (userId) {
      const { data: profile } = await supa
        .from('profiles')
        .select('fcm_token')
        .eq('id', userId)
        .single();

      if (!profile?.fcm_token) {
        return jsonResponse({ success: false, reason: 'Token FCM não encontrado' });
      }

      const ok = await sendPush({
        token: profile.fcm_token,
        title,
        body: message,
        data,
        channelId,
        imageUrl,
      });

      return jsonResponse({ success: ok });
    }

    // Caso 2: Enviar para múltiplos usuários
    if (userIds && Array.isArray(userIds)) {
      const { data: profiles } = await supa
        .from('profiles')
        .select('fcm_token')
        .in('id', userIds)
        .not('fcm_token', 'is', null);

      const tokens = (profiles || []).map((p) => p.fcm_token!).filter(Boolean);

      if (tokens.length === 0) {
        return jsonResponse({ success: false, reason: 'Nenhum token FCM encontrado' });
      }

      const result = await sendMulticast(tokens, title, message, data, channelId, imageUrl);
      if (result.invalidTokens && result.invalidTokens.length > 0) {
        await cleanMultipleFcmTokens(result.invalidTokens);
      }
      return jsonResponse({ success: true, ...result });
    }

    // Caso 3: Enviar para todos os motoristas online (broadcast)
    if (topic === 'all_drivers') {
      const { data: drivers } = await supa
        .from('driver_locations')
        .select('driver_id')
        .eq('status', 'online');

      if (!drivers || drivers.length === 0) {
        return jsonResponse({ success: false, reason: 'Nenhum motorista online' });
      }

      const driverIds = drivers.map((d) => d.driver_id);
      const { data: profiles } = await supa
        .from('profiles')
        .select('fcm_token')
        .in('id', driverIds)
        .not('fcm_token', 'is', null);

      const tokens = (profiles || []).map((p) => p.fcm_token!).filter(Boolean);

      if (tokens.length === 0) {
        return jsonResponse({ success: false, reason: 'Nenhum token FCM' });
      }

      const result = await sendMulticast(tokens, title, message, data, channelId, imageUrl);
      if (result.invalidTokens && result.invalidTokens.length > 0) {
        await cleanMultipleFcmTokens(result.invalidTokens);
      }
      return jsonResponse({ success: true, ...result });
    }

    return errorResponse('Especifique userId, userIds[], ou topic', 400);

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('send-notification error:', msg);
    return errorResponse(msg);
  }
});
