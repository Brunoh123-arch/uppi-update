import 'package:dartz/dartz.dart';
import 'package:uppi_motorista/core/datasources/firebase_datasource.dart';
import 'package:uppi_motorista/core/entities/order.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:flutter_common/core/enums/payment_mode.dart';
import 'package:injectable/injectable.dart';

import '../../domain/repositories/ride_history_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@prod
@LazySingleton(as: RideHistoryRepository)
class RideHistoryRepositoryImpl implements RideHistoryRepository {
  final FirebaseDatasource firebaseDatasource;
  final SupabaseClient supabaseClient;

  RideHistoryRepositoryImpl(
    this.firebaseDatasource, {
    SupabaseClient? supabaseClient,
  }) : supabaseClient = supabaseClient ?? Supabase.instance.client;

  @override
  Stream<Either<Failure, List<OrderEntity>>> startRideHistorySubscription() async* {
    yield await getRideHistory();
  }

  @override
  Future<Either<Failure, List<OrderEntity>>> getRideHistory() async {
    try {
      final uid = firebaseDatasource.uid;
      final queryResult = await supabaseClient
          .from('rides')
          .select()
          .eq('driver_id', uid!)
          .order('created_at', ascending: false)
          .limit(50);

      final orders = queryResult.map((data) {
        OrderStatus statusMapped = OrderStatus.requested;
        final st = data['status']?.toString();
        if (st == 'accepted' || st == 'driver_accepted') statusMapped = OrderStatus.driverAccepted;
        if (st == 'arrived') statusMapped = OrderStatus.arrived;
        if (st == 'in_progress' || st == 'started') statusMapped = OrderStatus.started;
        if (st == 'completed' || st == 'finished' || st == 'waiting_for_review') statusMapped = OrderStatus.finished;
        if (st == 'canceled' || st == 'rider_canceled' || st == 'driver_canceled') statusMapped = OrderStatus.riderCanceled;

        DateTime createdAt = DateTime.now();
        if (data['created_at'] != null) {
          createdAt =
              DateTime.tryParse(data['created_at'].toString())?.toLocal() ??
              DateTime.now();
        }

        DateTime? finishAt;
        if (data['finished_at'] != null) {
          finishAt = DateTime.tryParse(data['finished_at'].toString())?.toLocal();
        } else if (data['canceled_at'] != null) {
          finishAt = DateTime.tryParse(data['canceled_at'].toString())?.toLocal();
        } else if (data['updated_at'] != null) {
          finishAt = DateTime.tryParse(data['updated_at'].toString())?.toLocal();
        }

        DateTime? startAt;
        if (data['started_at'] != null) {
          startAt = DateTime.tryParse(data['started_at'].toString())?.toLocal();
        }

        final fare = (data['fare'] as num?)?.toDouble() ?? 0.0;
        // Distância real percorrida tem prioridade sobre a estimada
        final distanceMeters =
            (data['actual_distance'] as num?)?.toInt() ??
            (data['distance_meters'] as num?)?.toInt() ??
            (data['distance'] as num?)?.toInt() ??
            0;
        final durationSeconds =
            (data['actual_duration'] as num?)?.toInt() ??
            (data['duration_seconds'] as num?)?.toInt() ??
            (data['duration'] as num?)?.toInt() ??
            0;

        return OrderEntity.emptyOrder.copyWith(
          id: data['id'].toString(),
          status: statusMapped,
          costBest: fare,
          costAfterCoupon: fare,
          distanceBest: distanceMeters,
          durationBest: durationSeconds,
          paymentMode: data['payment_method'] == 'cash'
              ? PaymentMode.cash
              : PaymentMode.wallet,
          createdAt: createdAt,
          expectedAt: createdAt,
          startAt: startAt,
          finishAt: finishAt,
          currency: data['currency']?.toString() ?? 'BRL',
          serviceName: data['service_type']?.toString() ?? 'Standard',
          waypoints: [
            PlaceEntity(
              coordinates: LatLngEntity(lat: (data['pickup_lat'] as num?)?.toDouble() ?? 0, lng: (data['pickup_lng'] as num?)?.toDouble() ?? 0),
              address: data['pickup_address']?.toString() ?? 'Ponto de Origem',
            ),
            PlaceEntity(
              coordinates: LatLngEntity(lat: (data['dropoff_lat'] as num?)?.toDouble() ?? 0, lng: (data['dropoff_lng'] as num?)?.toDouble() ?? 0),
              address: data['dropoff_address']?.toString() ?? 'Ponto de Destino',
            ),
          ],
        );
      }).toList();

      return Right(orders);
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, bool>> reportIssue({
    required String orderId,
    required String subject,
    required String issue,
  }) async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) {
        return Left(Failure.server(message: 'Not authenticated'));
      }

      final response = await supabaseClient.functions.invoke(
        'submit-feedback',
        body: {
          'ride_id': orderId,
          'subject': subject,
          'review': issue,
          'is_complaint': true,
        },
      );
      if (response.status != 200) {
        throw Exception('Failed to submit feedback');
      }
      return const Right(true);
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }
}
