/**
 * GET-QUICK-REPLIES — Respostas rápidas do chat
 * Migrado do frontend estático + backend
 */

import { getServiceClient } from '../_shared/supabase-client.ts';
import { jsonResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const supa = getServiceClient();

    // Tenta buscar do banco primeiro
    const { data: dbReplies } = await supa
      .from('quick_replies')
      .select('id, text_key, text_pt, role, category')
      .eq('is_enabled', true)
      .order('sort_order', { ascending: true });

    if (dbReplies && dbReplies.length > 0) {
      return jsonResponse({ replies: dbReplies });
    }

    // Fallback: retorna respostas padrão
    const defaultReplies = [
      // Rider
      { text_key: 'quick_reply_on_my_way', text_pt: 'Estou a caminho!', role: 'rider', category: 'general' },
      { text_key: 'quick_reply_wait_please', text_pt: 'Espere um momento, por favor', role: 'rider', category: 'general' },
      { text_key: 'quick_reply_im_here', text_pt: 'Já estou aqui', role: 'rider', category: 'arrival' },
      { text_key: 'quick_reply_where_are_you', text_pt: 'Onde você está?', role: 'rider', category: 'general' },
      { text_key: 'quick_reply_change_pickup', text_pt: 'Posso mudar o ponto de embarque?', role: 'rider', category: 'location' },
      { text_key: 'quick_reply_thanks', text_pt: 'Obrigado(a)!', role: 'rider', category: 'general' },
      // Driver
      { text_key: 'quick_reply_arriving', text_pt: 'Estou chegando!', role: 'driver', category: 'arrival' },
      { text_key: 'quick_reply_im_waiting', text_pt: 'Estou aguardando no local', role: 'driver', category: 'arrival' },
      { text_key: 'quick_reply_what_color', text_pt: 'Qual a cor da sua roupa?', role: 'driver', category: 'identification' },
      { text_key: 'quick_reply_car_info', text_pt: 'Sou o carro que está na frente', role: 'driver', category: 'identification' },
      { text_key: 'quick_reply_traffic', text_pt: 'Trânsito intenso, chego em breve', role: 'driver', category: 'delay' },
      { text_key: 'quick_reply_ok', text_pt: 'Ok, entendido!', role: 'driver', category: 'general' },
    ];

    return jsonResponse({ replies: defaultReplies });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('get-quick-replies error:', msg);
    // Retorna padrão mesmo em erro
    return jsonResponse({ replies: [] });
  }
});
