// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$OrderRequestEntityImpl _$$OrderRequestEntityImplFromJson(
        Map<String, dynamic> json) =>
    _$OrderRequestEntityImpl(
      id: json['id'] as String,
      status: $enumDecode(_$OrderStatusEnumMap, json['status']),
      paymentMethod: PaymentMethodUnion.fromJson(
          json['paymentMethod'] as Map<String, dynamic>),
      currency: json['currency'] as String,
      fee: (json['fee'] as num).toDouble(),
      providerShare: (json['providerShare'] as num).toDouble(),
      distance: json['distance'] as int,
      duration: json['duration'] as int,
      serviceName: json['serviceName'] as String,
      route: (json['route'] as List<dynamic>)
          .map((e) => LatLngEntity.fromJson(e as Map<String, dynamic>))
          .toList(),
      waypoints: (json['waypoints'] as List<dynamic>)
          .map((e) => PlaceEntity.fromJson(e as Map<String, dynamic>))
          .toList(),
      rideOptions: (json['rideOptions'] as List<dynamic>)
          .map((e) => RideOptionEntity.fromJson(e as Map<String, dynamic>))
          .toList(),
      riderFirstName: json['riderFirstName'] as String?,
      riderLastName: json['riderLastName'] as String?,
      riderPhotoUrl: json['riderPhotoUrl'] as String?,
      riderRating: (json['riderRating'] as num?)?.toDouble(),
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.parse(json['expiresAt'] as String),
      isDangerZone: json['isDangerZone'] as bool? ?? false,
      dangerZoneName: json['dangerZoneName'] as String?,
    );

Map<String, dynamic> _$$OrderRequestEntityImplToJson(
        _$OrderRequestEntityImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'status': _$OrderStatusEnumMap[instance.status]!,
      'paymentMethod': instance.paymentMethod.toJson(),
      'currency': instance.currency,
      'fee': instance.fee,
      'providerShare': instance.providerShare,
      'distance': instance.distance,
      'duration': instance.duration,
      'serviceName': instance.serviceName,
      'route': instance.route.map((e) => e.toJson()).toList(),
      'waypoints': instance.waypoints.map((e) => e.toJson()).toList(),
      'rideOptions': instance.rideOptions.map((e) => e.toJson()).toList(),
      'riderFirstName': instance.riderFirstName,
      'riderLastName': instance.riderLastName,
      'riderPhotoUrl': instance.riderPhotoUrl,
      'riderRating': instance.riderRating,
      'expiresAt': instance.expiresAt?.toIso8601String(),
      'isDangerZone': instance.isDangerZone,
      'dangerZoneName': instance.dangerZoneName,
    };

const _$OrderStatusEnumMap = {
  OrderStatus.requested: 'requested',
  OrderStatus.notFound: 'notFound',
  OrderStatus.noCloseFound: 'noCloseFound',
  OrderStatus.found: 'found',
  OrderStatus.driverAccepted: 'driverAccepted',
  OrderStatus.arrived: 'arrived',
  OrderStatus.waitingForPrePay: 'waitingForPrePay',
  OrderStatus.driverCanceled: 'driverCanceled',
  OrderStatus.riderCanceled: 'riderCanceled',
  OrderStatus.started: 'started',
  OrderStatus.waitingForPostPay: 'waitingForPostPay',
  OrderStatus.waitingForReview: 'waitingForReview',
  OrderStatus.finished: 'finished',
  OrderStatus.booked: 'booked',
  OrderStatus.expired: 'expired',
};
