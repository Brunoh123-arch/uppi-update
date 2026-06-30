/**
 * CANCEL-ORDER Handler — Cancelar corrida (passageiro ou motorista)
 * Migrado de: index.ts
 */

import { getServiceClient, getSupabaseUser, cleanFcmToken } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm-client.ts';
import { cancelLimiter } from '../_shared/rate-limiter.ts';

export async function handleCancelOrder(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return optionsResponse(req);

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401, req);
    const uid = user.id;

    if (cancelLimiter.isRateLimited(uid)) {
      return errorResponse('Limite de cancelamentos atingido. Tente novamente mais tarde.', 429, req);
    }

    const body = await req.json();
    const { orderId, ride_id, reasonId, reasonNote } = body.args ?? body;
    const rideId = orderId || ride_id;

    if (!rideId) return errorResponse('orderId é obrigatório', 400, req);

    const supa = getServiceClient();

    // 1. Buscar corrida
    const { data: ride } = await supa
      .from('rides')
      .select('*')
      .eq('id', rideId)
      .single();

    if (!ride) return errorResponse('Corrida não encontrada', 404, req);

    // 🛡️ Verificar se a corrida já está em um estado final (concluída, cancelada, etc.)
    const finalStatuses = ['completed', 'finished', 'waiting_for_review', 'rider_canceled', 'driver_canceled', 'canceled', 'expired'];
    if (finalStatuses.includes(ride.status)) {
      return errorResponse(`Esta corrida já está em um estado final (${ride.status}) e não pode ser cancelada.`, 400, req);
    }

    // 2. Verificar permissão
    if (ride.rider_id !== uid && ride.driver_id !== uid) {
      return errorResponse('Sem permissão para cancelar esta corrida', 403, req);
    }

    const isDriver = ride.driver_id === uid;
    const cancelStatus = isDriver ? 'driver_canceled' : 'rider_canceled';

    // 3. Cancelar a corrida com Lock Otimista (eq('status', ride.status)) para prevenir dupla execução (F2)
    const { data: updatedRide, error: updateErr } = await supa
      .from('rides')
      .update({
        status: cancelStatus,
        cancel_reason_id: reasonId || null,
        cancel_reason_note: reasonNote || null,
        canceled_at: new Date().toISOString(),
      })
      .eq('id', rideId)
      .eq('status', ride.status) // Lock otimista!
      .select()
      .maybeSingle();

    if (updateErr || !updatedRide) {
      return errorResponse('Esta corrida já foi cancelada ou modificada por outro processo.', 409, req);
    }

    // 4. Se motorista estava alocado, voltar para online
    if (ride.driver_id) {
      await supa
        .from('driver_locations')
        .update({ status: 'online' })
        .eq('driver_id', ride.driver_id);

      await supa
        .from('profiles')
        .update({ status: 'online' })
        .eq('id', ride.driver_id);
    }

    // 5. Janela de carência de 2 minutos (120 segundos) baseada no accepted_at (F3)
    let bypassFeeDueToGracePeriod = false;
    if (ride.accepted_at) {
      const acceptedAt = new Date(ride.accepted_at).getTime();
      const now = Date.now();
      const elapsedSeconds = (now - acceptedAt) / 1000;
      if (elapsedSeconds <= 120) { // 2 minutos
        bypassFeeDueToGracePeriod = true;
        console.log(`Cancelamento dentro do período de carência (${elapsedSeconds.toFixed(1)}s após aceite). Sem taxa.`);
      }
    }

    // --- REEMBOLSO AUTOMÁTICO PIX SE CONFIRMADO (DIRETRIZ 1) ---
    const isEligibleForRefund = isDriver || bypassFeeDueToGracePeriod;
    if (ride.payment_method === 'pix') {
      const { data: pixPayment } = await supa
        .from('pix_payments')
        .select('amount, status')
        .eq('ride_id', rideId)
        .eq('status', 'approved')
        .maybeSingle();

      const { data: mpPayment } = await supa
        .from('mp_payments')
        .select('amount, status')
        .eq('ride_id', rideId)
        .eq('status', 'approved')
        .maybeSingle();

      if (pixPayment || mpPayment) {
        const pixAmount = Number(pixPayment?.amount || mpPayment?.amount || ride.fare);
        if (isEligibleForRefund && pixAmount > 0) {
          // Creditar o valor de volta na carteira do passageiro (rider_id)
          const { error: refundError } = await supa.rpc('increment_wallet', {
            target_user_id: ride.rider_id,
            amount_to_add: pixAmount
          });

          if (refundError) {
            console.error('Erro ao estornar Pix para a carteira do passageiro:', refundError);
          } else {
            // Registrar transação de refund na tabela wallet_transactions
            const { error: txError } = await supa.from('wallet_transactions').insert({
              user_id: ride.rider_id,
              amount: pixAmount,
              type: 'refund',
              transaction_type: 'refund',
              description: 'Estorno de corrida cancelada (Pix)',
              ride_id: rideId,
              status: 'completed',
            });
            if (txError) {
              console.error('Erro ao registrar transação de estorno Pix:', txError);
            }
            console.log(`Estorno de Pix de R$${pixAmount} creditado com sucesso para o passageiro ${ride.rider_id}`);
          }
        }
      }
    }
    // -------------------------------------------------------------

    // Valor dinâmico da taxa de cancelamento (do app_settings)
    let cancellationFeeCharged = false;
    let CANCEL_FEE = 5.00; // Fallback

    try {
      const { data: feeRow } = await supa
        .from('app_settings')
        .select('value')
        .eq('key', 'cancellation_fee')
        .maybeSingle();
      if (feeRow?.value != null) {
        CANCEL_FEE = Number(feeRow.value);
      }
    } catch (_) {}

    // Cobrar do passageiro e creditar ao motorista se passageiro cancelar após a carência (F2 / F3)
    if (!isDriver && ride.driver_id &&
        ['accepted', 'driver_accepted', 'arrived', 'started', 'in_progress'].includes(ride.status) &&
        !bypassFeeDueToGracePeriod) {

      // Debitar do passageiro
      const { error: debitError } = await supa.rpc('increment_wallet', {
        target_user_id: uid,
        amount_to_add: -CANCEL_FEE
      });

      if (debitError) {
        console.error('Erro ao debitar taxa de cancelamento do passageiro', debitError);
      }

      // Creditar no motorista
      const { error: creditError } = await supa.rpc('increment_wallet', {
        target_user_id: ride.driver_id,
        amount_to_add: CANCEL_FEE
      });

      if (creditError) {
        console.error('Erro ao creditar taxa de cancelamento do motorista', creditError);
      }

      // Registrar transações
      await supa.from('wallet_transactions').insert([
        {
          user_id: uid,
          amount: -CANCEL_FEE,
          type: 'cancellation_fee',
          description: `Taxa de cancelamento - Corrida #${rideId.substring(0, 8)}`,
          ride_id: rideId,
          status: 'completed',
        },
        {
          user_id: ride.driver_id,
          amount: CANCEL_FEE,
          type: 'cancellation_fee',
          description: `Compensação cancelamento - Corrida #${rideId.substring(0, 8)}`,
          ride_id: rideId,
          status: 'completed',
        },
      ]);

      cancellationFeeCharged = true;
      console.log(`Taxa de cancelamento R$${CANCEL_FEE} cobrada do rider ${uid} para o driver ${ride.driver_id}`);
    }

    // Penalizar o motorista e creditar ao passageiro se motorista cancelar após a carência (F4)
    if (isDriver &&
        ['accepted', 'driver_accepted', 'arrived', 'started', 'in_progress'].includes(ride.status) &&
        !bypassFeeDueToGracePeriod) {

      // Debitar do motorista
      const { error: debitError } = await supa.rpc('increment_wallet', {
        target_user_id: uid, // driver
        amount_to_add: -CANCEL_FEE
      });

      if (debitError) {
        console.error('Erro ao debitar taxa de cancelamento do motorista', debitError);
      }

      // Creditar no passageiro
      const { error: creditError } = await supa.rpc('increment_wallet', {
        target_user_id: ride.rider_id,
        amount_to_add: CANCEL_FEE
      });

      if (creditError) {
        console.error('Erro ao creditar taxa de cancelamento do passageiro', creditError);
      }

      // Registrar transações
      await supa.from('wallet_transactions').insert([
        {
          user_id: uid, // driver
          amount: -CANCEL_FEE,
          type: 'cancellation_fee',
          description: `Taxa de conveniência de cancelamento - Corrida #${rideId.substring(0, 8)}`,
          ride_id: rideId,
          status: 'completed',
        },
        {
          user_id: ride.rider_id,
          amount: CANCEL_FEE,
          type: 'cancellation_fee',
          description: `Compensação cancelamento motorista - Corrida #${rideId.substring(0, 8)}`,
          ride_id: rideId,
          status: 'completed',
        },
      ]);

      cancellationFeeCharged = true;
      console.log(`Taxa de conveniência de cancelamento R$${CANCEL_FEE} cobrada do driver ${uid} para o rider ${ride.rider_id}`);
    }

    // 6. Notificar a outra parte + Redespacho automático se motorista cancelou
    const notifyUserId = isDriver ? ride.rider_id : ride.driver_id;
    let willRedispatch = false;

    // 🔄 REDESPACHO AUTOMÁTICO: Se o motorista cancelou, tentar encontrar outro
    if (isDriver && ride.rider_id) {
      // Contar quantos motoristas já cancelaram esta corrida específica
      const { count: driverCancelCount } = await supa
        .from('ride_cancellations')
        .select('id', { count: 'exact' })
        .eq('ride_id', rideId)
        .neq('cancelled_by', ride.rider_id); // Apenas cancelamentos de motoristas

      const MAX_DRIVER_CANCELS = 3;

      if ((driverCancelCount || 0) < MAX_DRIVER_CANCELS) {
        // Ainda vale tentar: reabrir a corrida para redespacho
        const { error: reopenErr } = await supa
          .from('rides')
          .update({
            status: 'requested',
            driver_id: null,
            accepted_at: null,
            eta_pickup: null,
            updated_at: new Date().toISOString(),
          })
          .eq('id', rideId);

        if (!reopenErr) {
          // Disparar redespacho para próximo motorista disponível
          const { data: dispatched } = await supa.rpc('rpc_find_and_offer_ride', { p_ride_id: rideId });
          willRedispatch = dispatched === true;
          console.log(`[cancel-order] Redespacho após cancelamento do motorista: ${ willRedispatch ? 'motorista encontrado' : 'nenhum motorista disponível'}`);
        } else {
          console.error('[cancel-order] Erro ao reabrir corrida para redespacho:', reopenErr);
        }
      } else {
        // Limite de cancelamentos de motoristas atingido — encerrar definitivamente
        await supa.from('rides').update({
          status: 'expired',
          cancel_reason_note: `Corrida encerrada após ${MAX_DRIVER_CANCELS} cancelamentos de motoristas.`,
        }).eq('id', rideId);
        console.log(`[cancel-order] Corrida ${rideId} encerrada definitivamente após ${MAX_DRIVER_CANCELS} cancelamentos.`);
      }
    }

    if (notifyUserId) {
      const { data: notifyProfile } = await supa
        .from('profiles')
        .select('fcm_token')
        .eq('id', notifyUserId)
        .single();

      if (notifyProfile?.fcm_token) {
        // Montar mensagem de push precisa e honesta
        let pushBody: string;
        if (isDriver) {
          pushBody = willRedispatch
            ? 'O motorista cancelou a corrida. Buscando outro motorista para você...' // Só diz isso se o redespacho foi iniciado
            : 'O motorista cancelou a corrida. Não encontramos outro motorista no momento. Tente solicitar novamente.';
        } else {
          pushBody = 'O passageiro cancelou a corrida.';
        }

        const pushResult = await sendPush({
          token: notifyProfile.fcm_token,
          title: 'Corrida cancelada ❌',
          body: pushBody,
          data: { ride_id: rideId, type: 'ride_canceled', will_redispatch: String(willRedispatch) },
          channelId: 'tripEvents',
        });
        if (pushResult.invalidToken) {
          await cleanFcmToken(notifyUserId, notifyProfile.fcm_token);
        }
      }
    }

    // 7. Registrar atividade
    await supa.from('ride_activities').insert({
      ride_id: rideId,
      type: cancelStatus,
      actor_id: uid,
    });

    // 8. Registrar auditoria do cancelamento (Pillar 6)
    await supa.from('ride_cancellations').insert({
      ride_id: rideId,
      cancelled_by: uid,
      reason_id: reasonId || null,
      cancellation_fee: cancellationFeeCharged ? CANCEL_FEE : 0.00,
      driver_compensated_amount: (!isDriver && cancellationFeeCharged) ? CANCEL_FEE : 0.00,
    });

    return jsonResponse({
      success: true,
      status: cancelStatus,
      cancellation_fee_charged: cancellationFeeCharged,
      cancellation_fee: cancellationFeeCharged ? CANCEL_FEE : 0,
    }, 200, req);

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('cancel-order error:', msg);
    return errorResponse(msg, 500, req);
  }
}
