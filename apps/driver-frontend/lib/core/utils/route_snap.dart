import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class SnappedPoint {
  final LatLng position;
  final double bearing;

  SnappedPoint({required this.position, required this.bearing});
}

/// Projeta [p] na polyline [route] e retorna o ponto "grudado" na parte da
/// rota mais próxima (map-matching visual) e o ângulo (bearing) do segmento da via.
/// Retorna `null` se a rota tiver menos de 2 pontos — nesse caso o chamador usa a
/// posição crua do GPS.
SnappedPoint? snapPointToRoute(LatLng p, List<LatLng> route) {
  if (route.length < 2) return null;

  double bestOff = double.infinity;
  LatLng best = route.first;
  double bestBearing = 0.0;

  for (int i = 0; i < route.length - 1; i++) {
    final a = route[i];
    final b = route[i + 1];

    // Projeção planar local (metros), com origem em A — precisa o suficiente
    // na escala de uma rua.
    final mPerLng = 111320.0 * math.cos(a.latitude * math.pi / 180.0);
    const mPerLat = 111320.0;
    final bx = (b.longitude - a.longitude) * mPerLng;
    final by = (b.latitude - a.latitude) * mPerLat;
    final px = (p.longitude - a.longitude) * mPerLng;
    final py = (p.latitude - a.latitude) * mPerLat;

    final segLen2 = bx * bx + by * by;
    double t = segLen2 > 0 ? (px * bx + py * by) / segLen2 : 0.0;
    if (t < 0) t = 0;
    if (t > 1) t = 1;

    final lat = a.latitude + t * (b.latitude - a.latitude);
    final lng = a.longitude + t * (b.longitude - a.longitude);

    final dLat = (p.latitude - lat) * mPerLat;
    final dLng = (p.longitude - lng) * mPerLng;
    final off = math.sqrt(dLat * dLat + dLng * dLng);

    if (off < bestOff) {
      bestOff = off;
      best = LatLng(lat, lng);
      
      // Calcula o rumo (bearing) planar de A a B.
      // dx e dy relativos ao segmento de A para B.
      final sdy = b.latitude - a.latitude;
      final sdx = (b.longitude - a.longitude) * math.cos(a.latitude * math.pi / 180.0);
      bestBearing = (math.atan2(sdx, sdy) * 180.0 / math.pi + 360.0) % 360.0;
    }
  }

  return SnappedPoint(position: best, bearing: bestBearing);
}
