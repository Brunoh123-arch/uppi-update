import 'package:flutter/services.dart';

class UppiFeedback {
  UppiFeedback._();

  /// Alerta leve para quando o motorista aceita a viagem
  static Future<void> triggerLight() async {
    try {
      await HapticFeedback.lightImpact();
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {
      // Ignorar erros silenciosamente em plataformas sem suporte
    }
  }

  /// Alerta médio para quando o motorista chega ao local
  static Future<void> triggerMedium() async {
    try {
      await HapticFeedback.mediumImpact();
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {
      // Ignorar
    }
  }

  /// Alerta forte celebrativo para quando a viagem inicia
  static Future<void> triggerSuccess() async {
    try {
      await HapticFeedback.vibrate();
    } catch (_) {
      // Ignorar
    }
  }
}

/// Helper global de gerenciamento de economia de bateria (Fase 27)
class UppiPerformance {
  UppiPerformance._();

  static bool batterySaverMode = false;
}
