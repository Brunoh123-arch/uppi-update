import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'map_injector.dart';

class MapConfig {
  static String? _cachedApiKey;

  static Future<String> getGoogleMapsApiKey() async {
    if (_cachedApiKey != null) return _cachedApiKey!;

    String? apiKey;
    try {
      // 1. Tenta buscar da tabela app_settings do Supabase com timeout de 3 segundos
      final res = await Supabase.instance.client
          .from('app_settings')
          .select('value')
          .eq('key', 'google_map_api_key')
          .maybeSingle()
          .timeout(const Duration(seconds: 3));
      
      apiKey = res?['value']?.toString();
    } catch (e) {
      debugPrint('Timeout ou erro ao carregar google_map_api_key do Supabase: $e');
    }

    // 2. Se não encontrar, tenta ler das chaves locais do .env
    if (apiKey == null || apiKey.isEmpty) {
      apiKey = dotenv.maybeGet('GOOGLE_MAP_API_KEY') ??
               dotenv.maybeGet('GOOGLE_MAPS_API_KEY');
    }

    // 3. Fallback final para chaves padrão
    if (apiKey == null || apiKey.isEmpty) {
      apiKey = 'AIzaSyAHjeUov0-VHb3AXOmWTb5xBWy00Btdets'; // Chave fallback local
    }

    _cachedApiKey = apiKey;
    return apiKey;
  }

  static Future<void> initializeMap() async {
    final apiKey = await getGoogleMapsApiKey();
    if (kIsWeb) {
      try {
        await injectGoogleMaps(apiKey).timeout(const Duration(seconds: 7));
        debugPrint('Google Maps script injetado com sucesso no Web.');
      } catch (e) {
        debugPrint('Erro ao injetar script do Google Maps no Web: $e');
      }
    }
  }
}
