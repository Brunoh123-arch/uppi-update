import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse();

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401);

    const supa = getServiceClient();

    // Buscar configurações de split das app_settings
    const { data: settings } = await supa
      .from('app_settings')
      .select('key, value')
      .in('key', ['platform_fee_percent', 'driver_share_percent', 'min_platform_fee']);

    const config: Record<string, string> = {};
    settings?.forEach((s: any) => { config[s.key] = s.value; });

    const platformFeePercent = Number(config['platform_fee_percent']) || 20;
    const driverSharePercent = Number(config['driver_share_percent']) || 80;
    const minPlatformFee = Number(config['min_platform_fee']) || 2.0;

    return jsonResponse({
      platform_fee_percent: platformFeePercent,
      driver_share_percent: driverSharePercent,
      min_platform_fee: minPlatformFee,
    });

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    return errorResponse(msg);
  }
});
