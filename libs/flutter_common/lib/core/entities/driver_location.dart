import 'package:flutter/material.dart';
import 'package:flutter_common/gen/assets.gen.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:generic_map/generic_map.dart';
import 'package:latlong2/latlong.dart';

part 'driver_location.freezed.dart';
part 'driver_location.g.dart';

@Freezed()
class DriverLocation with _$DriverLocation {
  const factory DriverLocation({
    String? id,
    required double lat,
    required double lng,
    required int? rotation,
    String? vehicleType,
    String? markerUrl,
  }) = _DriverLocation;

  factory DriverLocation.fromJson(Map<String, dynamic> json) =>
      _$DriverLocationFromJson(json);

  const DriverLocation._();

  CustomMarker genericMarker() {
    final isMoto = vehicleType?.toLowerCase() == 'moto';
    return CustomMarker(
      id: id?.toString() ?? 'driver',
      position: LatLng(lat, lng),
      alignment: Alignment.center,
      rotation: rotation ?? 0,
      widget: (markerUrl != null && markerUrl!.isNotEmpty)
          ? Image.network(markerUrl!, width: 48, height: 48)
          : (isMoto
                ? Assets.images.motoTopView.image(width: 40, height: 40)
                : Assets.images.carTopView.image(width: 48, height: 48)),
    );
  }
}

extension DriverLocationListX on List<DriverLocation> {
  List<CustomMarker> get markers => map((e) => e.genericMarker()).toList();
}
