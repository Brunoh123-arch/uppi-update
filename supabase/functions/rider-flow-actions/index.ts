/**
 * RIDER-FLOW-ACTIONS Gateway — Ponto de entrada consolidado para o fluxo do passageiro
 * Centraliza calculate-fare, create-order e cancel-order para combater o Cold Start Hell.
 */

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { handleCalculateFare } from '../calculate-fare/handler.ts';
import { handleCreateOrder } from '../create-order/handler.ts';
import { handleCancelOrder } from '../cancel-order/handler.ts';
import { errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse(req);

  try {
    // Clonamos a requisição para podermos ler o corpo (action)
    // sem consumir a stream da requisição original que será passada aos handlers.
    const clone = req.clone();
    const body = await clone.json();
    
    // Suporta action direta ou envelopada em args
    const action = body.action || body.args?.action;

    if (action === 'calculate-fare') {
      return await handleCalculateFare(req);
    } else if (action === 'create-order') {
      return await handleCreateOrder(req);
    } else if (action === 'cancel-order') {
      return await handleCancelOrder(req);
    } else {
      return errorResponse(`Ação "${action}" não suportada no Rider Flow Gateway.`, 400, req);
    }
  } catch (e: any) {
    console.error('[rider-flow-actions] Gateway Exception:', e);
    return errorResponse(`Erro no processamento do gateway: ${e.message}`, 400, req);
  }
});
