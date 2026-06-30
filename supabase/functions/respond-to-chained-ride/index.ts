/**
 * RESPOND-TO-CHAINED-RIDE
 * Processa a resposta do motorista para uma corrida encadeada.
 */

import { getServiceClient, getSupabaseUser, verifyDriver } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    // 🛡️ Segurança: Validar token JWT e garantir que o chamador é um motorista
    let driverUid: string;
    try {
      driverUid = await verifyDriver(req);
    } catch (err: any) {
      const isNotDriver = err.message.includes('requer conta de motorista');
      const msg = isNotDriver ? 'Acesso negado - conta de passageiro' : err.message;
      return errorResponse(msg, err.message.includes('Não autenticado') ? 401 : 403);
    }

    const body = await req.json();
    const data = body.data ?? body;
    const { nextOrderId, accept } = data;

    if (!nextOrderId) {
      return errorResponse('nextOrderId é obrigatório', 400);
    }

    if (accept === true) {
      const supa = getServiceClient();
      
      // Vincula o motorista à corrida usando a mesma RPC do assign_driver normal
      const { error: rpcErr } = await supa.rpc("assign_driver_to_ride", {
        p_ride_id: nextOrderId,
        p_driver_id: driverUid,
      });

      if (rpcErr) {
        console.error("Erro ao aceitar corrida encadeada:", rpcErr);
        return errorResponse(rpcErr.message, 422);
      }

      return jsonResponse({ success: true, message: 'Corrida encadeada aceita com sucesso.' });
    }

    // Se recusou, no momento não fazemos nada, o app apenas esconde o banner
    return jsonResponse({ success: true, message: 'Corrida recusada pelo motorista.' });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('respond-to-chained-ride error:', msg);
    return errorResponse(msg);
  }
});
