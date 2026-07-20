import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_common/l10n/messages.dart';

import 'auth/auth_gate.dart';

final ValueNotifier<Locale> adminLocaleNotifier = ValueNotifier<Locale>(const Locale('pt'));

class AdminPanelApp extends StatelessWidget {
  const AdminPanelApp({super.key});

  bool _isSupabaseInitialized() {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSupabase = _isSupabaseInitialized();

    return ValueListenableBuilder<Locale>(
      valueListenable: adminLocaleNotifier,
      builder: (context, currentLocale, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Uppi - Painel Admin',
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF096EFF),
              secondary: Color(0xFFEA740C),
              surface: Color(0xFF1E293B),
              onPrimary: Color(0xFFFFFFFF),
              onSecondary: Color(0xFFFFFFFF),
              onSurface: Color(0xFFE2E8F0),
              tertiary: Color(0xFF6C9F12),
              error: Color(0xFFDE3730),
            ),
            textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
          ),
          locale: currentLocale,
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.supportedLocales,
          home: hasSupabase 
              ? const AuthGate() 
              : const _SupabaseErrorScreen(),
        );
      },
    );
  }
}

class _SupabaseErrorScreen extends StatelessWidget {
  const _SupabaseErrorScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDE3730), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.report_problem_rounded,
                  color: Color(0xFFDE3730),
                  size: 64,
                ),
                const SizedBox(height: 24),
                Text(
                  'Falha de Inicialização',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'O ecossistema Supabase não pôde ser inicializado no Painel Admin. '
                  'Isso acontece porque as credenciais não foram injetadas via --dart-define '
                  'e o arquivo ".env" correspondente está ausente ou incompleto.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    height: 1.5,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  child: const Text(
                    'Dica: Configure SUPABASE_URL e SUPABASE_ANON_KEY via --dart-define na compilação, ou crie um arquivo ".env" local na pasta do admin_panel para desenvolvimento.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFEA740C),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
