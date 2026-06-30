import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = true;

  // 1. Tenta obter credenciais injetadas via --dart-define
  const String defineSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const String defineAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  String? supabaseUrl = defineSupabaseUrl.isNotEmpty ? defineSupabaseUrl : null;
  String? anonKey = defineAnonKey.isNotEmpty ? defineAnonKey : null;

  // 2. Se não estiverem definidas por --dart-define, carrega via dotenv (fallback de desenvolvimento)
  if (supabaseUrl == null || anonKey == null) {
    try {
      const String env = String.fromEnvironment('ENV', defaultValue: 'prod');
      if (env == 'staging') {
        await dotenv.load(fileName: '.env.staging');
      } else {
        await dotenv.load(fileName: '.env');
      }
      supabaseUrl ??= dotenv.maybeGet('SUPABASE_URL');
      anonKey ??= dotenv.maybeGet('SUPABASE_ANON_KEY');
    } catch (e) {
      debugPrint("Failed to load .env file: $e");
    }
  }

  if (supabaseUrl != null && supabaseUrl.isNotEmpty) {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: anonKey ?? '',
    );
  }

  runApp(const AdminPanelApp());
}
