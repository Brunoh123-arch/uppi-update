import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';

/// Celebration screen shown after successful driver registration.
/// Inspired by inDrive's confetti success screen but using Uppi's iOS blue design.
class RegistrationSuccessScreen extends StatefulWidget {
  final VoidCallback? onContinue;

  const RegistrationSuccessScreen({super.key, this.onContinue});

  @override
  State<RegistrationSuccessScreen> createState() =>
      _RegistrationSuccessScreenState();
}

class _RegistrationSuccessScreenState extends State<RegistrationSuccessScreen>
    with TickerProviderStateMixin {
  late AnimationController _confettiController;
  late AnimationController _scaleController;
  late AnimationController _checkController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _checkAnimation;
  final List<_ConfettiParticle> _particles = [];
  final _random = Random();

  @override
  void initState() {
    super.initState();

    // Generate confetti particles
    for (int i = 0; i < 80; i++) {
      _particles.add(_ConfettiParticle(
        x: _random.nextDouble(),
        y: -_random.nextDouble() * 0.5,
        speed: 0.3 + _random.nextDouble() * 0.7,
        size: 4 + _random.nextDouble() * 8,
        color: _confettiColors[_random.nextInt(_confettiColors.length)],
        rotation: _random.nextDouble() * pi * 2,
        rotationSpeed: (_random.nextDouble() - 0.5) * 0.1,
        horizontalDrift: (_random.nextDouble() - 0.5) * 0.3,
        shape: _random.nextInt(3), // 0=rect, 1=circle, 2=star
      ));
    }

    // Confetti animation
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..forward();

    // Scale bounce for the check icon
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    // Check mark draw animation
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _checkAnimation = CurvedAnimation(
      parent: _checkController,
      curve: Curves.easeInOut,
    );

    // Sequence: wait → scale in → draw check
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _scaleController.forward();
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _checkController.forward();
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _scaleController.dispose();
    _checkController.dispose();
    super.dispose();
  }

  static const _confettiColors = [
    ColorPalette.primary50,
    ColorPalette.primary60,
    ColorPalette.primary70,
    ColorPalette.tertiary60,
    ColorPalette.tertiary80,
    ColorPalette.secondary50,
    ColorPalette.secondary70,
    Color(0xFFFFD700), // Gold
    Color(0xFF7C4DFF), // Purple
    ColorPalette.semanticgreen60,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorPalette.neutral100,
      body: Stack(
        children: [
          // Confetti layer
          AnimatedBuilder(
            animation: _confettiController,
            builder: (context, _) {
              return CustomPaint(
                size: MediaQuery.of(context).size,
                painter: _ConfettiPainter(
                  particles: _particles,
                  progress: _confettiController.value,
                ),
              );
            },
          ),

          // Main content
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // Animated check circle
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            ColorPalette.primary50,
                            ColorPalette.primary60,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: ColorPalette.primary50.withOpacity(0.3),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: AnimatedBuilder(
                        animation: _checkAnimation,
                        builder: (context, _) {
                          return CustomPaint(
                            painter: _CheckPainter(
                              progress: _checkAnimation.value,
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Title
                  FadeTransition(
                    opacity: _scaleAnimation,
                    child: Text(
                      'Cadastro Enviado!',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: ColorPalette.neutral20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Subtitle
                  FadeTransition(
                    opacity: _scaleAnimation,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'Seus documentos foram enviados com sucesso.\nVamos analisá-los e você será notificado em breve.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: ColorPalette.neutral50,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),

                  const Spacer(flex: 3),

                  // Continue button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: FadeTransition(
                      opacity: _scaleAnimation,
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: widget.onContinue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ColorPalette.primary50,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Continuar',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated check mark painter
class _CheckPainter extends CustomPainter {
  final double progress;

  _CheckPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0) return;

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Check mark coordinates (relative to center)
    final startX = cx - 20;
    final startY = cy + 2;
    final midX = cx - 5;
    final midY = cy + 16;
    final endX = cx + 22;
    final endY = cy - 14;

    if (progress <= 0.5) {
      // First stroke of the check (down-left to bottom)
      final t = progress * 2;
      path.moveTo(startX, startY);
      path.lineTo(
        startX + (midX - startX) * t,
        startY + (midY - startY) * t,
      );
    } else {
      // First stroke complete + second stroke (bottom to top-right)
      final t = (progress - 0.5) * 2;
      path.moveTo(startX, startY);
      path.lineTo(midX, midY);
      path.lineTo(
        midX + (endX - midX) * t,
        midY + (endY - midY) * t,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Confetti particle data
class _ConfettiParticle {
  double x, y, speed, size, rotation, rotationSpeed, horizontalDrift;
  Color color;
  int shape;

  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.color,
    required this.rotation,
    required this.rotationSpeed,
    required this.horizontalDrift,
    required this.shape,
  });
}

/// Confetti rain painter
class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final currentY = p.y + progress * p.speed * 1.5;
      final currentX = p.x + sin(progress * pi * 3) * p.horizontalDrift * 0.1;
      final rotation = p.rotation + progress * p.rotationSpeed * pi * 8;

      // Fade out as particles reach the bottom
      final opacity = (1.0 - (currentY * 0.7)).clamp(0.0, 1.0);
      if (opacity <= 0 || currentY > 1.2) continue;

      final paint = Paint()..color = p.color.withOpacity(opacity);
      final px = currentX * size.width;
      final py = currentY * size.height;

      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(rotation);

      switch (p.shape) {
        case 0: // Rectangle
          canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
            paint,
          );
          break;
        case 1: // Circle
          canvas.drawCircle(Offset.zero, p.size * 0.4, paint);
          break;
        case 2: // Star/diamond
          final path = Path()
            ..moveTo(0, -p.size * 0.5)
            ..lineTo(p.size * 0.3, 0)
            ..lineTo(0, p.size * 0.5)
            ..lineTo(-p.size * 0.3, 0)
            ..close();
          canvas.drawPath(path, paint);
          break;
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
