import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:generic_map/generic_map.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';

class CurrentLocationMarker extends StatefulWidget {
  const CurrentLocationMarker({super.key});

  @override
  State<CurrentLocationMarker> createState() => _CurrentLocationMarkerState();

  CenterMarker get marker => CenterMarker(
        widget: this,
        size: const Size(60, 60),
        alignment: Alignment.center,
      );
}

class _CurrentLocationMarkerState extends State<CurrentLocationMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  StreamSubscription<CompassEvent>? _compassSubscription;
  double _heading = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _initCompass();
  }

  void _initCompass() {
    try {
      final stream = FlutterCompass.events;
      if (stream != null) {
        _compassSubscription = stream.listen(
          (CompassEvent event) {
            final double? headingVal = event.headingForCameraMode ?? event.heading;
            if (mounted && headingVal != null) {
              final double normalized = (headingVal + 360) % 360;
              // Só atualiza se a mudança for maior que 1 grau (evita jitter excessivo)
              if ((normalized - _heading).abs() > 1.0) {
                setState(() {
                  _heading = normalized;
                });
              }
            }
          },
          onError: (dynamic error) {
            debugPrint('[CurrentLocationMarker] Erro no compass: $error');
          },
        );
      }
    } catch (e) {
      debugPrint('[CurrentLocationMarker] Exceção ao iniciar compass: $e');
    }
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(60, 60),
          painter: LocationMarkerPainter(
            pulseValue: _animation.value,
            heading: _heading,
          ),
        );
      },
    );
  }
}

class LocationMarkerPainter extends CustomPainter {
  final double pulseValue;
  final double heading;

  LocationMarkerPainter({
    required this.pulseValue,
    required this.heading,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double maxConeRadius = size.width / 2;

    // 1. Desenha o pulso de luz (halo)
    final double haloRadius = 10.0 + (pulseValue * 15.0);
    final double haloOpacity = 0.25 * (1.0 - pulseValue);
    final Paint haloPaint = Paint()
      ..color = ColorPalette.primary50.withValues(alpha: haloOpacity)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, haloRadius, haloPaint);

    // 2. Desenha o cone de direção rotacionado com base na bússola
    // Graus magnéticos (heading): 0° = Norte (topo), 90° = Leste (direita), 180° = Sul (baixo), 270° = Oeste (esquerda)
    // No Flutter Canvas drawArc: 0 radianos = Leste (direita).
    // Para alinhar 0° magnético com o topo do canvas (Norte), subtraímos 90°.
    final double directionRad = (heading - 90.0) * math.pi / 180.0;
    const double sweepRad = 55.0 * math.pi / 180.0; // 55 graus de abertura do feixe
    final double startRad = directionRad - (sweepRad / 2);

    final double coneRadius = maxConeRadius - 2;
    final Paint conePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          ColorPalette.primary50.withValues(alpha: 0.50),
          ColorPalette.primary50.withValues(alpha: 0.20),
          ColorPalette.primary50.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: coneRadius))
      ..style = PaintingStyle.fill;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: coneRadius),
      startRad,
      sweepRad,
      true,
      conePaint,
    );

    // 3. Sombra da bolinha
    final Path shadowPath = Path()
      ..addOval(Rect.fromCircle(center: center.translate(0, 1), radius: 8.5));
    canvas.drawShadow(shadowPath, Colors.black.withValues(alpha: 0.3), 3.0, true);

    // 4. Borda branca da bolinha
    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 8.5, borderPaint);

    // 5. Bolinha azul central
    final Paint dotPaint = Paint()
      ..color = ColorPalette.primary50
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 6.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant LocationMarkerPainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue || oldDelegate.heading != heading;
  }
}
