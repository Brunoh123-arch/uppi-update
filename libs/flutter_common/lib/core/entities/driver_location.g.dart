// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'driver_location.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$DriverLocationImpl _$$DriverLocationImplFromJson(Map<String, dynamic> json) =>
    _$DriverLocationImpl(
      id: json['id'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      rotation: (json['rotation'] as num?)?.toInt(),
      vehicleType: json['vehicleType'] as String?,
      markerUrl: json['markerUrl'] as String?,
    );

Map<String, dynamic> _$$DriverLocationImplToJson(
        _$DriverLocationImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'lat': instance.lat,
      'lng': instance.lng,
      'rotation': instance.rotation,
      'vehicleType': instance.vehicleType,
      'markerUrl': instance.markerUrl,
    };
