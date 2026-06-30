/**
 * CHAT-SEND-MESSAGE — Enviar mensagem no chat da corrida
 * Migrado de: functions/src/chat/chat.functions.ts (sendMessage)
 * Notifica o outro participante via FCM
 */

import { getServiceClient, getSupabaseUser, cleanFcmToken } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm-client.ts';
import { RateLimiter } from '../_shared/rate-limiter.ts';

const chatLimiter = new RateLimiter(60, 60_000); // 60 req/min por usuário

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);
    const uid = user.id;

    if (chatLimiter.isRateLimited(uid)) {
      return errorResponse('Muitas mensagens enviadas. Aguarde um momento.', 429);
    }

    const body = await req.json();
    const { ride_id, orderId, content, message } = body.args ?? body;
    const rideId = ride_id || orderId;
    const msgContent = content || message;

    if (!rideId || !msgContent) {
      return errorResponse('ride_id e content são obrigatórios', 400);
    }

    // 🛡️ Limite de tamanho de mensagem para evitar abuso/overload
    if (msgContent.length > 1000) {
      return errorResponse('Mensagem muito longa. O limite é 1000 caracteres.', 400);
    }

    const supa = getServiceClient();

    // 1. Verificar corrida e permissão
    const { data: ride } = await supa
      .from('rides')
      .select('status, rider_id, driver_id, chat_reopened_at')
      .eq('id', rideId)
      .single();

    if (!ride) return errorResponse('Corrida não encontrada', 404);

    const isDriver = ride.driver_id === uid;
    const isRider = ride.rider_id === uid;

    if (!isDriver && !isRider) {
      return errorResponse('Sem permissão', 403);
    }

    // 🛡️ PILAR 22: Validar estado do chat pós-corrida
    const rideStatus = ride.status;
    if (['completed', 'finished'].includes(rideStatus)) {
      if (!ride.chat_reopened_at) {
        return errorResponse('O chat desta corrida está fechado. Solicite a reabertura para objetos esquecidos.', 400);
      }
      const reopenedAt = new Date(ride.chat_reopened_at);
      const now = new Date();
      const hoursSinceReopen = (now.getTime() - reopenedAt.getTime()) / (1000 * 60 * 60);
      if (hoursSinceReopen > 24) {
        return errorResponse('O canal temporário de 24 horas para este chat expirou.', 400);
      }
    } else if (['cancelled', 'expired'].includes(rideStatus)) {
      return errorResponse('Não é permitido enviar mensagens em uma corrida cancelada ou expirada.', 400);
    }

    // 2. Salvar mensagem
    const { data: msg, error: insertErr } = await supa
      .from('ride_messages')
      .insert({
        ride_id: rideId,
        sender_id: uid,
        content: msgContent,
        sent_by_driver: isDriver,
      })
      .select('id')
      .single();

    if (insertErr) return errorResponse(insertErr.message, 500);

    // 3. Notificar o outro participante via FCM
    const targetId = isDriver ? ride.rider_id : ride.driver_id;
    if (targetId) {
      const { data: targetProfile } = await supa
        .from('profiles')
        .select('fcm_token, full_name')
        .eq('id', targetId)
        .single();

      if (targetProfile?.fcm_token) {
        // Buscar nome do remetente
        const { data: senderProfile } = await supa
          .from('profiles')
          .select('full_name')
          .eq('id', uid)
          .single();

        const senderName = senderProfile?.full_name || (isDriver ? 'Motorista' : 'Passageiro');

        const pushResult = await sendPush({
          token: targetProfile.fcm_token,
          title: `💬 ${senderName}`,
          body: msgContent.length > 100 ? msgContent.substring(0, 100) + '...' : msgContent,
          data: { type: 'chat_message', ride_id: rideId },
          channelId: 'tripEvents',
        });
        if (pushResult.invalidToken) {
          await cleanFcmToken(targetId, targetProfile.fcm_token);
        }
      }
    }

    return jsonResponse({
      success: true,
      message_id: msg?.id,
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('chat-send-message error:', msg);
    return errorResponse(msg);
  }
});
