/**
 * REOPEN-RIDE-CHAT — Reabrir chat temporário pós-corrida (24h)
 * Para casos de objetos esquecidos: permite que o passageiro abra um canal 
 * de comunicação mascarado com o motorista, válido por 24 horas.
 * 
 * Não há investigação ou julgamento de culpa — apenas facilitação de contato
 * para combinação direta de "Taxa de Deslocamento" (combustível da devolução).
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
    const { ride_id } = args;

    if (!ride_id) return errorResponse('ride_id é obrigatório', 400);

    const supa = getServiceClient();

    // 1. Buscar corrida e validar participação
    const { data: ride, error: rideErr } = await supa
      .from('rides')
      .select('id, rider_id, driver_id, status, updated_at, chat_reopened_at')
      .eq('id', ride_id)
      .single();

    if (rideErr || !ride) {
      return errorResponse('Corrida não encontrada', 404);
    }

    // Validar que o solicitante é participante da corrida
    if (ride.rider_id !== uid && ride.driver_id !== uid) {
      return errorResponse('Você não é participante desta corrida', 403);
    }

    // Validar que a corrida já terminou
    if (!['completed', 'finished'].includes(ride.status)) {
      return errorResponse('Chat pós-corrida só pode ser aberto para corridas finalizadas', 400);
    }

    // Validar janela de 24h após a finalização
    const finishedAt = new Date(ride.updated_at);
    const now = new Date();
    const hoursSinceFinish = (now.getTime() - finishedAt.getTime()) / (1000 * 60 * 60);

    if (hoursSinceFinish > 24) {
      return errorResponse('O prazo de 24 horas para reabertura do chat expirou. Para casos judiciais, procure o suporte da plataforma.', 400);
    }

    // Verificar se já foi reaberto
    if (ride.chat_reopened_at) {
      const reopenedAt = new Date(ride.chat_reopened_at);
      const hoursSinceReopen = (now.getTime() - reopenedAt.getTime()) / (1000 * 60 * 60);

      if (hoursSinceReopen > 24) {
        return errorResponse('O chat temporário já expirou (24h). Para casos judiciais, procure o suporte.', 400);
      }

      // Já está aberto — retornar sucesso
      return jsonResponse({
        success: true,
        ride_id,
        chat_reopened_at: ride.chat_reopened_at,
        expires_at: new Date(reopenedAt.getTime() + 24 * 60 * 60 * 1000).toISOString(),
        already_open: true,
      });
    }

    // 2. Marcar chat como reaberto
    await supa
      .from('rides')
      .update({ chat_reopened_at: now.toISOString() })
      .eq('id', ride_id);

    // 3. Notificar a outra parte
    const otherPartyId = uid === ride.rider_id ? ride.driver_id : ride.rider_id;
    const isRider = uid === ride.rider_id;

    if (otherPartyId) {
      const { data: otherProfile } = await supa
        .from('profiles')
        .select('fcm_token')
        .eq('id', otherPartyId)
        .single();

      if (otherProfile?.fcm_token) {
        const pushResult = await sendPush({
          token: otherProfile.fcm_token,
          title: 'Chat reaberto — Objeto esquecido 📦',
          body: isRider
            ? 'O passageiro quer entrar em contato sobre um possível objeto esquecido. Chat válido por 24h.'
            : 'O motorista quer entrar em contato sobre um possível objeto esquecido. Chat válido por 24h.',
          data: { ride_id, type: 'chat_reopened' },
          channelId: 'tripEvents',
        });

        if (pushResult.invalidToken) {
          await cleanFcmToken(otherPartyId, otherProfile.fcm_token);
        }
      }
    }

    const expiresAt = new Date(now.getTime() + 24 * 60 * 60 * 1000).toISOString();

    console.log(`[reopen-ride-chat] Chat reaberto para corrida ${ride_id} por ${uid}. Expira em: ${expiresAt}`);

    return jsonResponse({
      success: true,
      ride_id,
      chat_reopened_at: now.toISOString(),
      expires_at: expiresAt,
      already_open: false,
      disclaimer: 'A Uppi não se responsabiliza por objetos esquecidos conforme Termos de Uso. Este canal é para contato direto entre as partes para combinação de devolução.',
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('reopen-ride-chat error:', msg);
    return errorResponse(msg);
  }
});
