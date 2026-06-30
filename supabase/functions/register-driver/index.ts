/**
 * REGISTER-DRIVER — Cadastro de novo motorista
 * Migrado de: functions/src/drivers/driver.functions.ts (registerDriver)
 */

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);
    const uid = user.id;

    const body = await req.json();
    const {
      fullName, phone, vehiclePlate, vehicleModelId,
      vehicleColorId, vehicleYear, vehicleCategory,
      bankName, bankAccountNumber, bankSwiftCode, bankRoutingNumber,
      address, email, certificateNumber, searchDistance,
      documents, avatarUrl
    } = body.args ?? body;

    if (!fullName || fullName.trim() === '') {
      return errorResponse('fullName é obrigatório', 400);
    }

    const supa = getServiceClient();

    // Verificar se já é motorista
    const { data: existing } = await supa
      .from('profiles')
      .select('role')
      .eq('id', uid)
      .single();

    // Atualizar perfil com role de motorista
    const vehicle_details = {
      plate: vehiclePlate,
      model: vehicleModelId,
      color: vehicleColorId,
      year: vehicleYear,
      category: vehicleCategory,
      certificateNumber: certificateNumber,
      address: address,
      searchDistance: searchDistance,
      bankName: bankName,
      bankAccountNumber: bankAccountNumber,
      bankSwiftCode: bankSwiftCode,
      bankRoutingNumber: bankRoutingNumber,
    };

    const { error: profileErr } = await supa
      .from('profiles')
      .update({
        role: 'driver',
        full_name: fullName,
        phone,
        email: email,
        cpf: certificateNumber || null,
        status: 'waiting_documents',
        address: address,
        avatar_url: avatarUrl || null,
        documents: documents || null,
        // Grava a COLUNA vehicle_type (carro/moto/suv/executivo) — usada pelo
        // marcador do passageiro e pelo matching de corridas. Antes só ia para
        // dentro do JSON vehicle_details.category e a coluna ficava no default 'carro'.
        vehicle_type: vehicleCategory || 'carro',
        vehicle_plate_number: vehiclePlate || null,
        vehicle_production_year: vehicleYear ? parseInt(String(vehicleYear), 10) : null,
        vehicle_model_id: vehicleModelId || null,
        vehicle_color_id: vehicleColorId || null,
        bank_name: bankName || null,
        bank_account_number: bankAccountNumber || null,
        bank_swift_code: bankSwiftCode || null,
        bank_routing_number: bankRoutingNumber || null,
        vehicle_details: vehicle_details,
      })
      .eq('id', uid);

    if (profileErr) return errorResponse(profileErr.message, 500);

    // Salvar documentos do motorista
    await supa.from('driver_documents').upsert({
      driver_id: uid,
      cnh: certificateNumber || null,
      vehicle_plate: vehiclePlate || null,
      vehicle_model: vehicleModelId || null,
      vehicle_color: vehicleColorId || null,
      vehicle_year: vehicleYear || null,
      vehicle_category: vehicleCategory || null,
      status: 'pending_review',
    }, { onConflict: 'driver_id' });

    // Inicializar localização
    await supa.from('driver_locations').upsert({
      driver_id: uid,
      lat: 0,
      lng: 0,
      status: 'offline',
    }, { onConflict: 'driver_id' });

    console.log(`Novo motorista registrado: ${uid} | ${fullName}`);

    return jsonResponse({
      success: true,
      driver_id: uid,
      status: 'waiting_documents',
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('register-driver error:', msg);
    return errorResponse(msg);
  }
});
