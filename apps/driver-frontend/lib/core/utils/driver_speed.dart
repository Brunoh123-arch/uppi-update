import 'package:flutter/foundation.dart';

/// Canal global da velocidade atual do motorista (km/h).
///
/// O GPS já reporta a velocidade em cada atualização de posição; aqui só
/// expomos esse valor para a UI (velocímetro) sem precisar tocar na entidade
/// [DriverLocation] nem em codegen. Segue o mesmo padrão dos outros notifiers
/// globais do app (ex: activeRouteNotifier, isMinimizedNotifier).
class DriverSpeed {
  DriverSpeed._();

  /// Velocidade atual em km/h. 0 quando parado ou indisponível.
  static final ValueNotifier<double> kmh = ValueNotifier<double>(0);

  /// Atualiza a partir da velocidade do GPS em metros/segundo.
  /// Valores inválidos (negativos/NaN) viram 0.
  static void updateFromMps(double? speedMps) {
    if (speedMps == null || speedMps.isNaN || speedMps < 0) {
      kmh.value = 0;
      return;
    }
    kmh.value = speedMps * 3.6;
  }
}
