import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class CustomMarker {
  final String? id;
  final LatLng position;
  final Widget widget;
  final String? fallbackAssetPath;
  final double? width;
  final double? height;
  final Alignment? alignment;
  final int rotation;
  final bool flat;
  final VoidCallback? onTap;

  CustomMarker({
    this.id,
    required this.position,
    required this.widget,
    this.width,
    this.height,
    this.alignment,
    this.rotation = 0,
    this.fallbackAssetPath,
    this.flat = false,
    this.onTap,
  });

  @override
  String toString() {
    return 'WidgetMarker(id: $id, position: $position, widget: $widget, rotation: $rotation, width: $width, height: $height, alignment: $alignment, fallbackAssetPath: $fallbackAssetPath, flat: $flat)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CustomMarker &&
            other.id == id &&
            other.position == position &&
            other.widget == widget &&
            other.rotation == rotation &&
            other.width == width &&
            other.height == height &&
            other.alignment == alignment &&
            other.fallbackAssetPath == fallbackAssetPath &&
            other.flat == flat &&
            other.onTap == onTap;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        position.hashCode ^
        widget.hashCode ^
        rotation.hashCode ^
        width.hashCode ^
        height.hashCode ^
        alignment.hashCode ^
        fallbackAssetPath.hashCode ^
        flat.hashCode ^
        onTap.hashCode;
  }
}
