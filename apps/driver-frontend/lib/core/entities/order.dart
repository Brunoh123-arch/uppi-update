import 'package:dartz/dartz.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:flutter_common/core/enums/payment_mode.dart';
import 'package:flutter_common/core/extensions/extensions.dart';
import 'package:flutter_common/features/chat/chat.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter_common/core/entities/ride_option.dart';

part 'order.freezed.dart';
part 'order.g.dart';

@Freezed(fromJson: true)
class OrderEntity with _$OrderEntity {
  const factory OrderEntity({
    required String id,
    required OrderStatus status,
    required DateTime createdAt,
    required DateTime expectedAt,
    required DateTime? startAt,
    required DateTime? finishAt,
    required DateTime? etaPickupAt,
    required DateTime lastSeenMessagesAt,
    required int? destinationArrivedTo,
    required double providerShare,
    required String currency,
    required List<PlaceEntity> waypoints,
    required int waitMinutes,
    required double waitCost,
    required double rideOptionsCost,
    required double taxCost,
    required double serviceCost,
    required double costBest,
    required double costAfterCoupon,
    required PaymentMode paymentMode,
    required int durationBest,
    required int distanceBest,
    required List<LatLngEntity> rideDirections,
    required List<LatLngEntity> driverDirections,
    required List<RideOptionEntity> rideOptions,
    required String? riderFirstName,
    required String? riderLastName,
    required String riderPhoneNumber,
    required String? riderPhotoUrl,
    required int? riderPresetPhotoId,
    required String serviceName,
    required bool cashPaymentAllowed,
    required List<ChatMessageEntity> chatMessages,
    required String? boardingPin,
  }) = _OrderEntity;

  factory OrderEntity.fromJson(Map<String, dynamic> json) =>
      _$OrderEntityFromJson(json);

  static OrderEntity get emptyOrder => OrderEntity(
    id: '',
    createdAt: DateTime.now(),
    expectedAt: DateTime.now(),
    status: OrderStatus.requested,
    lastSeenMessagesAt: DateTime.now(),
    destinationArrivedTo: null,
    startAt: null,
    finishAt: null,
    etaPickupAt: null,
    costBest: 0,
    costAfterCoupon: 0,
    providerShare: 0,
    currency: 'BRL',
    cashPaymentAllowed: true,
    chatMessages: [],
    waypoints: const [],
    waitMinutes: 0,
    waitCost: 0,
    rideOptionsCost: 0,
    taxCost: 0,
    serviceCost: 0,
    paymentMode: PaymentMode.cash,
    durationBest: 0,
    distanceBest: 0,
    rideDirections: const [],
    driverDirections: const [],
    rideOptions: [],
    riderFirstName: 'Passageiro',
    riderLastName: '',
    riderPhoneNumber: '',
    serviceName: 'Standard',
    riderPhotoUrl: null,
    riderPresetPhotoId: null,
    boardingPin: null,
  );

  const OrderEntity._();

  Option<Either<String, String>> get avatar => riderPhotoUrl != null
      ? Some(Right(riderPhotoUrl!))
      : riderPresetPhotoId != null
      ? Some(Left('assets/avatars/a$riderPresetPhotoId.png'))
      : const None();

  String get riderFullName {
    if (riderFirstName == null && riderLastName == null) return 'Passageiro';
    return '${riderFirstName ?? ''} ${riderLastName ?? ''}'.trim();
  }

  double get total => switch (paymentMode) {
    PaymentMode.cash || PaymentMode.pix => costAfterCoupon,
    _ => (costBest - providerShare),
  };

  DateTime? get expectedDesintationArrival =>
      startAt?.add(Duration(seconds: durationBest));

  String? expectedArrival(BuildContext context) =>
      expectedDesintationArrival?.minutesFromNow(context);
}
