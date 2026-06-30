// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vehicle_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$VehicleModelEntityImpl _$$VehicleModelEntityImplFromJson(
        Map<String, dynamic> json) =>
    _$VehicleModelEntityImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String? ?? 'carro',
    );

Map<String, dynamic> _$$VehicleModelEntityImplToJson(
        _$VehicleModelEntityImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'category': instance.category,
    };
