import 'package:dartz/dartz.dart';

import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/entities/order_compact.dart';
import 'package:rider_flutter/core/error/failure.dart';
import 'package:flutter_common/core/entities/place.dart';

import '../../domain/repositories/scheduled_rides_repository.dart';
import 'package:rider_flutter/core/mappers/firestore_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@prod
@LazySingleton(as: ScheduledRidesRepository)
class ScheduledRidesRepositoryImpl implements ScheduledRidesRepository {
  final FirebaseDatasource firebaseDatasource;
  final SupabaseClient supabaseClient;

  ScheduledRidesRepositoryImpl(this.firebaseDatasource)
      : supabaseClient = Supabase.instance.client;

  @override
  Stream<Either<Failure, List<OrderCompactEntity>>> startUpcomingRidesSubscription() async* {
    yield await getUpcomingRides();
  }

  @override
  Future<Either<Failure, List<OrderCompactEntity>>> getUpcomingRides() async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) {
        return Left(Failure.serverError('User not authenticated'));
      }

      final queryResult = await supabaseClient
          .from('rides')
          .select()
          .eq('rider_id', uid)
          .eq('status', 'booked')
          .order('expected_at', ascending: true);

      final orders = queryResult.map((data) {
        final mockData = {
          'id': data['id'].toString(),
          'status': 'Booked',
          'createdAt': data['created_at'],
          'expectedAt': data['expected_at'],
          'distanceBest': data['distance_meters'] ?? 0,
          'durationBest': data['duration_seconds'] ?? 0,
          'costBest': data['fare'] ?? 0.0,
          'waypoints': [
            PlaceEntity(
              coordinates: LatLngEntity(lat: (data['pickup_lat'] as num?)?.toDouble() ?? 0, lng: (data['pickup_lng'] as num?)?.toDouble() ?? 0),
              address: data['pickup_address']?.toString() ?? 'Ponto de Origem',
            ),
            PlaceEntity(
              coordinates: LatLngEntity(lat: (data['dropoff_lat'] as num?)?.toDouble() ?? 0, lng: (data['dropoff_lng'] as num?)?.toDouble() ?? 0),
              address: data['dropoff_address']?.toString() ?? 'Ponto de Destino',
            ),
          ],
        };
        return FirestoreMapper.toOrderCompact(mockData);
      }).toList();

      return Right(orders);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> cancelRide(String orderId) async {
    try {
      // Cancelar via Edge Function para garantir notificações e RLS
      final response = await supabaseClient.functions.invoke(
        'cancel-order',
        body: {'orderId': orderId},
      );
      if (response.status != 200) {
        return Left(Failure.serverError('Falha ao cancelar corrida agendada'));
      }
      return const Right(unit);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }
}
