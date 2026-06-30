/**
 * CREATE-ORDER Handler — Solicita/agenda uma corrida
 * Migrado de: index.ts
 */

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, corsHeaders, optionsResponse } from '../_shared/cors.ts';
import { orderLimiter } from '../_shared/rate-limiter.ts';

/** Calcula distância entre dois pontos em metros (Haversine) */
function haversineDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R    = 6371000.0;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a    = Math.sin(dLat / 2) ** 2 +
               Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
               Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export async function handleCreateOrder(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return optionsResponse(req);

  try {
    // 1. Verifica usuário via Supabase JWT
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Unauthorized', 401, req);

    // 1.1 Rate limiting — máx 5 pedidos de corrida por minuto por usuário
    if (orderLimiter.isRateLimited(user.id)) {
      return errorResponse('Muitas solicitações. Aguarde 1 minuto.', 429, req);
    }

    const uid   = user.id;
    const email = user.email;

    // 2. Parse body
    const body = await req.json();
    const { args } = body;
    const { 
      waypoints, 
      serviceId, 
      couponCode, 
      corporateVoucherCode, 
      paymentMethod, 
      distance_meters, 
      duration_seconds, 
      expected_at, 
      quoted_fare,
      tip_incentive = 0,
      routePolyline
    } = args ?? body;

    if (!waypoints || waypoints.length < 2) {
      return new Response(
        JSON.stringify({ error: 'Invalid waypoints: need at least origin and destination' }),
        { status: 400, headers: { 'Content-Type': 'application/json', ...corsHeaders } }
      );
    }

    // 3. Calcula distância e duração estimada
    let totalDistanceMeters = distance_meters ?? 0;
    let durationSeconds = duration_seconds ?? 0;
    
    if (!totalDistanceMeters) {
      for (let i = 0; i < waypoints.length - 1; i++) {
        totalDistanceMeters += haversineDistance(
          waypoints[i].coordinates.lat,  waypoints[i].coordinates.lng,
          waypoints[i+1].coordinates.lat, waypoints[i+1].coordinates.lng,
        );
      }
    }
    if (!durationSeconds) {
      durationSeconds = Math.round((totalDistanceMeters / 1000 / 30) * 3600);
    }

    const supa = getServiceClient();

    // 🛑 VERIFICAÇÃO DE WALLET BLOQUEADA: Passageiro com chargeback não pode pedir corridas
    const { data: walletCheck } = await supa
      .from('wallets')
      .select('is_blocked, block_reason, balance')
      .eq('user_id', uid)
      .maybeSingle();

    if (walletCheck?.is_blocked) {
      return errorResponse(
        'Sua conta está temporariamente bloqueada. Entre em contato com o suporte.',
        403,
        req
      );
    }

    let baseFare = 5.0, perKmRate = 2.0, perMinuteRate = 0.5, minimumFare = 7.0, surgeMultiplier = 1.0;
    let serviceType: string | null = null;
    try {
      // Surge multiplier global
      const { data: surgeRow } = await supa
        .from('app_settings')
        .select('value')
        .eq('key', 'global_surge_multiplier')
        .maybeSingle();
      if (surgeRow?.value) surgeMultiplier = Number(surgeRow.value);

      if (serviceId) {
        const { data: serviceRow } = await supa
          .from('services')
          .select('base_fare, per_km_fare, per_minute_fare, minimum_fare, name, vehicle_category')
          .eq('id', serviceId)
          .maybeSingle();
        if (serviceRow) {
          baseFare      = Number(serviceRow.base_fare       ?? 5.0);
          perKmRate     = Number(serviceRow.per_km_fare     ?? 2.0);
          perMinuteRate = Number(serviceRow.per_minute_fare ?? 0.5);
          minimumFare   = Number(serviceRow.minimum_fare    ?? 7.0);
          serviceType   = serviceRow.vehicle_category ?? serviceRow.name ?? null;
        }
      }
    } catch (e) {
      console.error("Pricing config error:", e);
    }

    // 5. Calcula tarifa (lógica protegida no servidor)
    const distanceKm      = totalDistanceMeters / 1000;
    const durationMinutes = durationSeconds / 60;
    let calculatedFare    = (baseFare + (distanceKm * perKmRate) + (durationMinutes * perMinuteRate)) * surgeMultiplier;
    if (calculatedFare < minimumFare) calculatedFare = minimumFare;

    const originalFare = parseFloat(calculatedFare.toFixed(2));
    let costAfterCoupon = calculatedFare;
    let appliedCoupon: string | null = null;

    // 🛡️ PROTEÇÃO DE PREÇO DEFASADO: Se o passageiro enviou o preço que viu na tela,
    // comparar com o preço recalculado no servidor. Se a diferença for > 20%, rejeitar.
    if (quoted_fare && Number(quoted_fare) > 0) {
      const quotedValue = Number(quoted_fare);
      const priceDiffPercent = Math.abs((originalFare - quotedValue) / quotedValue) * 100;
      if (priceDiffPercent > 20) {
        return errorResponse(
          `O preço foi atualizado de R$ ${quotedValue.toFixed(2).replace('.', ',')} para ` +
          `R$ ${originalFare.toFixed(2).replace('.', ',')} devido a mudanças na demanda. ` +
          `Por favor, revise e confirme novamente.`,
          409, req
        );
      }
    }

    // 6. B2B Corporate Voucher vs Coupon Processing
    let paymentSubsidyAmount = 0.00;
    let paymentRiderAmount = originalFare;
    let corporateVoucherId: string | null = null;
    let isB2BApplied = false;

    const b2bCodeToTest = corporateVoucherCode || couponCode;

    if (b2bCodeToTest) {
      try {
        const { data: voucher, error: voucherErr } = await supa
          .from('corporate_vouchers')
          .select(`
            id,
            code,
            subsidy_flat,
            max_uses_per_rider,
            is_active,
            corporate_id,
            corporate_accounts (
              id,
              company_name,
              balance,
              is_active
            )
          `)
          .eq('code', b2bCodeToTest.toUpperCase())
          .maybeSingle();

        if (!voucherErr && voucher) {
          const corpAccount = voucher.corporate_accounts;
          const isCorpActive = corpAccount?.is_active ?? false;
          const corpBalance = Number(corpAccount?.balance ?? 0);

          if (voucher.is_active && isCorpActive && corpBalance > 0) {
            const maxUses = Number(voucher.max_uses_per_rider ?? 1);
            
            const { count: usesCount } = await supa
              .from('rides')
              .select('id', { count: 'exact', head: true })
              .eq('rider_id', uid)
              .eq('corporate_voucher_id', voucher.id);

            if ((usesCount ?? 0) < maxUses) {
              corporateVoucherId = voucher.id;
              const subsidyFlat = Number(voucher.subsidy_flat ?? 0);
              
              paymentSubsidyAmount = Math.min(subsidyFlat, calculatedFare);
              paymentSubsidyAmount = parseFloat(paymentSubsidyAmount.toFixed(2));
              
              paymentRiderAmount = calculatedFare - paymentSubsidyAmount;
              paymentRiderAmount = parseFloat(paymentRiderAmount.toFixed(2));
              
              costAfterCoupon = calculatedFare;
              isB2BApplied = true;
              console.log(`B2B corporate voucher applied: ${voucher.code}. Subsidy: ${paymentSubsidyAmount}, Rider pays: ${paymentRiderAmount}`);
            } else {
              console.log(`B2B voucher code: ${b2bCodeToTest} already reached max uses for rider ${uid}`);
            }
          } else {
            console.log(`B2B corporate voucher or account is inactive or has insufficient balance.`);
          }
        }
      } catch (e) {
        console.error("Corporate voucher lookup error:", e);
      }
    }

    // Apply regular coupon ONLY if B2B corporate subsidy was NOT applied
    if (!isB2BApplied && couponCode) {
      try {
        const { data: couponRows } = await supa
          .from('coupons')
          .select('*')
          .eq('code', couponCode.toUpperCase())
          .eq('is_enabled', true)
          .limit(1);
        if (couponRows && couponRows.length > 0) {
          const cData = couponRows[0];
          const now = new Date();

          if (cData.expiration_date && new Date(cData.expiration_date) < now) {
            console.log(`Cupom ${couponCode} expirado`);
          }
          else if (cData.start_date && new Date(cData.start_date) > now) {
            console.log(`Cupom ${couponCode} ainda não ativo`);
          }
          else if (cData.minimum_order_amount && calculatedFare < Number(cData.minimum_order_amount)) {
            console.log(`Cupom ${couponCode}: pedido mínimo R$ ${cData.minimum_order_amount}`);
          }
          else if (cData.max_uses && (cData.used_by_riders || []).length >= cData.max_uses) {
            console.log(`Cupom ${couponCode} atingiu limite de usos`);
          }
          else if ((cData.used_by_riders || []).includes(uid)) {
            console.log(`Cupom ${couponCode} já usado por ${uid}`);
          }
          else {
            const couponValue = Number(cData.discount ?? cData.discount_percent ?? cData.discount_flat ?? 0);
            const discountType = cData.discount_type || (cData.discount_percent > 0 ? 'percentage' : 'flat');

            if (discountType === 'percentage' || discountType === 'percent') {
              let discount = costAfterCoupon * (couponValue / 100);
              if (cData.maximum_discount && discount > Number(cData.maximum_discount)) {
                discount = Number(cData.maximum_discount);
              }
              costAfterCoupon -= discount;
            } else {
              costAfterCoupon -= couponValue;
            }
            if (costAfterCoupon < 0) costAfterCoupon = 0;
            appliedCoupon = couponCode.toUpperCase();
            
            paymentRiderAmount = costAfterCoupon;

            const usedBy = cData.used_by_riders || [];
            usedBy.push(uid);
            const prevCount = cData.used_count || 0;
            const { data: updatedCoupon, error: updateErr } = await supa
              .from('coupons')
              .update({
                used_by_riders: usedBy,
                used_count: usedBy.length,
              })
              .eq('id', cData.id)
              .eq('used_count', prevCount) // Lock otimista! (F7)
              .select()
              .maybeSingle();

            if (updateErr || !updatedCoupon) {
              return errorResponse('Este cupom está sendo utilizado em outra requisição simultânea. Por favor, tente novamente.', 409, req);
            }
          }
        }
      } catch (e) {
        console.error("Coupon lookup error:", e);
      }
    }

    // 7. Parse método de pagamento
    let paymentMethodStr = 'cash';
    if (paymentMethod?.wallet)                                           paymentMethodStr = 'wallet';
    else if (paymentMethod?.paymentGateway || paymentMethod?.savedPaymentMethod) paymentMethodStr = 'credit_card';
    else if (paymentMethod?.pix)                                         paymentMethodStr = 'pix';

    // Verify rider's wallet can cover the residual/rider amount if the payment method is digital (wallet)
    if (paymentMethodStr === 'wallet') {
      const currentBalance = Number(walletCheck?.balance ?? 0);
      const totalToCharge = Number(( (isB2BApplied ? paymentRiderAmount : costAfterCoupon) + Number(tip_incentive)).toFixed(2));
      
      if (currentBalance < totalToCharge) {
        return errorResponse(
          `Saldo insuficiente na carteira digital. Seu saldo é R$ ${currentBalance.toFixed(2).replace('.', ',')} e o valor necessário para esta corrida (com incentivo) é R$ ${totalToCharge.toFixed(2).replace('.', ',')}.`,
          400,
          req
        );
      }
    }

    const pickup  = waypoints[0];
    const dropoff = waypoints[waypoints.length - 1];

    // 8. Garante que o perfil do rider existe no Supabase
    const { data: existingProfile } = await supa
      .from('profiles')
      .select('role')
      .eq('id', uid)
      .maybeSingle();

    await supa.from('profiles').upsert({
      id:         uid,
      role:       existingProfile?.role ?? 'rider',
      full_name:  user.user_metadata?.full_name ?? user.email ?? 'Passageiro',
      email:      email,
      avatar_url: user.user_metadata?.avatar_url,
      status:     'active',
      updated_at: new Date().toISOString(),
    }, { onConflict: 'id', ignoreDuplicates: false });

    if (expected_at) {
      const expectedTime = new Date(expected_at).getTime();
      if (isNaN(expectedTime) || expectedTime < Date.now() - 60000) {
        return errorResponse('O horário de agendamento não pode ser no passado.', 400, req);
      }
    }

    // 🛡️ BUG GRAVE scheduled rides: se expected_at for passado, a corrida é agendada
    const isBooked = expected_at ? true : false;

    // 9. Cria a corrida no banco
    const { data: ride, error: insertError } = await supa
      .from('rides')
      .insert({
        rider_id:         uid,
        status:           isBooked ? 'booked' : 'requested',
        pickup_address:   pickup.address,
        pickup_location:  `POINT(${pickup.coordinates.lng} ${pickup.coordinates.lat})`,
        pickup_lat:       pickup.coordinates.lat,
        pickup_lng:       pickup.coordinates.lng,
        dropoff_address:  dropoff.address,
        dropoff_location: `POINT(${dropoff.coordinates.lng} ${dropoff.coordinates.lat})`,
        dropoff_lat:      dropoff.coordinates.lat,
        dropoff_lng:      dropoff.coordinates.lng,
        fare:             isB2BApplied ? parseFloat(calculatedFare.toFixed(2)) : parseFloat(costAfterCoupon.toFixed(2)),
        original_fare:    originalFare,
        platform_fee:     0.0,
        payment_method:   paymentMethodStr,
        distance_meters:  Math.round(totalDistanceMeters),
        duration_seconds: durationSeconds,
        service_id:       serviceId ?? null,
        service_type:     serviceType,
        coupon_code:      isB2BApplied ? null : appliedCoupon,
        expected_at:      expected_at ? new Date(expected_at).toISOString() : null,
        payment_subsidy_amount: paymentSubsidyAmount,
        payment_rider_amount: isB2BApplied ? paymentRiderAmount : parseFloat(costAfterCoupon.toFixed(2)),
        corporate_voucher_id: corporateVoucherId,
        tip_incentive:    Number(tip_incentive),
        route_polyline:   routePolyline ?? [],
      })
      .select()
      .single();

    if (insertError) throw insertError;

    return jsonResponse(ride, 200, req);

  } catch (error: any) {
    const msg = error?.message || error?.details || (typeof error === 'object' ? JSON.stringify(error) : String(error));
    console.error("create_order error:", msg);
    return errorResponse(msg, 500, req);
  }
}
