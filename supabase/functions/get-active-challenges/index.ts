/**
 * GET-ACTIVE-CHALLENGES — Retorna desafios ativos para o motorista com progresso
 * Calcula progresso contando corridas completadas no período de cada desafio
 */

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);

    const userId = user.id;
    const supa = getServiceClient();
    const now = new Date().toISOString();

    // Buscar desafios ativos (não expirados)
    const { data: activeChallenges } = await supa
      .from('challenges')
      .select('*')
      .eq('is_active', true)
      .or(`period_end_at.is.null,period_end_at.gte.${now}`)
      .order('created_at', { ascending: false });

    if (!activeChallenges || activeChallenges.length === 0) {
      return jsonResponse({ challenges: [] });
    }

    // Buscar progresso do motorista — contar corridas completadas no período
    const challenges = [];

    for (const challenge of activeChallenges) {
      const periodStart = challenge.period_start_at || challenge.created_at;
      const periodEnd = challenge.period_end_at || now;

      const { count } = await supa
        .from('rides')
        .select('id', { count: 'exact', head: true })
        .eq('driver_id', userId)
        .in('status', ['completed', 'finished', 'waiting_for_review'])
        .gte('finished_at', periodStart)
        .lte('finished_at', periodEnd);

      const progress = count || 0;
      const target = challenge.target || 0;

      challenges.push({
        id: challenge.id,
        title: challenge.title,
        description: challenge.description,
        target,
        progress,
        currentProgress: progress,
        goal: target,
        rewardType: challenge.reward_type || 'walletBonus',
        rewardDescription: challenge.reward_description || challenge.reward_label || '',
        rewardLabel: challenge.reward_label || challenge.reward_description || '',
        rewardAmount: challenge.reward_amount,
        periodEndAt: challenge.period_end_at,
        endsAt: challenge.period_end_at,
        completed: progress >= target,
      });
    }

    return jsonResponse({ challenges });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('get-active-challenges error:', msg);
    return errorResponse(msg);
  }
});
