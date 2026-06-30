import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:generic_map/flutter_map/widget.dart';
import 'package:generic_map/interfaces/interfaces.dart';
import 'package:latlong2/latlong.dart';

class FlutterMapController implements MapViewController {
  final AnimatedMapController mapController;
  EdgeInsets? padding;

  FlutterMapController({required this.mapController, this.padding});

  @override
  void fitBounds(List<LatLng> points) {
    if (points.isEmpty) return;
    debugPrint("FlutterMapController.fitBounds: points count = ${points.length}, padding = $padding");
    try {
      mapController.animatedFitCamera(
        cameraFit: CameraFit.coordinates(
          coordinates: points,
          padding: padding ?? EdgeInsets.zero,
        ),
      );
      debugPrint("FlutterMapController.fitBounds: animatedFitCamera completed successfully");
    } catch (e, s) {
      debugPrint("FlutterMapController.fitBounds: Error fitting camera: $e\n$s");
    }
  }

  @override
  void moveCamera(LatLng location, double? zoom, {double? bearing, double? tilt, Duration? duration}) {
    final yAxis = (((padding?.top ?? 0) - (padding?.bottom ?? 0)) / 2);
    final xAxis = (((padding?.left ?? 0) - (padding?.right ?? 0)) / 2);
    final offsetFromPadding = Offset(xAxis, yAxis);
    final currentZoom = mapController.mapController.camera.zoom;
    mapController.animateTo(
      customId: FlutterMapViewState.useTransformerId,
      dest: location,
      zoom: zoom ?? currentZoom,
      offset: offsetFromPadding,
      // Convenção de sinal: `bearing` chega no padrão Google Maps (rumo da
      // bússola que deve apontar para CIMA na tela). No flutter_map a rotação
      // positiva gira o conteúdo em sentido horário, então heading-up exige o
      // valor NEGADO — sem isso o mapa girava para o lado errado e a seta de
      // navegação ficava com o dobro do ângulo de erro.
      // Sem bearing explícito, mantém a rotação atual do mapa — antes o
      // mapa "pulava" de volta para o norte no meio da navegação.
      rotation: bearing != null
          ? -bearing
          : mapController.mapController.camera.rotation,
      duration: duration,
    );
    //mapController.centerOnPoint(location);
    // mapController.animateTo(dest: location, zoom: zoom);
  }

  @override
  Future<LatLng> getCenter() async {
    return mapController.mapController.camera.center;
  }

  @override
  dispose() {
    mapController.dispose();
  }
}
