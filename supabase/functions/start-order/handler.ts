/**
 * START-ORDER Handler — Motorista inicia a corrida
 * Migrado de: index.ts
 */

import { getServiceClient, getSupabaseUser, cleanFcmToken } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm-client.ts';

export async function handleStartOrder(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return optionsResponse(req);

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401, req);
    const uid = user.id;

    const body = await req.json();
    const { orderId, ride_id, boardingPin } = body.args ?? body;
    const rideId = orderId || ride_id;

    if (!rideId) return errorResponse('orderId é obrigatório', 400, req);

    const supa = getServiceClient();

    // 1. Verificar corrida
    const { data: ride } = await supa
      .from('rides')
      .select('*')
      .eq('id', rideId)
      .eq('driver_id', uid)
      .single();

    if (!ride) return errorResponse('Corrida não encontrada ou não pertence a você', 403, req);

    // 🔐 VALIDAR PIN DE EMBARQUE: Previne passageiro errado no carro
    // Se a corrida possui um PIN de embarque cadastrado, a sua validação é obrigatória.
    if (ride.boarding_pin) {
      if (boardingPin == null || ride.boarding_pin !== String(boardingPin).trim()) {
        return errorResponse(
          'PIN de embarque incorreto ou ausente. Solicite o código de 4 dígitos ao passageiro e tente novamente.',
          400,
          req
        );
      }
    }

    if (ride.status !== 'arrived') {
      return errorResponse('A corrida deve estar com o status arrived para ser iniciada', 400, req);
    }

    // 2. Atualizar para "em andamento"
    const { error: updateErr } = await supa
      .from('rides')
      .update({
        status: 'in_progress',
        started_at: new Date().toISOString(),
        boarding_pin: null, // Limpar PIN após validar — não pode ser reutilizado
      })
      .eq('id', rideId);

    if (updateErr) return errorResponse(updateErr.message, 500, req);

    // 3. Notificar passageiro
    const { data: riderProfile } = await supa
      .from('profiles')
      .select('fcm_token')
      .eq('id', ride.rider_id)
      .single();

    if (riderProfile?.fcm_token) {
      const pushResult = await sendPush({
        token: riderProfile.fcm_token,
        title: 'Corrida iniciada! 🚀',
        body: 'Sua corrida começou. Aproveite o trajeto!',
        data: { ride_id: rideId, type: 'ride_started' },
        channelId: 'tripEvents',
      });
      if (pushResult.invalidToken) {
        await cleanFcmToken(ride.rider_id, riderProfile.fcm_token);
      }
    }

    // 4. Registrar atividade
    await supa.from('ride_activities').insert({
      ride_id: rideId,
      type: 'started',
      actor_id: uid,
    });

    return jsonResponse({ success: true, status: 'started' }, 200, req);

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('start-order error:', msg);
    return errorResponse(msg, 500, req);
  }
}
