/**
 * DELETE-USER-ACCOUNT — Soft-delete de conta de usuário
 * Marca perfil como deletado, limpa dados pessoais, cancela corridas ativas
 */

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    const body = await req.json();
    let targetUid = body.uid;

    if (!user) return errorResponse('Não autenticado', 401);

    const supa = getServiceClient();

    if (user) {
      const { data: adminRecord } = await supa
        .from('admins')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();

      if (adminRecord) {
        // É administrador: DEVE informar targetUid
        if (!targetUid) return errorResponse('Admin deve enviar uid do alvo no body', 400);
      } else {
        // Usuário comum: SÓ pode deletar a própria conta
        targetUid = user.id;
      }
    }

    if (!targetUid) return errorResponse('uid é obrigatório', 400);

    // Soft-delete: marcar perfil como deletado e limpar dados pessoais
    const { error: profileError } = await supa
      .from('profiles')
      .update({
        is_deleted: true,
        deleted_at: new Date().toISOString(),
        fcm_token: null,
        email: null,
        phone_number: null,
        phone: null,
        cpf: null,             // 🛡️ LGPD: Limpar CPF (dado pessoal sensível)
        document_number: null, // Alias do CPF caso utilizado
        documents: null,       // 🛡️ LGPD: Limpar metadados de documentos (CNH/CRLV)
        full_name: 'Usuário Anônimo',  // Era 'Conta Excluída' — mais neutro e LGPD-compliant
        avatar_url: null,      // Remover foto de perfil
        status: 'deleted',
      })
      .eq('id', targetUid);

    if (profileError) {
      console.error('Erro ao deletar perfil:', profileError);
    }

    // 🛡️ LGPD: Excluir dados bancários/PIX associados do motorista da tabela payout_accounts
    const { error: payoutError } = await supa
      .from('payout_accounts')
      .delete()
      .eq('driver_id', targetUid);
    
    if (payoutError) {
      console.error('Erro ao deletar contas bancárias de saques:', payoutError);
    }

    // 🛡️ LGPD: Deletar fisicamente fotos do Storage (avatar e documentos)
    try {
      // Buckets: avatars
      const { data: avatarFiles } = await supa.storage.from('avatars').list(targetUid);
      if (avatarFiles && avatarFiles.length > 0) {
        const paths = avatarFiles.map(f => `${targetUid}/${f.name}`);
        await supa.storage.from('avatars').remove(paths);
      }
      
      // Buckets: documents (raiz da pasta do usuário)
      const { data: docFiles } = await supa.storage.from('documents').list(targetUid);
      if (docFiles && docFiles.length > 0) {
        const paths = docFiles.map(f => `${targetUid}/${f.name}`);
        await supa.storage.from('documents').remove(paths);
      }
      
      // Buckets: documents/documents (subpasta criada pelo picker)
      const { data: docSubFiles } = await supa.storage.from('documents').list(`${targetUid}/documents`);
      if (docSubFiles && docSubFiles.length > 0) {
        const paths = docSubFiles.map(f => `${targetUid}/documents/${f.name}`);
        await supa.storage.from('documents').remove(paths);
      }
      
      console.log(`[LGPD-Storage] Limpeza física de arquivos concluída para uid: ${targetUid}`);
    } catch (err) {
      console.error('[LGPD-Storage] Falha ao limpar arquivos físicos do storage:', err);
    }

    // Registrar ação no log de auditoria administrativa
    await supa
      .from('admin_audit_log')
      .insert({
        action_type: 'user_account_deleted',
        target_resource_id: targetUid,
        details: { reason: 'Right to be forgotten (LGPD)', deleted_at: new Date().toISOString() }
      });

    // Limpar driver_locations
    await supa
      .from('driver_locations')
      .delete()
      .eq('driver_id', targetUid);

    // Cancelar corridas ativas do passageiro
    // BUG FIX #6: 'canceled' is not a valid status — use 'rider_canceled'/'driver_canceled'
    await supa
      .from('rides')
      .update({ status: 'rider_canceled', cancel_reason_note: 'Conta excluída pelo usuário' })
      .eq('rider_id', targetUid)
      .in('status', ['requested', 'driver_accepted', 'arrived', 'started', 'in_progress']);

    await supa
      .from('rides')
      .update({ status: 'driver_canceled', cancel_reason_note: 'Conta excluída pelo motorista' })
      .eq('driver_id', targetUid)
      .in('status', ['requested', 'driver_accepted', 'arrived', 'started', 'in_progress']);

    return jsonResponse({ success: true, message: 'Conta marcada para exclusão' });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('delete-user-account error:', msg);
    return errorResponse(msg);
  }
});
