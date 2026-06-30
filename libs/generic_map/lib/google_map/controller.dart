import 'dart:async';
import 'dart:math';

import 'package:generic_map/interfaces/interfaces.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as latlong;

class GoogleMapsController implements MapViewController {
  final Completer<GoogleMapController> mapController = Completer();

  CameraPosition? currentCameraPosition;

  GoogleMapsController();

  @override
  void fitBounds(List<latlong.LatLng> points) async {
    try {
      print("UPPI BRASIL - GoogleMapsController fitBounds called with ${points.length} points");
      if (points.isEmpty) {
        print("UPPI BRASIL - GoogleMapsController fitBounds: points list is empty, aborting");
        return;
      }
      var firstLatLng = points.first;
      var s = firstLatLng.latitude,
          n = firstLatLng.latitude,
          w = firstLatLng.longitude,
          e = firstLatLng.longitude;
      for (var i = 1; i < points.length; i++) {
        var latlng = points[i];
        s = min(s, latlng.latitude);
        n = max(n, latlng.latitude);
        w = min(w, latlng.longitude);
        e = max(e, latlng.longitude);
      }
      final bounds = LatLngBounds(
        southwest: LatLng(s, w),
        northeast: LatLng(n, e),
      );
      print("UPPI BRASIL - GoogleMapsController fitBounds: southwest = LatLng(${bounds.southwest.latitude}, ${bounds.southwest.longitude}), northeast = LatLng(${bounds.northeast.latitude}, ${bounds.northeast.longitude})");
      final controller = await mapController.future;
      
      print("UPPI BRASIL - GoogleMapsController fitBounds: resetting tilt and bearing");
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng((s + n) / 2, (w + e) / 2),
            zoom: 12,
            tilt: 0.0,
            bearing: 0.0,
          ),
        ),
      );
      
      print("UPPI BRASIL - GoogleMapsController fitBounds: map controller resolved. Calling animateCamera");
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 20),
      );
      print("UPPI BRASIL - GoogleMapsController fitBounds: animateCamera completed successfully");
    } catch (e, stack) {
      print("UPPI BRASIL - GoogleMapsController fitBounds ERROR: $e\n$stack");
    }
  }

  @override
  void moveCamera(latlong.LatLng location, double? zoom, {double? bearing, double? tilt, Duration? duration}) async {
    final googleLatLng = LatLng(location.latitude, location.longitude);
    final controller = await mapController.future;
    final cameraPosition = CameraPosition(
      target: googleLatLng,
      zoom: zoom ?? currentCameraPosition?.zoom ?? 16.0,
      bearing: bearing ?? currentCameraPosition?.bearing ?? 0.0,
      tilt: tilt ?? currentCameraPosition?.tilt ?? 45.0,
    );
    
    if (duration == Duration.zero) {
      controller.moveCamera(
        CameraUpdate.newCameraPosition(cameraPosition),
      );
    } else {
      // Com duração explícita a câmera desliza entre os fixes de GPS em vez
      // de saltar (google_maps_flutter >= 2.10 aceita `duration`).
      controller.animateCamera(
        CameraUpdate.newCameraPosition(cameraPosition),
        duration: duration,
      );
    }
  }

  @override
  Future<latlong.LatLng> getCenter() async {
    final visibleRegion = await (await mapController.future).getVisibleRegion();
    return latlong.LatLng(
      visibleRegion.southwest.latitude +
          ((visibleRegion.northeast.latitude -
                  visibleRegion.southwest.latitude) /
              2),
      visibleRegion.southwest.longitude +
          ((visibleRegion.northeast.longitude -
                  visibleRegion.southwest.longitude) /
              2),
    );
  }

  @override
  dispose() {
    mapController.future.then((value) => value.dispose());
  }
}
