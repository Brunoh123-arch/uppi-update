/**
 * SUBMIT-REVIEW — Enviar avaliação pós-corrida
 * Migrado de: functions/src/orders/order.functions.ts (submitReview)
 */

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);
    const uid = user.id;

    const body = await req.json();
    const { orderId, ride_id, score, review } = body.args ?? body;
    const rideId = orderId || ride_id;

    if (!rideId) return errorResponse('orderId é obrigatório', 400);

    // Se score for nulo, indefinido ou explicitamente pulado, tratamos como skip
    const isSkip = score === undefined || score === null;
    if (!isSkip && (score < 1 || score > 5)) {
      return errorResponse('score deve ser entre 1 e 5', 400);
    }

    const supa = getServiceClient();

    // 1. Buscar corrida
    const { data: ride } = await supa
      .from('rides')
      .select('*')
      .eq('id', rideId)
      .single();

    if (!ride) return errorResponse('Corrida não encontrada', 404);

    // Verificar permissão
    if (ride.rider_id !== uid && ride.driver_id !== uid) {
      return errorResponse('Sem permissão', 403);
    }

    // 🛡️ [Item D10] Apenas permitir avaliações de corridas concluídas ou aguardando avaliação
    if (ride.status !== 'completed' && ride.status !== 'finished' && ride.status !== 'waiting_for_review') {
      return errorResponse('Só é possível avaliar corridas que foram concluídas.', 400);
    }

    const isRider = ride.rider_id === uid;
    const reviewedUserId = isRider ? ride.driver_id : ride.rider_id;

    if (!isSkip) {
      // Verificar se já existe review para a mesma corrida pelo mesmo autor
      const { data: existingReview } = await supa
        .from('reviews')
        .select('id')
        .eq('ride_id', rideId)
        .eq('reviewer_id', uid)
        .maybeSingle();

      if (existingReview) {
        return errorResponse('Você já avaliou esta corrida', 400);
      }

      // 2. Registrar avaliação (Item 14)
      await supa.from('reviews').insert({
        ride_id: rideId,
        reviewer_id: uid,
        reviewed_id: reviewedUserId,
        rating: Number(score),
        score: Number(score),
        comment: review || null,
        reviewer_role: isRider ? 'rider' : 'driver',
      });

      // 3. Atualizar média do avaliado
      const { data: reviews } = await supa
        .from('reviews')
        .select('score')
        .eq('reviewed_id', reviewedUserId);

      // 🛡️ [Item D10] Contar corridas concluídas de forma correta (baseado na tabela de corridas)
      const { count: realRidesCount } = await supa
        .from('rides')
        .select('*', { count: 'exact', head: true })
        .or(`rider_id.eq.${reviewedUserId},driver_id.eq.${reviewedUserId}`)
        .in('status', ['completed', 'finished', 'waiting_for_review']);

      if (reviews && reviews.length > 0) {
        const avg = reviews.reduce((acc, r) => acc + r.score, 0) / reviews.length;
        const roundedAvg = Math.round(avg * 10) / 10;
        await supa
          .from('profiles')
          .update({
            average_rating: roundedAvg,
            rating: roundedAvg,
            review_count: reviews.length,
            total_rides: realRidesCount || 0,
          })
          .eq('id', reviewedUserId);
      }
    }

    // 4. Finalizar corrida se estiver aguardando avaliação (Item 9)
    let shouldFinish = false;
    if (ride.status === 'waiting_for_review') {
      shouldFinish = true;
    }

    if (shouldFinish) {
      await supa
        .from('rides')
        .update({ status: 'finished' })
        .eq('id', rideId);
    }

    // 5. Registrar atividade
    await supa.from('ride_activities').insert({
      ride_id: rideId,
      type: 'reviewed',
      actor_id: uid,
    });

    // 🏆 Gamificação: Disparar verificação de badges para o avaliador e o avaliado (Item C19)
    if (reviewedUserId && !isSkip) {
      triggerCheckBadge(reviewedUserId);
    }
    triggerCheckBadge(uid);

    return jsonResponse({
      success: true,
      status: shouldFinish ? 'finished' : ride.status,
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('submit-review error:', msg);
    return errorResponse(msg);
  }
});

// Helper para disparar a verificação de badges de forma assíncrona
async function triggerCheckBadge(userId: string) {
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceKey) return;

    const functionUrl = `${supabaseUrl}/functions/v1/check-badge`;
    const response = await fetch(functionUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${serviceKey}`
      },
      body: JSON.stringify({ userId })
    });
    if (!response.ok) {
      console.error(`[triggerCheckBadge] Erro ao verificar conquistas do usuário ${userId}:`, await response.text());
    } else {
      console.log(`[triggerCheckBadge] Verificação de conquistas disparada para o usuário ${userId}`);
    }
  } catch (err) {
    console.error(`[triggerCheckBadge] Falha de rede ao disparar conquistas para o usuário ${userId}:`, err);
  }
}

