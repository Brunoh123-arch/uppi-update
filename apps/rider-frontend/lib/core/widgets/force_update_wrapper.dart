import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Wrapper que verifica se o app está na versão mínima exigida pelo backend.
/// Se não estiver, exibe um dialog BLOQUEANTE que só permite atualizar.
///
/// Uso: envolver o MaterialApp.router com [ForceUpdateWrapper].
///
/// ```dart
/// child: ForceUpdateWrapper(
///   appType: 'rider', // ou 'driver'
///   child: MaterialApp.router(...),
/// )
/// ```
class ForceUpdateWrapper extends StatefulWidget {
  const ForceUpdateWrapper({
    super.key,
    required this.appType,
    required this.child,
  });

  /// 'rider' ou 'driver' — determina qual coluna do app_settings verificar
  final String appType;
  final Widget child;

  @override
  State<ForceUpdateWrapper> createState() => _ForceUpdateWrapperState();
}

class _ForceUpdateWrapperState extends State<ForceUpdateWrapper> {
  bool _checked = false;
  bool _updateRequired = false;
  String _storeUrl = '';
  String _currentVersion = '';
  String _minVersion = '';

  @override
  void initState() {
    super.initState();
    _checkVersion();
  }

  Future<void> _checkVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version;

      // Busca configurações do Supabase (sem autenticação — usando anon key é seguro pra isso)
      final colMin = 'min_app_version_${widget.appType}';
      // Detectar plataforma corretamente (não pelo packageName)
      final colStore = kIsWeb
          ? 'store_url_android'
          : (defaultTargetPlatform == TargetPlatform.iOS ? 'store_url_ios' : 'store_url_android');

      final response = await Supabase.instance.client
          .from('app_settings')
          .select('$colMin, store_url_android, store_url_ios')
          .eq('key', 'app_name')
          .maybeSingle();

      if (response == null) return;

      _minVersion = response[colMin]?.toString() ?? '1.0.0';
      _storeUrl = response[colStore]?.toString() ?? response['store_url_android']?.toString() ?? '';

      if (_isOutdated(_currentVersion, _minVersion)) {
        if (mounted) setState(() { _updateRequired = true; });
      }
    } catch (e) {
      debugPrint('[ForceUpdate] Erro ao verificar versão: $e');
    } finally {
      if (mounted) setState(() { _checked = true; });
    }
  }

  /// Compara versões semânticas (major.minor.patch)
  bool _isOutdated(String current, String minimum) {
    try {
      final c = current.split('.').map(int.parse).toList();
      final m = minimum.split('.').map(int.parse).toList();
      while (c.length < 3) {
        c.add(0);
      }
      while (m.length < 3) {
        m.add(0);
      }
      for (int i = 0; i < 3; i++) {
        if (c[i] < m[i]) return true;
        if (c[i] > m[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openStore() async {
    if (_storeUrl.isNotEmpty) {
      final uri = Uri.parse(_storeUrl);
      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Enquanto não verificou, mostra o app normalmente (evita flash de loading)
    if (!_checked || !_updateRequired) return widget.child;

    // Dialog bloqueante sobreposto ao app
    return Stack(
      children: [
        widget.child,
        // Overlay opaco que bloqueia interação
        Positioned.fill(
          child: Material(
            color: Colors.black87,
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 32,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Ícone
                        Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.system_update_rounded,
                            size: 40,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Atualização Necessária',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Sua versão ($_currentVersion) está desatualizada. '
                          'Atualize para a versão $_minVersion ou superior para continuar usando o Uppi.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _openStore,
                            icon: const Icon(Icons.download_rounded),
                            label: const Text(
                              'Atualizar Agora',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Theme.of(context).colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Esta versão não é mais suportada.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
