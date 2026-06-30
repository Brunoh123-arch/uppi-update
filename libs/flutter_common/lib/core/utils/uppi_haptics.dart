import 'package:flutter/services.dart';

/// Utilitário premium e futurista para feedback tátil (Haptics) nos apps Uppi.
/// Combina sequências de micro-vibrações de alta fidelidade para criar sensações mecânicas realistas.
class UppiHaptics {
  UppiHaptics._();

  /// 🎯 Clique de seleção ultraleve (seleção de itens, abas, toggles rápidos)
  static Future<void> selection() async {
    await HapticFeedback.selectionClick();
  }

  /// ⚙️ Efeito de clique físico/mecânico do futuro (Mechanical Click)
  /// Simula o acionamento de um botão físico de alta precisão.
  static Future<void> mechanicalClick() async {
    await HapticFeedback.selectionClick();
    await Future.delayed(const Duration(milliseconds: 50));
    await HapticFeedback.lightImpact();
  }

  /// 🌊 Onda tátil de sucesso tridimensional (Success Wave)
  /// Perfeito para confirmação de transações ou viagens bem-sucedidas.
  static Future<void> successWave() async {
    await HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 60));
    await HapticFeedback.selectionClick();
    await Future.delayed(const Duration(milliseconds: 60));
    await HapticFeedback.mediumImpact();
  }

  /// 🚗 Batimento do Motor (Engine Heartbeat)
  /// Especial para o motorista. Dá o feedback sensorial de partida/aceite de corrida.
  static Future<void> engineHeartbeat() async {
    await HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.lightImpact();
  }

  /// ⚠️ Alerta denso de erro ou recusa
  /// Vibração pesada informando falha de validação ou recusa de ação.
  static Future<void> errorAlert() async {
    await HapticFeedback.vibrate();
  }
}
