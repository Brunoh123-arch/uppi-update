import 'dart:math';
import 'package:latlong2/latlong.dart';

/// Utilitário para interpolação suave de marcadores no mapa.
/// Usado para animar a posição do veículo do motorista com movimento suave.
class SmoothMarkerInterpolator {
  /// Interpola linearmente entre dois pontos geográficos.
  /// [start] posição inicial
  /// [end] posição final
  /// [t] fração de tempo (0.0 a 1.0)
  static LatLng interpolatePosition(LatLng start, LatLng end, double t) {
    final lat = start.latitude + (end.latitude - start.latitude) * t;
    final lng = start.longitude + (end.longitude - start.longitude) * t;
    return LatLng(lat, lng);
  }

  /// Calcula o ângulo de rotação (bearing) geodésico entre dois pontos.
  /// Retorna o ângulo em graus (0-360), onde 0 = Norte.
  static double calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * pi / 180;
    final lat2 = to.latitude * pi / 180;
    final dLng = (to.longitude - from.longitude) * pi / 180;

    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    final bearing = atan2(y, x) * 180 / pi;
    return (bearing + 360) % 360;
  }

  /// Interpola suavemente o ângulo de rotação (lida com a fronteira 0/360).
  static double interpolateBearing(double from, double to, double t) {
    double diff = to - from;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return (from + diff * t + 360) % 360;
  }

  /// Interpola cubicamente (ease-in-out) entre 0.0 e 1.0.
  static double easeInOut(double t) {
    return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
  }
}
