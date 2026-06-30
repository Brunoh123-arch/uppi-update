import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _radiusCtrl = TextEditingController();
  final _commissionCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController();
  final _surgeCtrl = TextEditingController();

  String _mapProvider = 'googleMaps';
  bool isLoading = true;
  bool isSaving = false;
  bool _isRaining = false;
  bool _cashEnabled = true;
  bool _walletEnabled = true;
  String? configId;
  final _googleMapKeyCtrl = TextEditingController();
  final _googleMapKey2Ctrl = TextEditingController();
  final _googleMapKey3Ctrl = TextEditingController();
  final _mapboxTokenCtrl = TextEditingController();
  final _twilioAccountSidCtrl = TextEditingController();
  final _twilioAuthTokenCtrl = TextEditingController();
  final _twilioMessagingServiceSidCtrl = TextEditingController();
  final _twilioPhoneNumberCtrl = TextEditingController();
  final _turnstileSecretCtrl = TextEditingController();
  bool _obscureTwilioAuthToken = true;
  bool _obscureTurnstileSecret = true;
  
  RealtimeChannel? _settingsChannel;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _startRealtimeListeners();
  }

  void _startRealtimeListeners() {
    _settingsChannel = Supabase.instance.client
        .channel('app_settings_events')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_settings',
          callback: (payload) {
            // Atualiza silenciosamente sem a "bola de carregando"
            _loadSettings(silent: true);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _settingsChannel?.unsubscribe();
    _radiusCtrl.dispose();
    _commissionCtrl.dispose();
    _currencyCtrl.dispose();
    _surgeCtrl.dispose();
    _googleMapKeyCtrl.dispose();
    _googleMapKey2Ctrl.dispose();
    _googleMapKey3Ctrl.dispose();
    _mapboxTokenCtrl.dispose();
    _twilioAccountSidCtrl.dispose();
    _twilioAuthTokenCtrl.dispose();
    _twilioMessagingServiceSidCtrl.dispose();
    _twilioPhoneNumberCtrl.dispose();
    _turnstileSecretCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings({bool silent = false}) async {
    if (!silent) setState(() => isLoading = true);
    try {
      final res = await Supabase.instance.client
          .from('app_settings')
          .select('key, value');
      
      final Map<String, String> settings = {};
      for (final row in res) {
        settings[row['key']?.toString() ?? ''] = row['value']?.toString() ?? '';
      }

      if (!isSaving) {
        _radiusCtrl.text = settings['driver_search_radius'] ?? '10';
        _commissionCtrl.text = settings['commission_rate'] ?? '15';
        _currencyCtrl.text = settings['currency'] ?? 'BRL';
        _mapProvider = settings['map_provider'] ?? 'googleMaps';
        _surgeCtrl.text = settings['global_surge_multiplier'] ?? '1.0';
        _googleMapKeyCtrl.text = settings['google_map_api_key'] ?? '';
        _googleMapKey2Ctrl.text = settings['google_map_api_key_2'] ?? '';
        _googleMapKey3Ctrl.text = settings['google_map_api_key_3'] ?? 'AIzaSyCMk2sR6MgAIoMnsviLMQ38nBNJoWfpnLQ';
        _mapboxTokenCtrl.text = settings['mapbox_token'] ?? '';
        _twilioAccountSidCtrl.text = settings['twilio_account_sid'] ?? '';
        _twilioAuthTokenCtrl.text = settings['twilio_auth_token'] ?? '';
        _twilioMessagingServiceSidCtrl.text = settings['twilio_messaging_service_sid'] ?? '';
        _twilioPhoneNumberCtrl.text = settings['twilio_phone_number'] ?? '';
        _turnstileSecretCtrl.text = settings['turnstile_secret_key'] ?? '';
        _isRaining = settings['is_raining'] == 'true';
        _cashEnabled = settings['cash_enabled'] != 'false';
        _walletEnabled = settings['wallet_enabled'] != 'false';
      }
    } catch (e) {
      debugPrint('Erro ao carregar settings: $e');
    } finally {
      if (mounted && !silent) setState(() => isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => isSaving = true);
    try {
      final entries = {
        'driver_search_radius': (int.tryParse(_radiusCtrl.text) ?? 10).toString(),
        'commission_rate': (double.tryParse(_commissionCtrl.text) ?? 15.0).toString(),
        'currency': _currencyCtrl.text.toUpperCase(),
        'map_provider': _mapProvider,
        'global_surge_multiplier': (double.tryParse(_surgeCtrl.text) ?? 1.0).toString(),
        'google_map_api_key': _googleMapKeyCtrl.text,
        'google_map_api_key_2': _googleMapKey2Ctrl.text,
        'google_map_api_key_3': _googleMapKey3Ctrl.text,
        'mapbox_token': _mapboxTokenCtrl.text,
        'twilio_account_sid': _twilioAccountSidCtrl.text,
        'twilio_auth_token': _twilioAuthTokenCtrl.text,
        'twilio_messaging_service_sid': _twilioMessagingServiceSidCtrl.text,
        'twilio_phone_number': _twilioPhoneNumberCtrl.text,
        'turnstile_secret_key': _turnstileSecretCtrl.text,
        'is_raining': _isRaining.toString(),
        'cash_enabled': _cashEnabled.toString(),
        'wallet_enabled': _walletEnabled.toString(),
      };

      // Upsert each key-value pair individually
      for (final entry in entries.entries) {
        await Supabase.instance.client
            .from('app_settings')
            .upsert({
              'key': entry.key,
              'value': entry.value,
              'updated_at': DateTime.now().toIso8601String(),
            }, onConflict: 'key');
      }

      // Update the columnar fields in global_config row to keep it in sync with Edge Functions
      await Supabase.instance.client
          .from('app_settings')
          .update({
            'driver_search_radius': int.tryParse(_radiusCtrl.text) ?? 10,
            'commission_rate': double.tryParse(_commissionCtrl.text) ?? 15.0,
            'currency': _currencyCtrl.text.toUpperCase(),
            'map_provider': _mapProvider,
            'global_surge_multiplier': double.tryParse(_surgeCtrl.text) ?? 1.0,
            'google_map_api_key': _googleMapKeyCtrl.text,
            'twilio_account_sid': _twilioAccountSidCtrl.text,
            'twilio_auth_token': _twilioAuthTokenCtrl.text,
            'twilio_messaging_service_sid': _twilioMessagingServiceSidCtrl.text,
            'twilio_phone_number': _twilioPhoneNumberCtrl.text,
            'cash_enabled': _cashEnabled,
            'wallet_enabled': _walletEnabled,
          })
          .eq('key', 'global_config');

      // Audit trail for settings changes
      final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'settings_updated',
        'target_resource_id': 'app_settings',
        'details': entries,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurações salvas com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 80,
          padding: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Configurações Globais (Settings)',
              style: GoogleFonts.outfit(
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Card(
                              color: Theme.of(context).colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.tune, color: Colors.blueAccent),
                                        SizedBox(width: 16),
                                        Text(
                                          'Parâmetros do Sistema',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 32),
                                    TextField(
                                      controller: _radiusCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText:
                                            'Raio de Busca de Motoristas (KM)',
                                        helperText:
                                            'A distância máxima para enviar corridas aos motoristas ativos.',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    TextField(
                                      controller: _commissionCtrl,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Taxa Padrão da Plataforma (%)',
                                        helperText:
                                            'Ex: 15.0 significa que 15% do valor da corrida fica com a plataforma.',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    TextField(
                                      controller: _currencyCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Moeda Padrão',
                                        helperText: 'Ex: BRL, USD, EUR.',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    DropdownButtonFormField<String>(
                                      initialValue: _mapProvider,
                                      decoration: const InputDecoration(
                                        labelText: 'Provedor de Mapa Global',
                                        helperText:
                                            'Aplica a mudança de mapa instantaneamente no App do Passageiro e Motorista.',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'googleMaps',
                                          child: Text('Google Maps'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'openStreetMaps',
                                          child: Text('OpenStreetMap'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'mapBox',
                                          child: Text('MapBox'),
                                        ),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() => _mapProvider = val);
                                        }
                                      },
                                    ),
                                    const SizedBox(height: 24),
                                    TextField(
                                      controller: _googleMapKeyCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Chave de API do Google Maps',
                                        helperText: 'Necessário se o provedor escolhido for Google Maps.',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    TextField(
                                      controller: _googleMapKey2Ctrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Chave de API do Google Maps 2 (Opcional)',
                                        helperText: 'Opcional. Uma chave secundária para o App (iOS, etc).',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    TextField(
                                      controller: _googleMapKey3Ctrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Chave de API do Google Maps 3 (Opcional)',
                                        helperText: 'Opcional. Uma terceira chave de API (rotatividade/fallbacks).',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    TextField(
                                      controller: _mapboxTokenCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Token do Mapbox',
                                        helperText: 'Necessário se o provedor escolhido for MapBox.',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    TextField(
                                      controller: _surgeCtrl,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: InputDecoration(
                                        labelText: 'Tarifa Dinâmica Global (Ajuste Administrativo)',
                                        helperText: 'Multiplicador de preço (Ex: 1.0 = Normal, 2.5 = 2.5x mais caro). Afeta todas as corridas instantaneamente.',
                                        border: const OutlineInputBorder(),
                                        filled: true,
                                        fillColor: Colors.redAccent.withOpacity(0.1),
                                        prefixIcon: const Icon(Icons.flash_on, color: Colors.redAccent),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    SwitchListTile(
                                      title: const Text(
                                        'Habilitar Pagamento em Dinheiro (Cash) 💵',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: const Text(
                                        'Permite que passageiros paguem as corridas diretamente em dinheiro ao motorista.',
                                      ),
                                      value: _cashEnabled,
                                      activeThumbColor: Colors.blueAccent,
                                      secondary: const Icon(Icons.money, color: Colors.blueAccent),
                                      onChanged: (bool value) {
                                        setState(() {
                                          _cashEnabled = value;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 24),
                                    SwitchListTile(
                                      title: const Text(
                                        'Habilitar Pagamento via Carteira (Wallet) 💳',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: const Text(
                                        'Permite que passageiros paguem as corridas usando o saldo de sua carteira.',
                                      ),
                                      value: _walletEnabled,
                                      activeThumbColor: Colors.blueAccent,
                                      secondary: const Icon(Icons.account_balance_wallet, color: Colors.blueAccent),
                                      onChanged: (bool value) {
                                        setState(() {
                                          _walletEnabled = value;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 24),
                                    SwitchListTile(
                                      title: const Text(
                                        'Ativar Promoção: Taxa Zero na Chuva 🌧️',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: const Text(
                                        'Exibe uma faixa promocional em tempo real no app do passageiro informando sobre a Taxa Zero sob chuva.',
                                      ),
                                      value: _isRaining,
                                      activeThumbColor: Colors.blueAccent,
                                      secondary: const Icon(Icons.umbrella, color: Colors.blueAccent),
                                      onChanged: (bool value) {
                                        setState(() {
                                          _isRaining = value;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 40),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 56,
                                      child: ElevatedButton.icon(
                                        onPressed: isSaving ? null : _saveSettings,
                                        icon: isSaving ? const SizedBox() : const Icon(Icons.save),
                                        label: isSaving
                                            ? const SizedBox(
                                                height: 24,
                                                width: 24,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                              )
                                            : const Text('Salvar Configurações'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.greenAccent,
                                          foregroundColor: Colors.black,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 32),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Card(
                              color: Theme.of(context).colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(32.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.security,
                                          color: Colors.redAccent,
                                        ),
                                        SizedBox(width: 16),
                                        Text(
                                          'Aviso Crítico',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 24),
                                    Text(
                                      'Alterações nestes parâmetros afetam imediatamente o despacho de corridas e o faturamento do sistema para todas as cidades.',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 16,
                                        height: 1.5,
                                      ),
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Certifique-se de avisar a base de motoristas sobre mudanças em comissões (Provider Share) via aba de Push Marketing.',
                                      style: TextStyle(
                                        color: Colors.orangeAccent,
                                        fontSize: 16,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            Card(
                              color: Theme.of(context).colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.settings_phone,
                                          color: Colors.blueAccent,
                                        ),
                                        const SizedBox(width: 16),
                                        Text(
                                          'Configurações do Portal Twilio (SMS & Voz)',
                                          style: GoogleFonts.outfit(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 32),
                                    TextField(
                                      controller: _twilioAccountSidCtrl,
                                      decoration: InputDecoration(
                                        labelText: 'Twilio Account SID',
                                        labelStyle: GoogleFonts.outfit(color: Colors.white70),
                                        border: const OutlineInputBorder(),
                                        prefixIcon: const Icon(Icons.vpn_key, color: Colors.blueAccent),
                                      ),
                                      style: GoogleFonts.outfit(color: Colors.white),
                                    ),
                                    const SizedBox(height: 24),
                                    TextField(
                                      controller: _twilioAuthTokenCtrl,
                                      obscureText: _obscureTwilioAuthToken,
                                      decoration: InputDecoration(
                                        labelText: 'Twilio Auth Token',
                                        labelStyle: GoogleFonts.outfit(color: Colors.white70),
                                        border: const OutlineInputBorder(),
                                        prefixIcon: const Icon(Icons.lock, color: Colors.blueAccent),
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _obscureTwilioAuthToken
                                                ? Icons.visibility_off
                                                : Icons.visibility,
                                            color: Colors.white70,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _obscureTwilioAuthToken = !_obscureTwilioAuthToken;
                                            });
                                          },
                                        ),
                                      ),
                                      style: GoogleFonts.outfit(color: Colors.white),
                                    ),
                                    const SizedBox(height: 24),
                                    TextField(
                                      controller: _twilioMessagingServiceSidCtrl,
                                      decoration: InputDecoration(
                                        labelText: 'Twilio Messaging Service SID',
                                        labelStyle: GoogleFonts.outfit(color: Colors.white70),
                                        border: const OutlineInputBorder(),
                                        prefixIcon: const Icon(Icons.message, color: Colors.blueAccent),
                                      ),
                                      style: GoogleFonts.outfit(color: Colors.white),
                                    ),
                                    const SizedBox(height: 24),
                                    TextField(
                                      controller: _twilioPhoneNumberCtrl,
                                      decoration: InputDecoration(
                                        labelText: 'Número de Telefone Twilio',
                                        labelStyle: GoogleFonts.outfit(color: Colors.white70),
                                        border: const OutlineInputBorder(),
                                        helperText: 'Ex: +1234567890',
                                        helperStyle: GoogleFonts.outfit(color: Colors.white54),
                                        prefixIcon: const Icon(Icons.phone, color: Colors.blueAccent),
                                      ),
                                      style: GoogleFonts.outfit(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            Card(
                              color: Theme.of(context).colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.security,
                                          color: Colors.orangeAccent,
                                        ),
                                        const SizedBox(width: 16),
                                        Text(
                                          'Anti-Bot / CAPTCHA (Cloudflare Turnstile)',
                                          style: GoogleFonts.outfit(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Protege o envio de SMS OTP contra bots e ataques de SMS bombing. Obtenha a chave em dash.cloudflare.com → Turnstile.',
                                      style: GoogleFonts.outfit(
                                        color: Colors.white54,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    TextField(
                                      controller: _turnstileSecretCtrl,
                                      obscureText: _obscureTurnstileSecret,
                                      decoration: InputDecoration(
                                        labelText: 'Turnstile Secret Key',
                                        labelStyle: GoogleFonts.outfit(color: Colors.white70),
                                        border: const OutlineInputBorder(),
                                        prefixIcon: const Icon(Icons.vpn_key, color: Colors.orangeAccent),
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _obscureTurnstileSecret
                                                ? Icons.visibility_off
                                                : Icons.visibility,
                                            color: Colors.white70,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _obscureTurnstileSecret = !_obscureTurnstileSecret;
                                            });
                                          },
                                        ),
                                      ),
                                      style: GoogleFonts.outfit(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
