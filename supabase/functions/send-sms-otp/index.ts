/**
 * SEND-SMS-OTP Edge Function
 * Atua como Custom SMS Hook do Supabase Auth ou disparo de SMS de teste.
 */

import { getServiceClient } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  // CORS preflight requests
  if (req.method === 'OPTIONS') return optionsResponse(req);

  try {
    if (req.method !== 'POST') {
      return errorResponse('Método não permitido. Utilize POST.', 405, req);
    }

    const body = await req.json().catch(() => ({}));
    const args = body.args ?? body;

    // Resilient parsing of recipient phone number
    const phone = args.phone || 
                  args.phone_number || 
                  args.sms?.phone || 
                  args.sms?.phone_number || 
                  body.phone || 
                  body.phone_number || 
                  body.sms?.phone || 
                  body.sms?.phone_number;

    // Resilient parsing of message / otp code
    const message = args.message || 
                    args.otp_code || 
                    args.otp || 
                    args.sms?.message || 
                    args.sms?.otp || 
                    args.sms?.otp_code || 
                    body.message || 
                    body.otp_code || 
                    body.otp || 
                    body.sms?.message || 
                    body.sms?.otp || 
                    body.sms?.otp_code;

    if (!phone) {
      return errorResponse('Destinatário (phone ou phone_number) é obrigatório.', 400, req);
    }
    if (!message) {
      return errorResponse('Conteúdo do SMS (message ou otp_code) é obrigatório.', 400, req);
    }

    // Carregar configurações dinamicamente do Supabase
    const supa = getServiceClient();
    const { data: settings, error: settingsError } = await supa
      .from('app_settings')
      .select('*')
      .eq('key', 'global_config')
      .maybeSingle();

    if (settingsError || !settings) {
      console.error('[SendSmsOtp] Erro ao carregar app_settings:', settingsError);
      return errorResponse('Configurações globais (global_config) não encontradas no banco de dados.', 500, req);
    }

    // Obter credenciais de forma resiliente (tanto de colunas diretas quanto de meta JSON)
    const accountSid = settings.twilio_account_sid || settings.meta?.twilio_account_sid;
    const authToken = settings.twilio_auth_token || settings.meta?.twilio_auth_token;
    const messagingServiceSid = settings.twilio_messaging_service_sid || settings.meta?.twilio_messaging_service_sid;
    const twilioPhoneNumber = settings.twilio_phone_number || settings.meta?.twilio_phone_number;

    if (!accountSid || !authToken) {
      return errorResponse('Twilio não configurado. twilio_account_sid e twilio_auth_token são obrigatórios em app_settings.', 400, req);
    }

    // Twilio REST API para mensagens
    const twilioUrl = `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`;
    const basicAuth = btoa(`${accountSid}:${authToken}`);

    const params = new URLSearchParams();
    params.append('To', phone);

    if (messagingServiceSid) {
      params.append('MessagingServiceSid', messagingServiceSid);
    } else if (twilioPhoneNumber) {
      params.append('From', twilioPhoneNumber);
    } else {
      return errorResponse('Twilio mal configurado. Defina twilio_messaging_service_sid ou twilio_phone_number.', 400, req);
    }

    params.append('Body', message);

    console.log(`[SendSmsOtp] Enviando SMS para ${phone} via Twilio Account: ${accountSid}`);

    const response = await fetch(twilioUrl, {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${basicAuth}`,
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      body: params.toString()
    });

    const responseText = await response.text();

    if (!response.ok) {
      console.error(`[SendSmsOtp] Twilio API Error (Status ${response.status}):`, responseText);
      return errorResponse(`Falha ao enviar SMS via Twilio: ${responseText}`, 400, req);
    }

    console.log(`[SendSmsOtp] SMS enviado com sucesso para ${phone}`);

    // Retorna 200 OK com json vazio {} para o Supabase Auth aceitar
    return jsonResponse({}, 200, req);

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('[SendSmsOtp] Erro inesperado:', msg);
    return errorResponse(msg, 500, req);
  }
});
