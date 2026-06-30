import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { authLimiter } from '../_shared/rate-limiter.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    // 1. Validar JWT nativo do Supabase
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Unauthorized', 401);

    const uid = user.id;

    // Rate limiting — máx 10 syncs por minuto por usuário
    if (authLimiter.isRateLimited(uid)) {
      return errorResponse('Muitas tentativas. Aguarde.', 429);
    }

    const body = await req.json().catch(() => ({}));

    // Campos que um usuário regular PODE editar diretamente no próprio perfil
    const allowedFields = [
      'fcm_token', 'vehicle_details', 
      'full_name', 'avatar_url', 'documents', 
      'search_radius', 'gender', 'id_number', 'favorite_drivers',
      'identity_docs'
    ];

    const supa = getServiceClient();

    // 2. Buscar perfil existente para preservar estritamente campos sensíveis e impedir bypass de segurança/KYC
    const { data: existingProfile } = await supa
      .from('profiles')
      .select('id, role, status, identity_verification_status')
      .eq('id', uid)
      .maybeSingle();

    const profileData: Record<string, any> = {
      id: uid,
      updated_at: new Date().toISOString(),
    };

    // Extrair apenas os campos permitidos enviados no body do cliente
    for (const key of Object.keys(body)) {
      if (allowedFields.includes(key)) {
        profileData[key] = body[key];
      }
    }

    // 3. Impor valores padrão seguros (se novo usuário) ou herdar campos sensíveis inalterados (se existente)
    if (!existingProfile) {
      profileData.role = 'rider'; // Novos usuários iniciam sempre como passageiros
      profileData.status = 'active';
      profileData.identity_verification_status = 'pending';
    } else {
      profileData.role = existingProfile.role ?? 'rider';
      profileData.status = existingProfile.status ?? 'active';
      // Se novos documentos de KYC forem enviados, transiciona automaticamente para pendente.
      // Caso contrário, herda o status de validação existente para evitar privilege escalation.
      if (body.identity_docs) {
        profileData.identity_verification_status = 'pending';
      } else {
        profileData.identity_verification_status = existingProfile.identity_verification_status ?? 'pending';
      }
    }

    // Sobrescrever com valores estritos do JWT se disponíveis (boas práticas)
    if (user.user_metadata?.full_name && !profileData.full_name) profileData.full_name = user.user_metadata.full_name;
    if (user.email && !profileData.email) profileData.email = user.email;
    if (user.user_metadata?.avatar_url && !profileData.avatar_url) profileData.avatar_url = user.user_metadata.avatar_url;
    if (user.phone && !profileData.phone) profileData.phone = user.phone;

    // Reutiliza existingProfile da query acima (evita segunda chamada desnecessária)
    let queryResult;
    if (existingProfile) {
      queryResult = await supa
        .from('profiles')
        .update(profileData)
        .eq('id', uid)
        .select()
        .single();
    } else {
      queryResult = await supa
        .from('profiles')
        .insert(profileData)
        .select()
        .single();
    }

    const { data, error } = queryResult;

    if (error) throw error;

    return jsonResponse({ success: true, profile: data });

  } catch (error: unknown) {
    const msg = error instanceof Error 
      ? error.message 
      : (typeof error === 'object' && error !== null ? JSON.stringify(error) : String(error));
    console.error("sync_profile error:", msg);
    return errorResponse(msg);
  }
});
