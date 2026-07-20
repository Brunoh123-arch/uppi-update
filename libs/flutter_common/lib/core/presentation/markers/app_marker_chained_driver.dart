import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:generic_map/generic_map.dart';
import 'package:ionicons/ionicons.dart';
import 'package:latlong2/latlong.dart' show LatLng;

/// Marcador "Terminando uma corrida por perto"
/// Exibido na posição do motorista quando ele está finalizando outra corrida
/// antes de buscar o passageiro.
class AppMarkerChainedDriver extends StatelessWidget {
  final VoidCallback? onTap;

  const AppMarkerChainedDriver({super.key, this.onTap});

  String get _label {
    final languageCode = PlatformDispatcher.instance.locale.languageCode;
    if (languageCode == 'pt') {
      return 'Terminando uma corrida por perto';
    } else if (languageCode == 'es') {
      return 'Terminando un viaje cercano';
    } else {
      return 'Finishing a nearby ride';
    }
  }

  static const double width = 260;
  static const double height = 80;
  static const Alignment alignment = Alignment.bottomCenter;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // ── Balão ──
          Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF096EFF), // primary50
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x3F000000),
                  offset: Offset(0, 3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Ionicons.car_sport, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // ── Triângulo ponteiro ──
          ClipPath(
            clipper: _TriangleClipper(),
            child: Container(
              color: const Color(0xFF096EFF),
              height: 8,
              width: 12,
            ),
          ),
          // ── Ponto do pin ──
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: const Color(0xFF096EFF),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  CustomMarker genericMarker(LatLng position) => CustomMarker(
        id: 'chained_driver_label',
        position: position,
        width: width,
        height: height,
        alignment: alignment,
        widget: this,
        onTap: onTap,
      );
}

class _TriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(size.width, 0.0);
    path.lineTo(size.width / 2, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_TriangleClipper oldClipper) => false;
}
