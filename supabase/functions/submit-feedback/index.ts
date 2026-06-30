/**
 * SUBMIT-FEEDBACK — Avaliação detalhada da corrida com parâmetros
 * Migrado de: functions/src/feedback/feedback.functions.ts
 * 
 * Diferente do submit-review (nota simples), este permite:
 * - Parâmetros de avaliação (limpeza, direção, etc.)
 * - Review textual
 * - Cálculo de média ponderada do motorista
 * - Finaliza a corrida automaticamente
 */

import { getServiceClient, getSupabaseUser, verifyAdmin } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);
    const uid = user.id;

    const body = await req.json();
    const { ride_id, orderId, rating, review, parameters, is_complaint, subject } = body.args ?? body;
    const rideId = ride_id || orderId;

    if (!rideId) return errorResponse('ride_id é obrigatório', 400);

    const supa = getServiceClient();

    // 1. Buscar corrida
    const { data: ride } = await supa
      .from('rides')
      .select('rider_id, driver_id, status')
      .eq('id', rideId)
      .single();

    if (!ride) return errorResponse('Corrida não encontrada', 404);

    // 🛡️ Segurança: verificar se o usuário autenticado foi participante da corrida (rider ou driver)
    if (uid !== ride.rider_id && uid !== ride.driver_id) {
      return errorResponse('Você não foi um participante desta corrida', 403);
    }

    if (!ride.driver_id) return errorResponse('Corrida sem motorista', 400);

    const isAdmin = await verifyAdmin(req).then(() => true).catch(() => false);

    if (is_complaint) {
      // 🛡️ Segurança: apenas o passageiro ou o motorista podem fazer reclamação sobre a corrida
      if (uid !== ride.rider_id && uid !== ride.driver_id && !isAdmin) {
        return errorResponse('Você não faz parte desta corrida para registrar uma reclamação', 403);
      }
      await supa.from('complaints').insert({
        ride_id: rideId,
        user_id: uid,
        role: ride.rider_id === uid ? 'rider' : 'driver',
        subject: subject || 'Report Issue',
        content: review,
        status: 'submitted',
      });
      return jsonResponse({ success: true });
    }

    // 🛡️ Segurança: apenas o passageiro da corrida pode avaliar o motorista (C12)
    if (uid !== ride.rider_id && !isAdmin) {
      return errorResponse('Apenas o passageiro desta corrida pode avaliar o motorista', 403);
    }

    if (!rating || rating < 1 || rating > 5) {
      return errorResponse('Rating deve ser entre 1 e 5', 400);
    }

    // 2. Salvar feedback completo
    await supa.from('feedbacks').insert({
      ride_id: rideId,
      driver_id: ride.driver_id,
      rider_id: uid,
      rating: Number(rating),
      review: review || null,
      parameters: parameters || [],
    });

    // 3. Obter nota atualizada calculada nativamente pelo banco (via Trigger)
    const { data: updatedDriver } = await supa
      .from('profiles')
      .select('rating')
      .eq('id', ride.driver_id)
      .single();

    const finalRating = Number(updatedDriver?.rating) || 5.0;

    // 4. Finalizar corrida se não estiver em um estado final (Item 25)
    const isFinalStatus = ['completed', 'finished', 'waiting_for_review', 'rider_canceled', 'driver_canceled', 'canceled', 'expired'].includes(ride.status);
    if (!isFinalStatus) {
      await supa
        .from('rides')
        .update({ status: 'finished' })
        .eq('id', rideId);
    }

    // 🏆 Gamificação: Disparar verificação de badges para o passageiro e o motorista (Item C19)
    if (ride.driver_id) {
      triggerCheckBadge(ride.driver_id);
    }
    triggerCheckBadge(uid);

    return jsonResponse({
      success: true,
      newDriverRating: finalRating,
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('submit-feedback error:', msg);
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

