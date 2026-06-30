import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/entities/review_parameter.dart';
import 'package:rider_flutter/core/error/failure.dart';

import '../../domain/repositories/rate_order_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@prod
@LazySingleton(as: RateOrderRepository)
class RateOrderRepositoryImpl implements RateOrderRepository {
  final FirebaseDatasource firebaseDatasource;
  final SupabaseClient supabaseClient;

  RateOrderRepositoryImpl(this.firebaseDatasource)
      : supabaseClient = Supabase.instance.client;

  @override
  Future<Either<Failure, List<ReviewParameterEntity>>>
      getReviewParameters() async {
    try {
      // Parâmetros de avaliação fixos para o MVP
      // Futuramente podem ser buscados de uma tabela 'review_parameters' no Supabase
      return const Right([
        ReviewParameterEntity(id: '1', name: 'Motorista educado', isGood: true),
        ReviewParameterEntity(id: '2', name: 'Carro limpo', isGood: true),
        ReviewParameterEntity(id: '3', name: 'Pontual', isGood: true),
        ReviewParameterEntity(id: '4', name: 'Direção segura', isGood: true),
        ReviewParameterEntity(id: '5', name: 'Demorou muito', isGood: false),
        ReviewParameterEntity(id: '6', name: 'Rota incorreta', isGood: false),
      ]);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> submitReview({
    required String orderId,
    required int rating,
    required bool isFavorite,
    required String? comment,
    required List<int> reviewParameters,
  }) async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) {
        return Left(Failure.serverError('User not authenticated'));
      }

      // Call the submit-review Edge Function so that:
      // 1. Driver's average_rating gets recalculated
      // 2. Ride status transitions to 'finished'
      // 3. Ride activity is logged
      final response = await supabaseClient.functions.invoke(
        'submit-review',
        body: {
          'orderId': orderId,
          'score': rating,
          'review': comment,
        },
      );

      if (response.status != 200) {
        throw Exception('Erro ao enviar avaliação: ${response.data}');
      }

      // Handle favorite driver (client-side only)
      if (isFavorite) {
        final orderData = await supabaseClient
            .from('rides')
            .select('driver_id')
            .eq('id', orderId)
            .maybeSingle();
        final driverId = orderData?['driver_id'] as String?;

        if (driverId != null) {
          try {
            // 1. Obter dados completos do motorista
            final driverProfile = await supabaseClient
                .from('profiles')
                .select('full_name, avatar_url, preset_avatar_number, vehicle_details, average_rating, rating_count, vehicle_type')
                .eq('id', driverId)
                .maybeSingle();

            if (driverProfile != null) {
              final fullName = driverProfile['full_name'] as String? ?? '';
              final nameParts = fullName.split(' ');
              final firstName = nameParts.isNotEmpty ? nameParts.first : '';
              final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
              
              final vehicleDetails = driverProfile['vehicle_details'] as Map? ?? {};
              final carModel = vehicleDetails['model']?.toString();
              final carColor = vehicleDetails['color']?.toString();
              final carPlateNumber = vehicleDetails['plateNumber']?.toString();
              
              final ratingVal = (driverProfile['average_rating'] as num?)?.toDouble();
              final ratingInt = ratingVal != null ? (ratingVal * 100).toInt() : null;
              
              final ratingsCount = (driverProfile['rating_count'] as num?)?.toInt() ?? 0;

              // 2. Inserir na tabela favorite_drivers via user-actions EF
              await supabaseClient.functions.invoke(
                'user-actions',
                body: {
                  'action': 'insert',
                  'table': 'favorite_drivers',
                  'data': {
                    'driver_id': driverId,
                    'first_name': firstName,
                    'last_name': lastName,
                    'avatar_url': driverProfile['avatar_url']?.toString(),
                    'services': [driverProfile['vehicle_type']?.toString()].nonNulls.toList(),
                    'car_model': carModel,
                    'car_color': carColor,
                    'car_plate_number': carPlateNumber,
                    'rating': ratingInt,
                    'ratings_count': ratingsCount,
                  }
                },
              );
            }

            // 3. Sincronizar array de favoritos no profiles do usuário (legado/retrocompatibilidade)
            final profileData = await supabaseClient
                .from('profiles')
                .select('favorite_drivers')
                .eq('id', uid)
                .maybeSingle();

            final favorites = List<String>.from(
                (profileData?['favorite_drivers'] as List? ?? []).cast<String>());
            if (!favorites.contains(driverId)) favorites.add(driverId);

            await supabaseClient.functions.invoke(
              'sync-profile',
              body: {'favorite_drivers': favorites},
            );
          } catch (_) {}
        }
      }

      return const Right(unit);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> skipReview({required String orderId}) async {
    try {
      return const Right(unit);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }
}
