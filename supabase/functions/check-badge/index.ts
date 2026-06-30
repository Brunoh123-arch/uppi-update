/**
 * CHECK-BADGE — Verificar conquistas de gamificação
 * Migrado de: functions/src/gamification/gamification.functions.ts
 *
 * Verifica se motorista/passageiro desbloqueou alguma conquista nova
 */

import { getServiceClient, getSupabaseUser, cleanFcmToken, verifyAdmin } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm-client.ts';

interface BadgeDefinition {
  id: string;
  name: string;
  description: string;
  icon: string;
  required_rides?: number;
  required_rating?: number;
  required_tips?: number;
  role: string;
  reward_type?: string;
  reward_amount?: number;
}

const DEFAULT_BADGES: BadgeDefinition[] = [
  // Driver badges
  { id: 'first_ride_driver', name: 'Primeira Viagem', description: 'Completou sua primeira corrida como motorista', icon: '🚗', required_rides: 1, role: 'driver' },
  { id: 'ten_rides_driver', name: '10 Viagens', description: 'Completou 10 corridas', icon: '🏆', required_rides: 10, role: 'driver' },
  { id: 'fifty_rides_driver', name: 'Veterano', description: 'Completou 50 corridas', icon: '⭐', required_rides: 50, role: 'driver' },
  { id: 'hundred_rides_driver', name: 'Lenda', description: 'Completou 100 corridas', icon: '👑', required_rides: 100, role: 'driver' },
  { id: 'five_star_driver', name: '5 Estrelas', description: 'Avaliação perfeita de 5.0', icon: '🌟', required_rating: 5, role: 'driver' },
  // Rider badges
  { id: 'first_ride_rider', name: 'Passageiro(a) Uppi', description: 'Completou sua primeira corrida', icon: '🎉', required_rides: 1, role: 'rider' },
  { id: 'ten_rides_rider', name: 'Viajante Frequente', description: '10 corridas realizadas', icon: '✈️', required_rides: 10, role: 'rider' },
  { id: 'generous_tipper', name: 'Generoso(a)', description: 'Deu 5 gorjetas', icon: '💚', required_tips: 5, role: 'rider' },
];

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    const token = authHeader.replace(/^Bearer\s+/i, '').trim();
    const isServiceRole = token === Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    let body: any = {};
    try {
      body = await req.json();
    } catch (_) {
      // ignore
    }

    const { userId } = body.args ?? body;
    const user = await getSupabaseUser(req);

    let uid = '';
    if (userId && (isServiceRole || (user && await verifyAdmin(req).then(() => true).catch(() => false)))) {
      uid = userId;
    } else {
      if (!user) return errorResponse('Não autenticado', 401);
      uid = user.id;
    }

    const supa = getServiceClient();

    // 1. Buscar perfil
    const { data: profile } = await supa
      .from('profiles')
      // BUG FIX #7: field is 'average_rating', not 'rating' — badge was never awarded
      .select('role, average_rating, review_count, fcm_token')
      .eq('id', uid)
      .single();

    if (!profile) return errorResponse('Perfil não encontrado', 404);

    // 2. Buscar badges do DB ou usar default
    const { data: dbBadges } = await supa
      .from('badge_definitions')
      .select('*')
      .eq('role', profile.role);

    const badges: BadgeDefinition[] = (dbBadges?.length || 0) > 0
      ? dbBadges as unknown as BadgeDefinition[]
      : DEFAULT_BADGES.filter((b) => b.role === profile.role);

    // 3. Buscar badges já conquistados
    const { data: earnedBadges } = await supa
      .from('user_badges')
      .select('badge_id')
      .eq('user_id', uid);

    const earnedIds = new Set((earnedBadges || []).map((b) => b.badge_id));

    // 4. Contar corridas completadas
    const filterCol = profile.role === 'driver' ? 'driver_id' : 'rider_id';
    const { count: completedRides } = await supa
      .from('rides')
      .select('id', { count: 'exact', head: true })
      .eq(filterCol, uid)
      .in('status', ['finished', 'waiting_for_review']);

    // 5. Contar gorjetas dadas (rider)
    let tipCount = 0;
    if (profile.role === 'rider') {
      const { count } = await supa
        .from('wallet_transactions')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', uid)
        .eq('type', 'tip');
      tipCount = count || 0;
    }

    // 6. Verificar novos badges
    const newBadges: BadgeDefinition[] = [];
    for (const badge of badges) {
      if (earnedIds.has(badge.id)) continue;

      let earned = false;
      if (badge.required_rides && (completedRides || 0) >= badge.required_rides) earned = true;
      if (badge.required_rating && (profile.average_rating || 0) >= badge.required_rating) earned = true;
      if (badge.required_tips && tipCount >= badge.required_tips) earned = true;

      if (earned) {
        newBadges.push(badge);
        await supa.from('user_badges').insert({
          user_id: uid,
          badge_id: badge.id,
          badge_name: badge.name,
        });

        // 💰 Conceder recompensa (F8)
        if (badge.reward_type && badge.reward_amount && badge.reward_amount > 0) {
          if (badge.reward_type === 'walletBonus') {
            const amount = Number(badge.reward_amount);
            // Adicionar saldo à carteira do usuário
            const { error: walletError } = await supa.rpc('increment_wallet', {
              target_user_id: uid,
              amount_to_add: amount,
            });

            if (walletError) {
              console.error(`Erro ao creditar recompensa da conquista ${badge.name}:`, walletError);
            } else {
              // Inserir registro na carteira
              await supa.from('wallet_transactions').insert({
                user_id: uid,
                amount: amount,
                type: 'badge_reward',
                description: `Conquista desbloqueada: ${badge.name}`,
                status: 'completed',
              });
              console.log(`Recompensa de R$ ${amount} creditada para o usuário ${uid} (conquista: ${badge.name})`);
            }
          } else if (badge.reward_type === 'commissionExemption') {
            const days = Number(badge.reward_amount) || 7;
            // Calcular nova data de isenção de comissão
            const { data: currentProfile } = await supa
              .from('profiles')
              .select('commission_exempt_until')
              .eq('id', uid)
              .single();
            
            const now = new Date();
            let baseDate = now;
            if (currentProfile?.commission_exempt_until) {
              const currentExemptDate = new Date(currentProfile.commission_exempt_until);
              if (currentExemptDate > now) {
                baseDate = currentExemptDate;
              }
            }
            
            const newExemptUntil = new Date(baseDate.getTime() + days * 24 * 60 * 60 * 1000).toISOString();
            
            const { error: profileError } = await supa
              .from('profiles')
              .update({ commission_exempt_until: newExemptUntil })
              .eq('id', uid);
              
            if (profileError) {
              console.error(`Erro ao aplicar isenção de comissão para a conquista ${badge.name}:`, profileError);
            } else {
              console.log(`Isenção de comissão por ${days} dias aplicada para o motorista ${uid} (conquista: ${badge.name})`);
            }
          }
        }
      }
    }

    // 7. Notificar novos badges
    if (newBadges.length > 0 && profile.fcm_token) {
      for (const badge of newBadges) {
        const pushResult = await sendPush({
          token: profile.fcm_token,
          title: `${badge.icon} Conquista Desbloqueada!`,
          body: `${badge.name} — ${badge.description}`,
          data: { type: 'badge_earned', badge_id: badge.id },
          channelId: 'announcements',
        });
        if (pushResult.invalidToken) {
          await cleanFcmToken(uid, profile.fcm_token);
        }
      }
    }

    return jsonResponse({
      total_badges: badges.length,
      earned: earnedIds.size + newBadges.length,
      new_badges: newBadges.map((b) => ({ id: b.id, name: b.name, icon: b.icon, description: b.description })),
      all_badges: badges.map((b) => ({
        ...b,
        earned: earnedIds.has(b.id) || newBadges.some((n) => n.id === b.id),
      })),
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('check-badge error:', msg);
    return errorResponse(msg);
  }
});
