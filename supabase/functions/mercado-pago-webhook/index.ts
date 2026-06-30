/**
 * MERCADO-PAGO-WEBHOOK — IPN Webhook para receber notificações do MP
 * Migrado de: functions/src/payments/payment.functions.ts (mercadoPagoWebhook)
 * NOTA: Este endpoint NÃO requer autenticação Supabase (é chamado pelo MP)
 */

import { getServiceClient, cleanFcmToken } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { getMercadoPagoConfig, mpFetch } from '../_shared/mercadopago.ts';
import { sendPush } from '../_shared/fcm-client.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  // Aceitar apenas POST
  if (req.method !== 'POST') {
    return errorResponse('Método não permitido', 405);
  }

  try {
    const body = await req.json();
    const { type, data, action } = body;

    console.log('Mercado Pago webhook:', { type, action, dataId: data?.id });

    // IPN v2: aceitar events de 'payment' e de disputa/chargeback
    const isPaymentEvent = type === 'payment' && data?.id;
    const isDisputeEvent = ['dispute', 'chargebacks'].includes(type ?? '') && data?.id;

    if (!isPaymentEvent && !isDisputeEvent) {
      return jsonResponse({ received: true, processed: false });
    }

    const supa = getServiceClient();
    const config = await getMercadoPagoConfig(supa);

    // --- 🔐 VALIDAÇÃO DE ASSINATURA HMAC DO MERCADO PAGO ---
    if (config.webhookSecret) {
      const xSignature = req.headers.get('x-signature') || req.headers.get('X-Signature');
      if (!xSignature) {
        console.error('Mercado Pago Webhook error: x-signature header is missing');
        return errorResponse('Signature missing', 401);
      }

      // MP Webhook HMAC validation
      const parts = xSignature.split(',');
      let ts = '';
      let v1 = '';
      for (const part of parts) {
        const [k, v] = part.split('=');
        if (k.trim() === 't') ts = v.trim();
        if (k.trim() === 'v1') v1 = v.trim();
      }

      if (!ts || !v1) {
        return errorResponse('Invalid signature format', 401);
      }

      // A string assinada no Webhook V2 é composta por: "id:${dataId};request-id:${requestId};timestamp:${ts};"
      const requestId = req.headers.get('x-request-id') || '';
      const manifest = `id:${data?.id || ''};request-id:${requestId};timestamp:${ts};`;
      
      const encoder = new TextEncoder();
      const keyBytes = encoder.encode(config.webhookSecret);
      const msgBytes = encoder.encode(manifest);
      
      const cryptoKey = await crypto.subtle.importKey(
        'raw',
        keyBytes,
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['verify', 'sign']
      );
      
      const calculatedBuffer = await crypto.subtle.sign('HMAC', cryptoKey, msgBytes);
      const calculatedArray = Array.from(new Uint8Array(calculatedBuffer));
      const calculatedHash = calculatedArray.map(b => b.toString(16).padStart(2, '0')).join('');
      
      if (calculatedHash !== v1) {
        console.error('Mercado Pago Webhook error: HMAC signature mismatch!', { calculatedHash, receivedHash: v1 });
        return errorResponse('Signature verification failed', 401);
      }
      console.log('Mercado Pago Webhook signature verified successfully! ✅');
    } else {
      console.warn('⚠️ AVISO DE SEGURANÇA (UPPI BRASIL): mp_webhook_secret não configurado no Deno/banco. Assinatura HMAC não validada.');
    }
    // --- 🏁 FIM VALIDAÇÃO DE ASSINATURA ---

    // Consultar pagamento no MP
    const payment = await mpFetch(`/v1/payments/${data.id}`, config.accessToken);

    const rideId = payment.external_reference;
    const riderId = payment.metadata?.rider_id;

    console.log(
      `MP Payment ${data.id}: status=${payment.status} | ride=${rideId} | R$ ${payment.transaction_amount}`,
    );

    // Salvar/atualizar registro
    await supa.from('mp_payments').upsert({
      mp_payment_id: data.id.toString(),
      ride_id: rideId,
      rider_id: riderId,
      status: payment.status,
      status_detail: payment.status_detail,
      amount: payment.transaction_amount,
      currency: payment.currency_id,
      payment_method: payment.payment_method_id,
      payment_type: payment.payment_type_id,
      paid_at: payment.date_approved || null,
      updated_at: new Date().toISOString(),
    }, { onConflict: 'mp_payment_id' });

    // Se aprovado, atualizar corrida e wallet
    if (payment.status === 'approved' && rideId) {
      // Verificar se já foi processado
      const { data: existing } = await supa
        .from('mp_payments')
        .select('processed')
        .eq('mp_payment_id', data.id.toString())
        .single();

      if (!existing?.processed) {
        // Marcar como processado
        await supa
          .from('mp_payments')
          .update({ processed: true })
          .eq('mp_payment_id', data.id.toString());

        // Creditar no wallet do rider
        if (riderId) {
          // Atualiza o saldo de forma atômica através da nova tabela wallets e RPC
          const { data: walletData, error: walletError } = await supa.rpc('increment_wallet', {
            target_user_id: riderId,
            amount_to_add: payment.transaction_amount
          });

          if (walletError) {
            console.error('Erro ao incrementar carteira:', walletError);
          }

          // Registrar transação
          await supa.from('wallet_transactions').insert({
            user_id: riderId,
            amount: payment.transaction_amount,
            type: 'recharge',
            description: `Recarga via ${payment.payment_method_id} - MP #${data.id}`,
            ride_id: rideId,
            status: 'completed',
          });

          // Notificar rider
          const { data: riderProfile } = await supa
            .from('profiles')
            .select('fcm_token')
            .eq('id', riderId)
            .single();

          if (riderProfile?.fcm_token) {
            const pushResult = await sendPush({
              token: riderProfile.fcm_token,
              title: 'Pagamento confirmado! ✅',
              body: `R$ ${payment.transaction_amount.toFixed(2)} adicionados à sua carteira.`,
              data: { type: 'payment_approved', ride_id: rideId },
              channelId: 'wallet',
            });
            if (pushResult.invalidToken) {
              await cleanFcmToken(riderId, riderProfile.fcm_token);
            }
          }

          console.log(`Wallet creditado: rider ${riderId} +R$ ${payment.transaction_amount}`);
        }
      }
    }

    // 🛑 CHARGEBACK / DISPUTA: Se o MP reportar contestação, bloquear passageiro automaticamente
    const isChargedBack = payment.status === 'charged_back' || payment.status === 'in_mediation';
    if ((isDisputeEvent || isChargedBack) && rideId) {
      console.warn(`[MP-WEBHOOK] ⚠️ CHARGEBACK detectado! Payment ${data.id} | Ride ${rideId} | Rider ${riderId}`);

      // Registrar disputa na tabela payment_disputes
      await supa.from('payment_disputes').insert({
        ride_id: rideId || null,
        rider_id: riderId || null,
        mp_payment_id: data.id.toString(),
        dispute_type: isChargedBack ? 'chargeback' : 'in_mediation',
        amount: payment.transaction_amount || 0,
        status: 'open',
        mp_raw_payload: payment,
      });

      // Bloquear carteira do passageiro para evitar novas corridas
      if (riderId) {
        await supa
          .from('wallets')
          .update({
            is_blocked: true,
            block_reason: `Chargeback MP #${data.id} - R$ ${payment.transaction_amount}`,
          })
          .eq('user_id', riderId);

        console.log(`[MP-WEBHOOK] Wallet do rider ${riderId} bloqueada por chargeback.`);
      }

      // Notificar admins sobre o chargeback (busca admin tokens)
      const { data: admins } = await supa
        .from('admins')
        .select('id')
        .limit(3); // Notifica até 3 admins

      for (const admin of admins || []) {
        const { data: adminProfile } = await supa
          .from('profiles')
          .select('fcm_token')
          .eq('id', admin.id)
          .single();

        if (adminProfile?.fcm_token) {
          await sendPush({
            token: adminProfile.fcm_token,
            title: '🚨 Chargeback Detectado!',
            body: `R$ ${payment.transaction_amount?.toFixed(2)} contestado. Ride: ${rideId?.substring(0, 8)}. Rider bloqueado.`,
            data: { type: 'chargeback_alert', ride_id: rideId, rider_id: riderId },
            channelId: 'admin_alerts',
          });
        }
      }

      return jsonResponse({ received: true, processed: true, action: 'chargeback_handled' });
    }

    return jsonResponse({ received: true, processed: true });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('mercado-pago-webhook error:', msg);
    // Sempre retornar 200 para evitar retry do MP
    return jsonResponse({ received: true, error: msg });
  }
});
