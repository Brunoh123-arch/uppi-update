import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:generic_map/interfaces/interfaces.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:widget_to_marker/widget_to_marker.dart';

class GoogleMapProvider
    implements MapProvider<Future<Marker>, Circle, Polyline> {
  @override
  List<Circle> parseCircleMarkers(List<CircleMarker> marker) {
    return marker.map((e) => _parseCircleMarker(e)).toList();
  }

  Circle _parseCircleMarker(CircleMarker marker) {
    return Circle(
      circleId: CircleId(marker.id ?? marker.position.toString()),
      center: LatLng(marker.position.latitude, marker.position.longitude),
      radius: marker.radius,
      fillColor: marker.color ?? Colors.blue,
      strokeColor: marker.borderColor ?? Colors.yellow,
      strokeWidth: marker.borderWidth?.toInt() ?? 5,
    );
  }

  static final Map<int, BitmapDescriptor> _bitmapCache = {};

  @override
  List<Future<Marker>> parseMarkers(List<CustomMarker> marker) {
    return marker.map((e) => _parseMarker(e)).toList();
  }

  Future<Marker> _parseMarker(CustomMarker marker) async {
    final String keySource = marker.id ?? (marker.widget.key != null ? marker.widget.key.toString() : marker.widget.runtimeType.toString());
    // Geramos e cacheamos o bitmap do marcador virado para o Norte (0°).
    // A rotação final é aplicada nativamente na GPU pelo próprio Google Maps SDK,
    // o que evita recriação excessiva de bitmaps e flickering.
    final cacheKey = keySource.hashCode ^ marker.width.hashCode ^ marker.height.hashCode;
    BitmapDescriptor icon;
    if (_bitmapCache.containsKey(cacheKey)) {
      icon = _bitmapCache[cacheKey]!;
    } else {
      icon = await SizedBox(
        width: marker.width,
        height: marker.height,
        child: marker.widget,
      ).toBitmapDescriptor(
        imageSize: Size(
          (marker.width ?? 100) * 2.0,
          (marker.height ?? 100) * 2.0,
        ),
        logicalSize: Size(marker.width ?? 100, marker.height ?? 100),
        waitToRender: kIsWeb ? const Duration(milliseconds: 1500) : const Duration(milliseconds: 300),
      );
      // Evita crescimento sem limite (ids únicos de outros motoristas/zonas
      // acumulam bitmaps na memória durante o turno inteiro).
      if (_bitmapCache.length > 300) _bitmapCache.clear();
      _bitmapCache[cacheKey] = icon;
    }

    final String markerIdStr = marker.id ?? marker.position.toString();
    
    // Converte o Alignment do Flutter [-1, 1] para a âncora do Google Maps [0, 1]
    // O padrão do Google Maps é base-central (bottomCenter), ideal para pins normais.
    // Para a bolinha azul de GPS (que usa center), a conversão resulta em Offset(0.5, 0.5), travando-a geograficamente.
    final alignment = marker.alignment ?? Alignment.bottomCenter;
    final anchorX = (alignment.x + 1) / 2;
    final anchorY = (alignment.y + 1) / 2;

    return Marker(
      markerId: MarkerId(markerIdStr),
      position: LatLng(marker.position.latitude, marker.position.longitude),
      icon: icon,
      anchor: Offset(anchorX, anchorY),
      rotation: marker.rotation.toDouble(),
      flat: marker.flat,
      onTap: marker.onTap,
    );
  }

  @override
  List<Polyline> parsePolyLines(List<PolyLineLayer> polyLine) {
    final List<Polyline> result = [];
    for (final e in polyLine) {
      final points = e.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
      
      // Se a rota tiver borda definida, criamos uma linha mais grossa por baixo (zIndex menor)
      if (e.borderColor != null && e.borderStrokeWidth != null && e.borderStrokeWidth! > 0) {
        result.add(Polyline(
          polylineId: PolylineId('${e.points.hashCode}_border'),
          points: points,
          color: e.borderColor!,
          width: (e.width ?? 5).toInt() + (e.borderStrokeWidth! * 2).toInt(),
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: 1,
        ));
      }
      
      // Simula gradiente no Google Maps dividindo a rota em segmentos com cores interpoladas
      if (e.gradientColors.length >= 2 && points.length >= 2) {
        final colorStart = e.gradientColors.first;
        final colorEnd = e.gradientColors.last;
        final segmentCount = points.length - 1;
        for (int i = 0; i < segmentCount; i++) {
          final t = segmentCount == 1 ? 0.0 : i / (segmentCount - 1);
          final segColor = Color.lerp(colorStart, colorEnd, t)!;
          result.add(Polyline(
            polylineId: PolylineId('${e.points.hashCode}_seg_$i'),
            points: [points[i], points[i + 1]],
            color: segColor,
            width: e.width?.toInt() ?? 5,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
            zIndex: 2,
          ));
        }
      } else {
        // Linha principal cor sólida
        result.add(Polyline(
          polylineId: PolylineId('${e.points.hashCode}_main'),
          points: points,
          color: e.color ?? (e.gradientColors.isNotEmpty ? e.gradientColors.first : Colors.blue),
          width: e.width?.toInt() ?? 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: 2,
        ));
      }
    }
    return result;
  }
}
