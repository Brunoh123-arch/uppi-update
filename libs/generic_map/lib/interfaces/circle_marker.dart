import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class CircleMarker {
  final String? id;
  final LatLng position;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final double? borderWidth;

  CircleMarker({
    this.id,
    required this.position,
    required this.radius,
    this.color,
    this.borderColor,
    this.borderWidth,
  });
}
