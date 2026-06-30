/**
 * GET-DIRECTIONS — Proxy seguro para obter rotas da Google Directions API no lado do servidor
 * Mantém a Google API Key oculta do cliente.
 */

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { corsHeaders, jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);

    const body = await req.json();
    const { origin, destination, waypoints, language = 'pt-BR' } = body.args ?? body;

    if (!origin || !destination) {
      return errorResponse('Parâmetros origin e destination são obrigatórios', 400);
    }

    const supa = getServiceClient();

    // Buscar a Google API Key nas configurações
    let googleApiKey = '';
    const { data: settingsRow } = await supa
      .from('app_settings')
      .select('value')
      .eq('key', 'google_map_api_key')
      .maybeSingle();

    if (settingsRow && settingsRow.value) {
      googleApiKey = settingsRow.value.toString();
    }

    if (!googleApiKey) {
      const { data: globalConfigRow } = await supa
        .from('app_settings')
        .select('google_map_api_key')
        .eq('key', 'global_config')
        .maybeSingle();

      if (globalConfigRow && globalConfigRow.google_map_api_key) {
        googleApiKey = globalConfigRow.google_map_api_key.toString();
      }
    }

    if (!googleApiKey) {
      return errorResponse('Google Maps API Key não configurada no servidor', 500);
    }

    let url = `https://maps.googleapis.com/maps/api/directions/json?origin=${encodeURIComponent(origin)}&destination=${encodeURIComponent(destination)}&key=${googleApiKey}&language=${language}`;

    if (waypoints && waypoints.toString().trim().length > 0) {
      url += `&waypoints=${encodeURIComponent(waypoints.toString())}`;
    }

    console.log(`[get-directions] Requesting Google Directions API: ${url.replace(googleApiKey, 'HIDDEN')}`);

    const response = await fetch(url);
    if (!response.ok) {
      console.error(`[get-directions] HTTP Error from Google Directions: ${response.status}`);
      return errorResponse(`Erro HTTP da API Google Directions: ${response.status}`, 502);
    }

    const directionsData = await response.json();
    
    // Retorna a resposta completa da Google Directions API de forma segura
    return jsonResponse(directionsData);

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('[get-directions] Exception:', msg);
    return errorResponse(msg);
  }
});
