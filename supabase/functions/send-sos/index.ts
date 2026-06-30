/**
 * SEND-SOS — Enviar alerta de emergência (SOS)
 * Migrado de: functions/src/sos/sos.functions.ts
 */

import { getServiceClient, getSupabaseUser, cleanFcmToken } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { sendPush } from '../_shared/fcm-client.ts';
import { sosLimiter } from '../_shared/rate-limiter.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);
    const uid = user.id;

    if (sosLimiter.isRateLimited(uid)) {
      return errorResponse('Muitas solicitações de SOS. Aguarde um momento.', 429);
    }

    const body = await req.json();
    const { ride_id, orderId, lat, lng, message } = body.args ?? body;
    const rideId = ride_id || orderId;

    const supa = getServiceClient();

    // Buscar perfil do usuário
    const { data: profile } = await supa
      .from('profiles')
      .select('full_name, phone, role')
      .eq('id', uid)
      .single();

    // Registrar SOS
    const { data: sos } = await supa
      .from('sos_alerts')
      .insert({
        user_id: uid,
        ride_id: rideId || null,
        lat: lat ? Number(lat) : null,
        lng: lng ? Number(lng) : null,
        message: message || 'Alerta de emergência ativado',
        user_name: profile?.full_name || 'Usuário',
        user_phone: profile?.phone || '',
        status: 'active',
        submitted_by: profile?.role || 'unknown',
      })
      .select()
      .single();

    // Notificar admins — admins ficam na tabela 'admins', não em profiles.role
    const { data: adminRows } = await supa
      .from('admins')
      .select('id');

    if (adminRows && adminRows.length > 0) {
      // Buscar fcm_tokens dos admins via profiles
      const adminIds = adminRows.map((a: { id: string }) => a.id);
      const { data: adminProfiles } = await supa
        .from('profiles')
        .select('id, fcm_token')
        .in('id', adminIds)
        .not('fcm_token', 'is', null);

      if (adminProfiles && adminProfiles.length > 0) {
        for (const admin of adminProfiles) {
          if (admin.fcm_token) {
            const pushResult = await sendPush({
              token: admin.fcm_token,
              title: '🚨 ALERTA SOS!',
              body: `${profile?.full_name || 'Usuário'} ativou o botão de emergência!${rideId ? ` (Corrida #${rideId.substring(0, 8)})` : ''}`,
              data: { type: 'sos_alert', sos_id: sos?.id || '', ride_id: rideId || '' },
              channelId: 'safety',
            });
            if (pushResult.invalidToken) {
              await cleanFcmToken(admin.id, admin.fcm_token);
            }
          }
        }
      }
    }

    // Se for passageiro e tem motorista na corrida, notificar motorista também
    if (rideId && profile?.role === 'rider') {
      const { data: ride } = await supa
        .from('rides')
        .select('driver_id')
        .eq('id', rideId)
        .single();

      if (ride?.driver_id) {
        const { data: driverProfile } = await supa
          .from('profiles')
          .select('fcm_token')
          .eq('id', ride.driver_id)
          .single();

        if (driverProfile?.fcm_token) {
          const pushResult = await sendPush({
            token: driverProfile.fcm_token,
            title: '🚨 Alerta de Emergência',
            body: 'O passageiro ativou o botão de emergência!',
            data: { type: 'sos_alert', ride_id: rideId },
            channelId: 'safety',
          });
          if (pushResult.invalidToken) {
            await cleanFcmToken(ride.driver_id, driverProfile.fcm_token);
          }
        }
      }
    }

    return jsonResponse({
      success: true,
      sos_id: sos?.id,
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('send-sos error:', msg);
    return errorResponse(msg);
  }
});
