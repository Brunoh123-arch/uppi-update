/**
 * CREATE-PIX-PAYMENT — Criar pagamento PIX via Mercado Pago
 * Migrado de: functions/src/payments/payment.functions.ts (createPixPayment)
 */

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { getMercadoPagoConfig, mpFetch } from '../_shared/mercadopago.ts';
import { authLimiter } from '../_shared/rate-limiter.ts';
import { isValidCpf } from '../_shared/cpf.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);
    const uid = user.id;

    // Rate Limiting (F6): Limitar criação de PIX para evitar spam no gateway do Mercado Pago
    if (authLimiter.isRateLimited(uid)) {
      return errorResponse('Muitas requisições de pagamento. Tente novamente em 1 minuto.', 429);
    }

    const body = await req.json();
    const {
      orderId, ride_id,
      payerEmail, payerFirstName, payerLastName, payerCpf,
    } = body.args ?? body;

    const rideId = orderId || ride_id;

    if (!rideId || !payerEmail || !payerCpf) {
      return errorResponse('orderId, payerEmail e payerCpf são obrigatórios', 400);
    }

    // Validação matemática de CPF (F6)
    if (!isValidCpf(payerCpf)) {
      return errorResponse('CPF do pagador é inválido', 400);
    }

    const supa = getServiceClient();

    // 🛡️ UPPI SEGURANÇA: Buscar a tarifa (fare) real e o driver no banco de dados para evitar fraudes de preço
    const { data: ride, error: rideError } = await supa
      .from('rides')
      .select('fare, driver_id')
      .eq('id', rideId)
      .single();

    if (rideError || !ride) {
      return errorResponse('Corrida não encontrada ou erro ao carregar tarifa', 404);
    }

    // Verificar se o gateway Mercado Pago está ativo
    const { data: gateway } = await supa
      .from('payment_gateways')
      .select('is_active')
      .eq('name', 'Mercado Pago')
      .maybeSingle();

    if (gateway && gateway.is_active === false) {
      return errorResponse('O pagamento via Mercado Pago / Pix está desativado pelo administrador.', 400);
    }

    const fareAmount = Number(ride.fare);
    if (!fareAmount || fareAmount <= 0) {
      return errorResponse('Tarifa da corrida inválida ou zerada', 400);
    }

    const config = await getMercadoPagoConfig(supa);

    // Calcular Split (Application Fee) se o motorista estiver atribuído e tiver MP Account vinculado
    let applicationFee: number | undefined = undefined;
    if (ride.driver_id) {
      const { data: driverProfile } = await supa
        .from('profiles')
        .select('mercado_pago_account_id, commission_percentage')
        .eq('id', ride.driver_id)
        .maybeSingle();

      if (driverProfile?.mercado_pago_account_id) {
        let commissionPct = Number(driverProfile.commission_percentage);
        if (isNaN(commissionPct) || commissionPct === 0) {
          const { data: appSettings } = await supa
            .from('app_settings')
            .select('value')
            .eq('key', 'commission_rate')
            .maybeSingle();
          commissionPct = Number(appSettings?.value) || 15;
        }
        
        applicationFee = Number((fareAmount * (commissionPct / 100)).toFixed(2));
      }
    }

    // Criar pagamento PIX no Mercado Pago (suporta split via application_fee se disponível)
    const payment = await mpFetch('/v1/payments', config.accessToken, 'POST', {
      transaction_amount: fareAmount,
      description: `Corrida Uppi #${rideId.substring(0, 8)}`,
      payment_method_id: 'pix',
      payer: {
        email: payerEmail,
        first_name: payerFirstName || '',
        last_name: payerLastName || '',
        identification: {
          type: 'CPF',
          number: payerCpf.replace(/\D/g, ''),
        },
      },
      external_reference: rideId,
      notification_url: Deno.env.get('MP_WEBHOOK_URL') || '',
      metadata: { rider_id: uid, ride_id: rideId },
      ...(applicationFee !== undefined ? { application_fee: applicationFee } : {}),
    });

    // Salvar registro no Supabase
    await supa.from('pix_payments').insert({
      mp_payment_id: payment.id.toString(),
      ride_id: rideId,
      rider_id: uid,
      amount: fareAmount,
      status: payment.status,
      qr_code: payment.point_of_interaction?.transaction_data?.qr_code || '',
      qr_code_base64: payment.point_of_interaction?.transaction_data?.qr_code_base64 || '',
      ticket_url: payment.point_of_interaction?.transaction_data?.ticket_url || '',
      expires_at: payment.date_of_expiration || null,
    });

    console.log(`PIX criado: ${payment.id} | Corrida: ${rideId} | R$ ${fareAmount}`);

    return jsonResponse({
      paymentId: payment.id,
      status: payment.status,
      qrCode: payment.point_of_interaction?.transaction_data?.qr_code || '',
      qrCodeBase64: payment.point_of_interaction?.transaction_data?.qr_code_base64 || '',
      ticketUrl: payment.point_of_interaction?.transaction_data?.ticket_url || '',
      expiresAt: payment.date_of_expiration || null,
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('create-pix-payment error:', msg);
    return errorResponse(msg);
  }
});
