/**
 * ADMIN-ACTIONS — Ações administrativas consolidadas
 * Migrado de: functions/src/admin/admin.functions.ts
 * 
 * Endpoints suportados (via "action" no body):
 * - updateDriverStatus: Aprovar/rejeitar/bloquear motorista
 * - zeroDriverWallet: Zerar carteira do motorista
 * - setDriverCommission: Definir comissão individual
 * - grantCommissionExemption: Conceder isenção de comissão
 * - updatePlatformCommission: Comissão global
 * - updateMercadoPago: Configurar credenciais MP
 * - updateConfig: Atualizar config geral
 * - getConfig: Buscar config geral
 * - updateOrderStatus: Atualizar status de corrida
 */

import { getServiceClient, getSupabaseUser } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse, optionsResponse } from '../_shared/cors.ts';
import { adminLimiter } from '../_shared/rate-limiter.ts';

/** Verifica se o user é admin */
async function requireAdmin(
  supa: ReturnType<typeof getServiceClient>,
  userId: string,
): Promise<void> {
  const { data } = await supa.from('admins').select('role').eq('id', userId).maybeSingle();
  if (!data) throw new Error('Acesso negado — requer role admin');
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return optionsResponse(req);

  try {
    const user = await getSupabaseUser(req);
    if (!user) return errorResponse('Não autenticado', 401, req);

    if (adminLimiter.isRateLimited(user.id)) {
      return errorResponse('Limite de ações administrativas atingido. Aguarde um minuto.', 429, req);
    }

    const supa = getServiceClient();
    await requireAdmin(supa, user.id);

    const body = await req.json();
    const { action, ...params } = body.args ?? body;

    if (!action) return errorResponse('action é obrigatório', 400, req);

    switch (action) {
      // ── Motorista ───────────────────────────────────────────────────
      case 'updateDriverStatus': {
        const { driverId, status } = params;
        if (!driverId) return errorResponse('driverId é obrigatório', 400, req);
        await supa.from('profiles').update({ status }).eq('id', driverId);
        await supa.from('driver_locations').update({ status }).eq('driver_id', driverId);
        return jsonResponse({ success: true }, 200, req);
      }

      case 'zeroDriverWallet': {
        const { driverId } = params;
        if (!driverId) return errorResponse('driverId é obrigatório', 400, req);

        const { data: walletData } = await supa.from('wallets').select('balance').eq('user_id', driverId).single();
        const currentBal = Number(walletData?.balance) || 0;

        await supa.rpc('increment_wallet', { target_user_id: driverId, amount_to_add: -currentBal });

        await supa.from('wallet_transactions').insert({
          user_id: driverId,
          amount: 0,
          type: 'admin_reset',
          description: 'Saldo zerado pelo admin',
          status: 'completed',
        });
        return jsonResponse({ success: true }, 200, req);
      }

      case 'setDriverCommission': {
        const { driverIds, commissionPercentage } = params;
        if (!driverIds?.length) return errorResponse('driverIds é obrigatório', 400, req);
        if (commissionPercentage < 0 || commissionPercentage > 100) {
          return errorResponse('Comissão deve ser entre 0 e 100', 400, req);
        }
        for (const driverId of driverIds) {
          await supa.from('profiles').update({
            commission_percentage: commissionPercentage,
          }).eq('id', driverId);
        }
        return jsonResponse({ success: true, updated: driverIds.length, commissionPercentage }, 200, req);
      }

      case 'grantCommissionExemption': {
        const { driverIds, exemptionDays } = params;
        if (!driverIds?.length) return errorResponse('driverIds é obrigatório', 400, req);
        if (!exemptionDays || exemptionDays < 1 || exemptionDays > 365) {
          return errorResponse('Dias de isenção deve ser entre 1 e 365', 400, req);
        }
        const exemptUntil = new Date(Date.now() + exemptionDays * 24 * 60 * 60 * 1000);
        for (const driverId of driverIds) {
          await supa.from('profiles').update({
            commission_exempt_until: exemptUntil.toISOString(),
          }).eq('id', driverId);
        }
        return jsonResponse({
          success: true,
          updated: driverIds.length,
          exempt_until: exemptUntil.toISOString(),
          exemptionDays,
        }, 200, req);
      }

      case 'updatePlatformCommission': {
        const { commissionPercentage } = params;
        if (commissionPercentage < 0 || commissionPercentage > 100) {
          return errorResponse('Comissão deve ser entre 0 e 100', 400, req);
        }
        // Salva em app_settings (fonte única de verdade)
        await supa.from('app_settings').upsert({
          key: 'commission_rate',
          value: String(commissionPercentage),
        });

        return jsonResponse({ success: true, commissionPercentage }, 200, req);
      }

      // ── Config ──────────────────────────────────────────────────────
      case 'updateConfig': {
        const { key, value } = params;
        if (!key) return errorResponse('key é obrigatório', 400, req);

        // Allowlist de chaves permitidas para atualização geral (impede sobrescrever credenciais sensíveis)
        const allowedKeys = [
          'commission_rate', 
          'map_provider', 
          'google_map_api_key', 
          'global_surge_multiplier', 
          'currency', 
          'min_payout_amount', 
          'support_email',
          'app_name',
          'force_update_rider_version',
          'force_update_driver_version',
          'osrm_routing_url',
          'driver_search_radius'
        ];

        if (!allowedKeys.includes(key)) {
          return errorResponse(`Alteração não autorizada: a chave de configuração '${key}' não é permitida para alteração geral.`, 400, req);
        }

        await supa.from('app_settings').upsert({
          key: key,
          value: String(value),
        });
        return jsonResponse({ success: true }, 200, req);
      }

      case 'getConfig': {
        const { data } = await supa.from('app_settings').select('key, value');
        const settings: Record<string, string> = {};
        data?.forEach((row: any) => {
          settings[row.key] = row.value;
        });
        return jsonResponse(settings, 200, req);
      }

      // ── Mercado Pago ────────────────────────────────────────────────
      case 'updateMercadoPago': {
        const { accessToken, publicKey, webhookSecret, sandbox } = params;
        const mpUpdates = [];
        if (accessToken) mpUpdates.push({ key: 'mp_access_token', value: String(accessToken) });
        if (publicKey) mpUpdates.push({ key: 'mp_public_key', value: String(publicKey) });
        if (webhookSecret) mpUpdates.push({ key: 'mp_webhook_secret', value: String(webhookSecret) });
        if (sandbox !== undefined) mpUpdates.push({ key: 'mp_sandbox', value: String(sandbox) });
        
        if (mpUpdates.length > 0) {
          await supa.from('app_settings').upsert(mpUpdates);
        }
        return jsonResponse({ success: true }, 200, req);
      }

      // ── Corrida ─────────────────────────────────────────────────────
      case 'updateOrderStatus': {
        const { rideId, orderId, status } = params;
        const id = rideId || orderId;
        if (!id || !status) return errorResponse('rideId e status são obrigatórios', 400, req);
        await supa.from('rides').update({ status }).eq('id', id);
        return jsonResponse({ success: true, status }, 200, req);
      }

      // ── Gateways de Pagamento ────────────────────────────────────────
      case 'createPaymentGateway': {
        const { name, external_url, is_active } = params;
        if (!name) return errorResponse('name é obrigatório', 400, req);
        const { data, error } = await supa
          .from('payment_gateways')
          .insert({ name, title: name, external_url: external_url || null, is_active: is_active ?? true })
          .select()
          .single();
        if (error) return errorResponse(error.message, 500, req);

        await supa.from('admin_audit_log').insert({
          admin_id: user.id,
          action_type: 'payment_gateway_created',
          target_resource_id: data.id?.toString() ?? 'new_gateway',
          details: { name, external_url, is_active },
        });
        return jsonResponse({ success: true, gateway: data }, 200, req);
      }

      case 'updatePaymentGateway': {
        const { gatewayId, name, external_url, is_active } = params;
        if (!gatewayId) return errorResponse('gatewayId é obrigatório', 400, req);
        const updates: Record<string, unknown> = {};
        if (name !== undefined) { updates.name = name; updates.title = name; }
        if (external_url !== undefined) updates.external_url = external_url;
        if (is_active !== undefined) updates.is_active = is_active;

        const { error } = await supa.from('payment_gateways').update(updates).eq('id', gatewayId);
        if (error) return errorResponse(error.message, 500, req);

        await supa.from('admin_audit_log').insert({
          admin_id: user.id,
          action_type: 'payment_gateway_updated',
          target_resource_id: gatewayId,
          details: updates,
        });
        return jsonResponse({ success: true }, 200, req);
      }

      case 'deletePaymentGateway': {
        const { gatewayId } = params;
        if (!gatewayId) return errorResponse('gatewayId é obrigatório', 400, req);
        const { error } = await supa.from('payment_gateways').delete().eq('id', gatewayId);
        if (error) return errorResponse(error.message, 500, req);

        await supa.from('admin_audit_log').insert({
          admin_id: user.id,
          action_type: 'payment_gateway_deleted',
          target_resource_id: gatewayId,
        });
        return jsonResponse({ success: true }, 200, req);
      }

      default:
        return errorResponse(`Ação desconhecida: ${action}`, 400, req);
    }

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('admin-actions error:', msg);
    return errorResponse(msg, msg.includes('admin') ? 403 : 500, req);
  }
});
