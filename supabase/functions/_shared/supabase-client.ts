/**
 * Supabase client helpers para Edge Functions
 */

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';

let _serviceClient: SupabaseClient | null = null;

/** Service role client — bypassa RLS para operações server-side */
export function getServiceClient(): SupabaseClient {
  if (!_serviceClient) {
    _serviceClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );
  }
  return _serviceClient;
}

/** Extrai o user autenticado via JWT do Supabase */
export async function getSupabaseUser(req: Request) {
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return null;

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: `Bearer ${token}` } } },
  );

  const { data: { user }, error } = await userClient.auth.getUser();
  if (error || !user) return null;
  return user;
}

/** Verifica se o user é admin (checa a tabela admins) */
export async function verifyAdmin(req: Request): Promise<string> {
  const user = await getSupabaseUser(req);
  if (!user) throw new Error('Não autenticado');

  const supa = getServiceClient();
  const { data: adminRecord } = await supa
    .from('admins')
    .select('role')
    .eq('id', user.id)
    .maybeSingle();

  if (!adminRecord) {
    throw new Error('Acesso negado - requer privilégios de admin');
  }

  return user.id;
}

/** Verifica se o user é superadmin (checa a tabela admins e se a role é superadmin) */
export async function verifySuperAdmin(req: Request): Promise<string> {
  const user = await getSupabaseUser(req);
  if (!user) throw new Error('Não autenticado');

  const supa = getServiceClient();
  const { data: adminRecord } = await supa
    .from('admins')
    .select('role')
    .eq('id', user.id)
    .maybeSingle();

  if (!adminRecord || adminRecord.role !== 'superadmin') {
    throw new Error('Acesso negado - requer privilégios de superadmin');
  }

  return user.id;
}

/** Verifica se o user é motorista */
export async function verifyDriver(req: Request): Promise<string> {
  const user = await getSupabaseUser(req);
  if (!user) throw new Error('Não autenticado');

  const supa = getServiceClient();
  const { data: profile, error } = await supa
    .from('profiles')
    .select('role')
    .eq('id', user.id)
    .maybeSingle();

  if (error) {
    throw new Error(`Erro ao verificar perfil: ${error.message}`);
  }

  if (!profile || profile.role !== 'driver') {
    throw new Error('Acesso negado - requer conta de motorista');
  }

  return user.id;
}

/** Remove token FCM inválido do perfil do usuário */
export async function cleanFcmToken(userId: string, token: string): Promise<void> {
  const supa = getServiceClient();
  try {
    const { error } = await supa
      .from('profiles')
      .update({ fcm_token: null })
      .eq('id', userId)
      .eq('fcm_token', token);
    if (error) {
      console.warn(`[cleanFcmToken] Erro ao limpar token para o usuário ${userId}:`, error.message);
    } else {
      console.log(`[cleanFcmToken] Token inválido limpo com sucesso para o usuário ${userId}`);
    }
  } catch (err) {
    console.warn(`[cleanFcmToken] Falha ao limpar token do usuário ${userId}:`, err);
  }
}

/** Remove múltiplos tokens FCM inválidos da base de dados */
export async function cleanMultipleFcmTokens(tokens: string[]): Promise<void> {
  if (!tokens || tokens.length === 0) return;
  const supa = getServiceClient();
  try {
    const { error } = await supa
      .from('profiles')
      .update({ fcm_token: null })
      .in('fcm_token', tokens);
    if (error) {
      console.warn(`[cleanMultipleFcmTokens] Erro ao limpar múltiplos tokens:`, error.message);
    } else {
      console.log(`[cleanMultipleFcmTokens] ${tokens.length} tokens inválidos limpos com sucesso`);
    }
  } catch (err) {
    console.warn(`[cleanMultipleFcmTokens] Falha ao limpar múltiplos tokens:`, err);
  }
}

