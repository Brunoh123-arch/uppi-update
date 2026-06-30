import 'package:flutter_common/core/entities/payment_method_union.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:rider_flutter/core/entities/order.dart';
import 'package:rider_flutter/core/entities/order_compact.dart';

/// Converte dados do Supabase (tabela `rides`) para as entidades do app.
class FirestoreMapper {
  FirestoreMapper._();

  static OrderStatus _toStatus(String? raw) {
    switch (raw) {
      case 'Requested':
        return OrderStatus.requested;
      case 'NotFound':
        return OrderStatus.notFound;
      case 'NoCloseFound':
        return OrderStatus.noCloseFound;
      case 'Found':
        return OrderStatus.found;
      case 'DriverAccepted':
        return OrderStatus.driverAccepted;
      case 'Arrived':
        return OrderStatus.arrived;
      case 'WaitingForPrePay':
        return OrderStatus.waitingForPrePay;
      case 'DriverCanceled':
        return OrderStatus.driverCanceled;
      case 'RiderCanceled':
        return OrderStatus.riderCanceled;
      case 'Started':
        return OrderStatus.started;
      case 'WaitingForPostPay':
        return OrderStatus.waitingForPostPay;
      case 'WaitingForReview':
        return OrderStatus.waitingForReview;
      case 'Finished':
        return OrderStatus.finished;
      case 'Booked':
        return OrderStatus.booked;
      case 'Expired':
        return OrderStatus.expired;
      default:
        return OrderStatus.requested;
    }
  }

  static DateTime _toDateTime(dynamic value) {
    if (value == null) return DateTime.now().toLocal();
    if (value is DateTime) return value.toLocal();
    try {
      return DateTime.parse(value.toString()).toLocal();
    } catch (_) {
      return DateTime.now().toLocal();
    }
  }

  static OrderEntity toOrderEntity(Map<String, dynamic> data) {
    final status = _toStatus(data['status'] as String?);
    return OrderEntity(
      id: data['id']?.toString() ?? '',
      status: status,
      waypoints: const [],
      arrivedAtWaypointIndex: status == OrderStatus.started ? 0 : null,
      rideDirections: const [],
      driverDirections: const [],
      driver: null,
      serviceName: data['serviceName'] as String? ?? 'Uppi',
      serviceImageUrl: data['serviceImageUrl'] as String? ?? '',
      cancellationFee: (data['cancellationFee'] as num?)?.toDouble() ?? 0.0,
      cost: (data['costBest'] as num?)?.toDouble() ?? 0.0,
      costAfterCoupon:
          (data['costAfterCoupon'] as num?)?.toDouble() ??
          (data['costBest'] as num?)?.toDouble() ??
          0.0,
      currency: data['currency'] as String? ?? 'BRL',
      distance: (data['distanceBest'] as num?)?.toInt() ?? 0,
      duration: (data['durationBest'] as num?)?.toInt() ?? 0,
      waitTime: (data['waitTime'] as num?)?.toInt() ?? 0,
      etaPickup: data['etaPickup'] != null ? _toDateTime(data['etaPickup']) : null,
      createdAt: _toDateTime(data['createdAt']),
      expectedAt: data['expectedAt'] != null
          ? _toDateTime(data['expectedAt'])
          : _toDateTime(data['createdAt']),
      startedAt: data['startedAt'] != null
          ? _toDateTime(data['startedAt'])
          : null,
      lastSeenMessagesAt: DateTime.now(),
      paymentMethod: null,
      chatMessages: const [],
      walletCredit: (data['walletCredit'] as num?)?.toDouble() ?? 0.0,
      cashPaymentAllowed: data['cashPaymentAllowed'] as bool? ?? true,
      boardingPin: (data['boarding_pin'] ?? data['boardingPin'])?.toString(),
    );
  }

  static OrderCompactEntity toOrderCompact(Map<String, dynamic> data) {
    return OrderCompactEntity(
      id: data['id']?.toString() ?? '',
      createdAt: _toDateTime(data['createdAt']),
      expectedAt: data['expectedAt'] != null
          ? _toDateTime(data['expectedAt'])
          : _toDateTime(data['createdAt']),
      startedAt: data['startedAt'] != null
          ? _toDateTime(data['startedAt'])
          : null,
      endedAt: data['endedAt'] != null
          ? _toDateTime(data['endedAt'])
          : null,
      waitTime: (data['waitTime'] as num?)?.toInt() ?? 0,
      isTwoWayTrip: data['isTwoWayTrip'] as bool? ?? false,
      waypoints: (data['waypoints'] as List<dynamic>?)?.map((e) => e as PlaceEntity).toList() ?? const [],
      rideOptions: const [],
      fee: (data['costBest'] as num?)?.toDouble() ?? 0.0,
      currency: data['currency'] as String? ?? 'BRL',
      paymentMethodUnion: const PaymentMethodUnion.cash(),
      serviceName: data['serviceName'] as String? ?? 'Uppi',
      serviceDescription: null,
      serviceImageUrl: null,
      distanceBest: (data['distanceBest'] as num?)?.toInt() ?? 0,
      durationBest: (data['durationBest'] as num?)?.toInt() ?? 0,
      driver: null,
    );
  }
}
