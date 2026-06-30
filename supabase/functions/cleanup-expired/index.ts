/**
 * CLEANUP-EXPIRED — Limpar corridas expiradas e dados obsoletos
 * Substitui: Firebase scheduledCleanup (Cloud Scheduler)
 * No Supabase: Chamar via PG Cron ou Edge Function invocado por cron externo
 *
 * Ações:
 * 1. Cancelar corridas "requested" há mais de 10 min
 * 2. Marcar motoristas sem atualização de localização > 30 min como offline
 * 3. Limpar tokens FCM inválidos (opcional)
 */

import { getServiceClient, cleanFcmToken } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm-client.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    // 🛡️ Segurança (Crítico 1): Validar webhook secret
    const webhookSecret = Deno.env.get('WEBHOOK_SECRET');
    const incomingSecret = req.headers.get('x-webhook-secret') || req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '').trim();

    if (!webhookSecret || incomingSecret !== webhookSecret) {
      console.error('[cleanup-expired] Tentativa de acesso não autorizado');
      return errorResponse('Não autorizado', 401);
    }

    const supa = getServiceClient();
    const now = new Date();

    // ── 1. Cancelar corridas pendentes > 20 minutos ───────────────────
    const tenMinAgo = new Date(now.getTime() - 20 * 60 * 1000).toISOString();

    const { data: expiredRides, error: expErr } = await supa
      .from('rides')
      .update({
        status: 'expired',
        cancel_reason_note: 'Tempo esgotado — nenhum motorista aceitou',
      })
      .eq('status', 'requested')
      .or(`and(expected_at.is.null,created_at.lt.${tenMinAgo}),expected_at.lt.${tenMinAgo}`)
      .select('id, rider_id');

    if (expErr) throw expErr;

    // Notificar riders sobre a expiração
    if (expiredRides && expiredRides.length > 0) {
      for (const r of expiredRides) {
        if (!r.rider_id) continue;
        const { data: profile } = await supa
          .from('profiles')
          .select('fcm_token')
          .eq('id', r.rider_id)
          .single();

        if (profile?.fcm_token) {
          const pushResult = await sendPush({
            token: profile.fcm_token,
            title: 'Busca encerrada ⏳',
            body: 'Não encontramos nenhum motorista próximo no momento. Tente solicitar novamente.',
            data: { ride_id: r.id, type: 'ride_expired' },
            channelId: 'tripEvents',
          });
          if (pushResult.invalidToken) {
            await cleanFcmToken(r.rider_id, profile.fcm_token);
          }
        }
      }
    }

    // ── 2. Motoristas inativos > 30 min → offline ─────────────────────
    const thirtyMinAgo = new Date(now.getTime() - 30 * 60 * 1000).toISOString();

    const { count: offlinedDrivers } = await supa
      .from('driver_locations')
      .update({ status: 'offline' })
      .eq('status', 'online')
      .lt('updated_at', thirtyMinAgo)
      .select('driver_id', { count: 'exact' });

    // ── 3. Cancelar corridas aceitas sem ação > 15 min (excluindo se motorista estiver a caminho com ETA futuro)
    const fifteenMinAgo = new Date(now.getTime() - 15 * 60 * 1000).toISOString();
    const nowIso = now.toISOString();

    // Buscar as corridas elegíveis para expiração primeiro para obtermos rider_id e driver_id para notificação
    const { data: staleRides } = await supa
      .from('rides')
      .select('id, rider_id, driver_id')
      .eq('status', 'accepted') // Status corrigido de driver_accepted para accepted (Item 10)
      .lt('updated_at', fifteenMinAgo)
      // Janela de carência dinâmica (Item 10): não expirar se eta_pickup for no futuro (motorista ainda a caminho de área rural, etc.)
      .or(`eta_pickup.is.null,eta_pickup.lt.${nowIso}`);

    const staleIds = (staleRides || []).map((r) => r.id);
    let staleCount = 0;

    if (staleIds.length > 0) {
      const { count } = await supa
        .from('rides')
        .update({
          status: 'expired',
          cancel_reason_note: 'Tempo esgotado — motorista não iniciou a corrida a tempo',
        })
        .in('id', staleIds)
        .select('id', { count: 'exact' });
      staleCount = count || 0;

      // Notificar passageiro e motorista sobre o cancelamento (Item 11)
      for (const r of staleRides || []) {
        // Voltar motorista inativo para online
        if (r.driver_id) {
          await supa.from('driver_locations').update({ status: 'online' }).eq('driver_id', r.driver_id);
          await supa.from('profiles').update({ status: 'online' }).eq('id', r.driver_id);
        }

        // Enviar Pushes
        const participants = [
          { id: r.rider_id, title: 'Corrida cancelada ⏳', body: 'A corrida foi encerrada por falta de movimentação do motorista.', channel: 'tripEvents' },
          { id: r.driver_id, title: 'Corrida expirada ⏳', body: 'A corrida aceita expirou por limite de tempo excedido para o início.', channel: 'tripEvents' }
        ];

        for (const p of participants) {
          if (!p.id) continue;
          const { data: profile } = await supa.from('profiles').select('fcm_token').eq('id', p.id).single();
          if (profile?.fcm_token) {
            const pushResult = await sendPush({
              token: profile.fcm_token,
              title: p.title,
              body: p.body,
              data: { ride_id: r.id, type: 'ride_expired' },
              channelId: p.channel,
            });
            if (pushResult.invalidToken) {
              await cleanFcmToken(p.id, profile.fcm_token);
            }
          }
        }
      }
    }

    // ── 4. VIAGEM FANTASMA: Corridas 'in_progress' sem GPS há > 45 min ────────
    // Se o celular do motorista morreu/foi roubado DEPOIS de iniciar a corrida,
    // o status fica 'in_progress' para sempre travando ambos os perfis.
    // Solução: força-encerrar com o fare original e notificar ambas as partes.
    const fortyFiveMinAgo = new Date(now.getTime() - 45 * 60 * 1000).toISOString();

    const { data: ghostRides } = await supa
      .from('rides')
      .select('id, rider_id, driver_id, fare')
      .eq('status', 'in_progress')
      .lt('updated_at', fortyFiveMinAgo);

    let ghostCount = 0;

    for (const ghost of ghostRides || []) {
      try {
        // Tentar encerrar via RPC finish_ride (mantém transação ACID + comissão)
        const { error: rpcErr } = await supa.rpc('finish_ride', {
          p_ride_id: ghost.id,
          p_driver_id: ghost.driver_id,
          p_cash_amount: 0,
        });

        if (rpcErr) {
          // fallback: marcar como 'expired' se a RPC falhar
          console.warn(`[cleanup-expired] finish_ride falhou para viagem fantasma ${ghost.id}: ${rpcErr.message}. Marcando como expired.`);
          await supa
            .from('rides')
            .update({
              status: 'expired',
              cancel_reason_note: 'Corrida encerrada automaticamente — app do motorista inativo por mais de 45 minutos',
            })
            .eq('id', ghost.id);
        } else {
          ghostCount++;
        }

        // Resetar perfil do motorista
        if (ghost.driver_id) {
          await supa.from('driver_locations').update({ status: 'online' }).eq('driver_id', ghost.driver_id);
          await supa.from('profiles').update({ status: 'online' }).eq('id', ghost.driver_id);
        }

        // Notificar passageiro e motorista
        const fareStr = ghost.fare ? `R$ ${Number(ghost.fare).toFixed(2).replace('.', ',')}` : '';
        const ghostParticipants = [
          {
            id: ghost.rider_id,
            title: 'Corrida encerrada automaticamente 🔔',
            body: `Sua corrida foi encerrada pois o motorista ficou offline.${fareStr ? ` Valor cobrado: ${fareStr}` : ''}`,
            channel: 'tripEvents',
          },
          {
            id: ghost.driver_id,
            title: 'Corrida encerrada automaticamente 🔔',
            body: 'Sua corrida em andamento foi encerrada por inatividade prolongada do aplicativo.',
            channel: 'tripEvents',
          },
        ];

        for (const p of ghostParticipants) {
          if (!p.id) continue;
          const { data: gProfile } = await supa.from('profiles').select('fcm_token').eq('id', p.id).single();
          if (gProfile?.fcm_token) {
            const pushResult = await sendPush({
              token: gProfile.fcm_token,
              title: p.title,
              body: p.body,
              data: { ride_id: ghost.id, type: 'ghost_ride_closed' },
              channelId: p.channel,
            });
            if (pushResult.invalidToken) {
              await cleanFcmToken(p.id, gProfile.fcm_token);
            }
          }
        }

        console.log(`[cleanup-expired] Viagem fantasma ${ghost.id} encerrada com sucesso.`);
      } catch (ghostErr) {
        console.error(`[cleanup-expired] Erro ao encerrar viagem fantasma ${ghost.id}:`, ghostErr);
      }
    }

    // ── 5. HEARTBEAT PASSAGEIRO: Corridas 'arrived' sem ação há > 3 min ────────
    // Se o motorista marcou 'arrived' (chegou ao local) mas o passageiro não
    // apareceu nem interagiu em 3 minutos, provavelmente ficou offline ou desistiu.
    // Libera o motorista em vez de deixá-lo preso esperando 15 min.
    const threeMinAgo = new Date(now.getTime() - 3 * 60 * 1000).toISOString();

    const { data: heartbeatRides } = await supa
      .from('rides')
      .select('id, rider_id, driver_id')
      .eq('status', 'arrived')
      .lt('updated_at', threeMinAgo);

    let heartbeatCount = 0;

    for (const hb of heartbeatRides || []) {
      try {
        await supa
          .from('rides')
          .update({
            status: 'expired',
            cancel_reason_note: 'Passageiro não respondeu após chegada do motorista (timeout 3 min)',
          })
          .eq('id', hb.id);

        heartbeatCount++;

        // Resetar motorista para online
        if (hb.driver_id) {
          await supa.from('driver_locations').update({ status: 'online' }).eq('driver_id', hb.driver_id);
          await supa.from('profiles').update({ status: 'online' }).eq('id', hb.driver_id);
        }

        // Notificar ambos
        const hbParticipants = [
          {
            id: hb.rider_id,
            title: 'Corrida cancelada ⏳',
            body: 'O motorista chegou ao local, mas não houve resposta. A corrida foi encerrada automaticamente.',
            channel: 'tripEvents',
          },
          {
            id: hb.driver_id,
            title: 'Passageiro não apareceu 🚫',
            body: 'O passageiro não respondeu após sua chegada. Você já está disponível para novas corridas.',
            channel: 'tripEvents',
          },
        ];

        for (const p of hbParticipants) {
          if (!p.id) continue;
          const { data: hbProfile } = await supa.from('profiles').select('fcm_token').eq('id', p.id).single();
          if (hbProfile?.fcm_token) {
            const pushResult = await sendPush({
              token: hbProfile.fcm_token,
              title: p.title,
              body: p.body,
              data: { ride_id: hb.id, type: 'heartbeat_expired' },
              channelId: p.channel,
            });
            if (pushResult.invalidToken) {
              await cleanFcmToken(p.id, hbProfile.fcm_token);
            }
          }
        }

        console.log(`[cleanup-expired] Heartbeat expirado: corrida ${hb.id} — passageiro não apareceu.`);
      } catch (hbErr) {
        console.error(`[cleanup-expired] Erro ao expirar heartbeat ${hb.id}:`, hbErr);
      }
    }

    const result = {
      success: true,
      timestamp: now.toISOString(),
      expired_rides: expiredRides?.length || 0,
      stale_accepted: staleCount,
      offlined_drivers: offlinedDrivers || 0,
      ghost_rides_closed: ghostCount,
      heartbeat_expired: heartbeatCount,
    };

    console.log('cleanup-expired:', JSON.stringify(result));
    return jsonResponse(result);

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('cleanup-expired error:', msg);
    return errorResponse(msg);
  }
});
