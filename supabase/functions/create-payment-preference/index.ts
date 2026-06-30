/**
 * CREATE-PAYMENT-PREFERENCE — Criar preferência Checkout Pro (Mercado Pago)
 * Migrado de: functions/src/payments/payment.functions.ts (createPaymentPreference)
 */

import { getServiceClient, getSupabaseUser, verifyAdmin } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { getMercadoPagoConfig, mpFetch } from '../_shared/mercadopago.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);
    const uid = user.id;

    const body = await req.json();
    const { orderId, ride_id, currency, description } = body.args ?? body;
    const rideId = orderId || ride_id;

    if (!rideId) {
      return errorResponse('orderId é obrigatório', 400);
    }

    const supa = getServiceClient();

    // 🛡️ UPPI SEGURANÇA: Buscar a tarifa (fare) real no banco de dados para evitar fraudes de preço (Crítico 3)
    const { data: ride, error: rideError } = await supa
      .from('rides')
      .select('fare, rider_id')
      .eq('id', rideId)
      .single();

    if (rideError || !ride) {
      return errorResponse('Corrida não encontrada ou erro ao carregar tarifa', 404);
    }

    const fareAmount = Number(ride.fare);
    if (!fareAmount || fareAmount <= 0) {
      return errorResponse('Tarifa da corrida inválida ou zerada', 400);
    }

    // 🛡️ Segurança: apenas o passageiro da corrida ou admin pode criar preferência (BOLA)
    const isAdmin = await verifyAdmin(req).then(() => true).catch(() => false);
    if (ride.rider_id !== uid && !isAdmin) {
      return errorResponse('Acesso negado - você não é o passageiro desta corrida', 403);
    }

    // Verificar se o gateway Mercado Pago está ativo
    const { data: gateway } = await supa
      .from('payment_gateways')
      .select('is_active')
      .eq('name', 'Mercado Pago')
      .maybeSingle();

    if (gateway && gateway.is_active === false) {
      return errorResponse('O pagamento via Mercado Pago está desativado pelo administrador.', 400);
    }

    const config = await getMercadoPagoConfig(supa);

    // Buscar dados do rider
    const { data: rider } = await supa
      .from('profiles')
      .select('full_name, email')
      .eq('id', uid)
      .single();

    const nameParts = (rider?.full_name || '').split(' ');
    const firstName = nameParts[0] || '';
    const lastName = nameParts.slice(1).join(' ') || '';

    const appUrl = Deno.env.get('APP_URL') || 'https://uppi.app';
    const webhookUrl = Deno.env.get('MP_WEBHOOK_URL') || '';

    // 🛡️ Email do Payer Seguro (Item 29): Priorizar e-mail verificado do profiles
    const email = rider?.email || user.email || '';

    // Montar preferência no Mercado Pago
    const preference = await mpFetch('/checkout/preferences', config.accessToken, 'POST', {
      items: [{
        id: rideId,
        title: description || `Corrida Uppi #${rideId.substring(0, 8)}`,
        description: 'Pagamento de corrida via Uppi',
        category_id: 'transportation',
        quantity: 1,
        currency_id: (currency || 'BRL').toUpperCase(),
        unit_price: fareAmount, // Tarifa real do banco
      }],
      payer: {
        email: email, // Email seguro
        first_name: firstName,
        last_name: lastName,
      },
      payment_methods: {
        excluded_payment_types: [],
        installments: 1,
      },
      back_urls: {
        success: `${appUrl}/payment/success?orderId=${rideId}`,
        failure: `${appUrl}/payment/failure?orderId=${rideId}`,
        pending: `${appUrl}/payment/pending?orderId=${rideId}`,
      },
      auto_return: 'approved',
      external_reference: rideId,
      notification_url: webhookUrl,
      statement_descriptor: 'UPPI CORRIDA',
      metadata: { rider_id: uid, ride_id: rideId },
    });

    // Salvar preferência
    await supa.from('payment_preferences').insert({
      mp_preference_id: preference.id,
      ride_id: rideId,
      rider_id: uid,
      amount: fareAmount, // Tarifa real do banco
      currency: currency || 'BRL',
      init_point: preference.init_point,
      sandbox_init_point: preference.sandbox_init_point,
      status: 'created',
    });

    console.log(`Preferência MP criada: ${preference.id} | Corrida: ${rideId} | R$ ${fareAmount}`);

    return jsonResponse({
      preferenceId: preference.id,
      initPoint: preference.init_point,
      sandboxInitPoint: preference.sandbox_init_point,
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('create-payment-preference error:', msg);
    return errorResponse(msg);
  }
});
