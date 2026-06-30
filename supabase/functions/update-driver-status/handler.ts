/**
 * UPDATE-DRIVER-STATUS Handler — Atualiza status do motorista (online/offline)
 * Migrado de: index.ts
 */

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

export async function handleUpdateDriverStatus(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return optionsResponse(req);

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401, req);
    const uid = user.id;

    const body = await req.json();
    const { status, lat, lng } = body.args ?? body;

    if (!status) return errorResponse('status é obrigatório', 400, req);

    const validStatuses = ['online', 'offline', 'in_service'];
    if (!validStatuses.includes(status)) {
      return errorResponse(`Status inválido. Use: ${validStatuses.join(', ')}`, 400, req);
    }

    const supa = getServiceClient();

    // Verificar se motorista existe e pode ficar online
    const { data: profile } = await supa
      .from('profiles')
      .select('role, is_approved')
      .eq('id', uid)
      .single();

    if (!profile || profile.role !== 'driver') {
      return errorResponse('Acesso negado', 403, req);
    }

    // Não pode ficar online se não está aprovado pelo administrador (is_approved === true)
    if (status === 'online' && profile.is_approved !== true) {
      return errorResponse('Sua conta precisa estar aprovada para ficar online', 403, req);
    }

    // Atualizar status na tabela de localizações
    const updateData: Record<string, unknown> = {
      driver_id: uid,
      status,
      updated_at: new Date().toISOString(),
    };

    if (lat && lng) {
      updateData.lat = Number(lat);
      updateData.lng = Number(lng);
    }

    // UPPI SEGURANÇA: Para evitar erros de restrição de NOT NULL nas colunas lat/lng
    // durante atualizações parciais de status, verificamos se o registro já existe.
    const { data: existingLocation } = await supa
      .from('driver_locations')
      .select('driver_id')
      .eq('driver_id', uid)
      .maybeSingle();

    let error;
    if (existingLocation) {
      const { error: updateErr } = await supa
        .from('driver_locations')
        .update(updateData)
        .eq('driver_id', uid);
      error = updateErr;
    } else {
      updateData.lat = lat ? Number(lat) : 0.0;
      updateData.lng = lng ? Number(lng) : 0.0;
      const { error: insertErr } = await supa
        .from('driver_locations')
        .upsert(updateData, { onConflict: 'driver_id' });
      error = insertErr;
    }

    if (error) return errorResponse(error.message, 500, req);

    // Sincronizar na tabela profiles
    await supa
      .from('profiles')
      .update({ status })
      .eq('id', uid);

    return jsonResponse({ success: true, status }, 200, req);

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('update-driver-status error:', msg);
    return errorResponse(msg, 500, req);
  }
}
