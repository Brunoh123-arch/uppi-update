import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';

/// Custom painter that draws a face-scan style oval guide
/// Similar to inDrive's selfie guide but in Uppi's iOS blue style
class SelfieGuidePainter extends CustomPainter {
  final double progress;

  SelfieGuidePainter({this.progress = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ovalRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.65,
      height: size.height * 0.82,
    );

    // Draw the semi-transparent overlay outside the oval
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      path,
      Paint()..color = ColorPalette.neutral20.withOpacity(0.6),
    );

    // Draw the animated border around the oval
    final borderPaint = Paint()
      ..color = ColorPalette.primary50
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // Draw dashed oval border
    final ovalPath = Path()..addOval(ovalRect);
    final metrics = ovalPath.computeMetrics().first;
    final totalLength = metrics.length;
    final dashLength = totalLength / 40;
    final gapLength = dashLength * 0.6;

    double distance = 0;
    while (distance < totalLength * progress) {
      final start = distance;
      final end = (distance + dashLength).clamp(0.0, totalLength);
      final extractPath = metrics.extractPath(start, end);
      canvas.drawPath(extractPath, borderPaint);
      distance += dashLength + gapLength;
    }

    // Draw corner brackets for extra iOS feel
    _drawCornerBrackets(canvas, size);
  }

  void _drawCornerBrackets(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ColorPalette.primary50
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    const bracketLength = 30.0;
    const margin = 16.0;

    // Top-left
    canvas.drawLine(
      const Offset(margin, margin + bracketLength),
      const Offset(margin, margin),
      paint,
    );
    canvas.drawLine(
      const Offset(margin, margin),
      const Offset(margin + bracketLength, margin),
      paint,
    );

    // Top-right
    canvas.drawLine(
      Offset(size.width - margin - bracketLength, margin),
      Offset(size.width - margin, margin),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - margin, margin),
      Offset(size.width - margin, margin + bracketLength),
      paint,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(margin, size.height - margin - bracketLength),
      Offset(margin, size.height - margin),
      paint,
    );
    canvas.drawLine(
      Offset(margin, size.height - margin),
      Offset(margin + bracketLength, size.height - margin),
      paint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(size.width - margin - bracketLength, size.height - margin),
      Offset(size.width - margin, size.height - margin),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - margin, size.height - margin),
      Offset(size.width - margin, size.height - margin - bracketLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(SelfieGuidePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
