import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:safe_device/safe_device.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uppi_motorista/core/presentation/blocked_device_screen.dart';

class SecurityGuard {
  /// Executa verificações de integridade do dispositivo (Root/Jailbreak/Emulador)
  /// Se alguma violação for detectada, bloqueia o perfil do motorista via RPC,
  /// realiza logout e redireciona para a tela de bloqueio impenetrável.
  static Future<bool> checkIntegrity(BuildContext context) async {
    if (kDebugMode || kIsWeb) {
      debugPrint('[SecurityGuard] Ignorando verificação de integridade do dispositivo em modo de depuração ou Web.');
      return true;
    }

    bool isJailBroken = await SafeDevice.isJailBroken;
    bool isRealDevice = await SafeDevice.isRealDevice;


    if (isJailBroken || !isRealDevice) {
      final type = isJailBroken ? 'root_jailbreak' : 'emulator';

      try {
        final currentUser = Supabase.instance.client.auth.currentUser;
        if (currentUser != null) {
          bool isDevMode = await SafeDevice.isDevelopmentModeEnable;
          // 1. Reporta a ameaça detectada para a tabela suspicious_devices e bloqueia o motorista
          await Supabase.instance.client.rpc('rpc_flag_suspicious_device', params: {
            'p_threat_type': type,
            'p_details': {
              'developer_mode': isDevMode,
              'timestamp': DateTime.now().toIso8601String(),
            }
          });
        }
      } catch (_) {
        // Tratado silenciosamente para evitar burlas no fluxo se falhar a rede
      }

      try {
        // 2. Desloga o usuário permanentemente do Supabase
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}

      // 3. Empurra a tela de bloqueio sem possibilidade de retornar (Navigator.pushAndRemoveUntil)
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => BlockedDeviceScreen(threatType: type),
          ),
          (route) => false,
        );
      }
      return false;
    }
    return true;
  }
}
