import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_login_screen.dart';
import '../layout/main_dashboard_layout.dart';

/// Gate que escuta a sessão do Supabase e redireciona
/// entre Login e Dashboard automaticamente.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _sub;
  bool _isLoggedIn = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // Verifica sessão existente
    final session = Supabase.instance.client.auth.currentSession;
    _isLoggedIn = session != null;
    _ready = true;

    // Escuta mudanças de auth
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      setState(() {
        _isLoggedIn = data.session != null;
      });
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _isLoggedIn ? const MainDashboardLayout() : const AdminLoginScreen();
  }
}
