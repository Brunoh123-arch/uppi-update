/**
 * DRIVER-FLOW-ACTIONS Gateway — Ponto de entrada consolidado para o fluxo do motorista
 * Centraliza update-location, update-status, accept-order, arrived, start e finish para combater o Cold Start Hell.
 */

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { handleUpdateDriverLocation } from '../update-driver-location/handler.ts';
import { handleUpdateDriverStatus } from '../update-driver-status/handler.ts';
import { handleAcceptOrder } from '../accept-order/handler.ts';
import { handleArrivedAtPickup } from '../arrived-at-pickup/handler.ts';
import { handleStartOrder } from '../start-order/handler.ts';
import { handleFinishOrder } from '../finish-order/handler.ts';
import { errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse(req);

  try {
    // Clonamos a requisição para ler o corpo (action)
    // sem consumir a stream original para os handlers.
    const clone = req.clone();
    const body = await clone.json();

    const action = body.action || body.args?.action;

    if (action === 'update-driver-location') {
      return await handleUpdateDriverLocation(req);
    } else if (action === 'update-driver-status') {
      return await handleUpdateDriverStatus(req);
    } else if (action === 'accept-order') {
      return await handleAcceptOrder(req);
    } else if (action === 'arrived-at-pickup') {
      return await handleArrivedAtPickup(req);
    } else if (action === 'start-order') {
      return await handleStartOrder(req);
    } else if (action === 'finish-order') {
      return await handleFinishOrder(req);
    } else {
      return errorResponse(`Ação "${action}" não suportada no Driver Flow Gateway.`, 400, req);
    }
  } catch (e: any) {
    console.error('[driver-flow-actions] Gateway Exception:', e);
    return errorResponse(`Erro no processamento do gateway: ${e.message}`, 400, req);
  }
});
