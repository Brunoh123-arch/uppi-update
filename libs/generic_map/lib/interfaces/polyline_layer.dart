import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class PolyLineLayer {
  final List<LatLng> points;
  final Color? color;
  final double? width;
  final List<Color> gradientColors;
  final StrokeCap strokeCap;
  final StrokeJoin strokeJoin;
  final double? borderStrokeWidth;
  final Color? borderColor;

  PolyLineLayer({
    required this.points,
    this.color,
    this.width,
    required this.gradientColors,
    this.strokeCap = StrokeCap.round,
    this.strokeJoin = StrokeJoin.round,
    this.borderStrokeWidth,
    this.borderColor,
  });
}
