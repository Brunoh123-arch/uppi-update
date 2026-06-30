import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

/**
 * USER-ACTIONS — Secure wrapper for basic CRUD on user-owned tables
 * Enforces server-side validation and prevents unauthorized manipulation.
 * Tables allowed: favorite_addresses, favorite_drivers, saved_payment_methods
 */

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);
    const uid = user.id;

    const body = await req.json();
    const { action, table, data, id } = body;

    const allowedTables = ['favorite_addresses', 'favorite_drivers', 'payment_methods', 'payout_accounts', 'payout_requests'];
    if (!allowedTables.includes(table)) {
      return errorResponse('Tabela não permitida', 403);
    }

    const supa = getServiceClient();

    switch (action) {
      case 'insert': {
        // Enforce user ownership
        const insertData = { ...data, user_id: uid };
        if (table === 'payment_methods') insertData.user_id = uid;
        if (table === 'payout_accounts') {
          delete insertData.user_id;
          insertData.driver_id = uid;
        }
        if (table === 'payout_requests') {
          delete insertData.user_id;
          insertData.driver_id = uid;
          insertData.status = 'pending'; // Forçar status pendente no servidor
        }
        
        const { data: result, error } = await supa
          .from(table)
          .insert(insertData)
          .select()
          .single();
          
        if (error) throw error;
        return jsonResponse({ success: true, data: result });
      }

      case 'update': {
        if (!id) return errorResponse('ID necessário para update', 400);
        
        // Ensure user only updates their own data
        let idField = 'user_id';
        if (table === 'payment_methods') idField = 'user_id';
        if (table === 'payout_accounts') idField = 'driver_id';
        
        const { data: result, error } = await supa
          .from(table)
          .update(data)
          .eq('id', id)
          .eq(idField, uid)
          .select()
          .single();
          
        if (error) throw error;
        return jsonResponse({ success: true, data: result });
      }

      case 'delete': {
        if (!id) return errorResponse('ID necessário para delete', 400);
        
        // For favorite_drivers, id might be driver_id. Wait, favorite_drivers doesn't have a PK 'id' usually.
        // Let's check: if table is favorite_drivers, data might contain driver_id
        if (table === 'favorite_drivers') {
            const driverId = data?.driver_id || id;
            const { error } = await supa
            .from(table)
            .delete()
            .eq('user_id', uid)
            .eq('driver_id', driverId);
            if (error) throw error;
            return jsonResponse({ success: true });
        }

        let idField = 'user_id';
        if (table === 'payment_methods') idField = 'user_id';
        if (table === 'payout_accounts') idField = 'driver_id';

        const { error } = await supa
          .from(table)
          .delete()
          .eq('id', id)
          .eq(idField, uid);
          
        if (error) throw error;
        return jsonResponse({ success: true });
      }
      
      case 'set_default_payment': {
        if (table !== 'payment_methods') return errorResponse('Ação inválida para tabela', 400);
        if (!id) return errorResponse('ID necessário', 400);
        
        // Reset all defaults for user
        await supa.from(table).update({ is_default: false }).eq('user_id', uid);
        
        // Set new default
        const { data: result, error } = await supa
            .from(table)
            .update({ is_default: true })
            .eq('id', id)
            .eq('user_id', uid)
            .select()
            .single();
            
        if (error) throw error;
        return jsonResponse({ success: true, data: result });
      }

      case 'set_default_payout': {
        if (table !== 'payout_accounts') return errorResponse('Ação inválida para tabela', 400);
        if (!id) return errorResponse('ID necessário', 400);
        
        // Supabase trigger enforce_single_default_payout_account already handles this
        // But we just update the specific one to true
        const { data: result, error } = await supa
            .from(table)
            .update({ is_default: true })
            .eq('id', id)
            .eq('driver_id', uid)
            .select()
            .single();
            
        if (error) throw error;
        return jsonResponse({ success: true, data: result });
      }

      default:
        return errorResponse('Ação inválida', 400);
    }
  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    return errorResponse(msg);
  }
});
