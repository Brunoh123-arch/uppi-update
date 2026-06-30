import 'package:dartz/dartz.dart';
import 'package:uppi_motorista/core/datasources/firebase_datasource.dart';
import 'package:uppi_motorista/core/entities/profile.dart';
import 'package:uppi_motorista/core/enums/driver_status.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:uppi_motorista/features/profile/data/models/feedbacks_summary.dart';
import 'package:uppi_motorista/features/profile/data/models/profile_aggregations_info.dart';
import 'package:uppi_motorista/features/profile/domain/repositories/profile_repository.dart';
import 'package:uppi_motorista/features/profile/domain/entities/review.dart';
import 'package:flutter_common/core/entities/media.dart';
import 'package:flutter_common/core/enums/gender.dart';
import 'package:injectable/injectable.dart';

@prod
@LazySingleton(as: ProfileRepository)
class ProfileRepositoryProd implements ProfileRepository {
  final FirebaseDatasource firebaseDatasource;

  ProfileRepositoryProd(this.firebaseDatasource);

  @override
  Future<Either<Failure, ProfileAggregationsInfo>>
  getProfileAggregationsInfo() async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) return const Left(Failure.error());

      // Buscar corridas finalizadas do Supabase (o status final usado pelo
      // backend é 'finished'; 'completed' e 'waiting_for_review' são
      // estados intermediários do fluxo de finalização).
      final finishedRides = await firebaseDatasource.supabaseClient
          .from('rides')
          .select('id, distance_meters, actual_distance')
          .eq('driver_id', uid)
          .inFilter('status', ['completed', 'finished', 'waiting_for_review']);

      final ridesList = finishedRides as List;
      int totalDistance = 0;
      for (final ride in ridesList) {
        final dist = ((ride['actual_distance'] as num?) ??
                (ride['distance_meters'] as num?) ??
                0)
            .toInt();
        // Distância > 200 km numa corrida urbana é dado corrompido/teste
        if (dist > 200000) continue;
        totalDistance += dist;
      }

      // Buscar rating médio do perfil
      final profileRow = await firebaseDatasource.supabaseClient
          .from('profiles')
          .select('average_rating')
          .eq('id', uid)
          .maybeSingle();
      final rating = (profileRow?['average_rating'] as num?)?.toDouble() ?? 5.0;

      return Right(
        ProfileAggregationsInfo(
          rating: rating,
          totalRides: ridesList.length,
          totalDistance: totalDistance,
        ),
      );
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }

  @override
  Stream<Either<Failure, ProfileAggregationsInfo>>
  startProfileAggregationsSubscription() async* {
    final uid = firebaseDatasource.uid;
    if (uid == null) {
      yield const Left(Failure.error());
      return;
    }

    // Emitir imediatamente via REST — 'profiles' é uma VIEW e não emite
    // eventos realtime, então o stream sozinho nunca carregaria a tela.
    yield await getProfileAggregationsInfo();

    // Stream na tabela rides — qualquer corrida nova/finalizada do motorista
    // dispara re-fetch das agregações completas (corridas, distância, nota).
    yield* firebaseDatasource.supabaseClient
        .from('rides')
        .stream(primaryKey: ['id'])
        .eq('driver_id', uid)
        .asyncMap((_) async {
      return await getProfileAggregationsInfo();
    }).handleError((_) {});
  }

  @override
  Future<Either<Failure, ProfileEntity>> uploadProfileImage({
    required MediaEntity image,
  }) async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) return const Left(Failure.error());

      await firebaseDatasource.supabaseClient.functions.invoke(
        'sync-profile',
        body: {'avatar_url': image.address},
      );

      final data = await firebaseDatasource.supabaseClient
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();

      if (data == null) return const Left(Failure.error());

      Gender? parseGender(String? g) {
        if (g == 'male' || g == 'Male') return Gender.male;
        if (g == 'female' || g == 'Female') return Gender.female;
        return null;
      }

      final fullName = data['full_name']?.toString() ?? '';
      final nameParts = fullName.split(' ');
      final st = data['status']?.toString();
      DriverStatus driverStatus = const DriverStatus.offline();
      if (st == 'online') driverStatus = const DriverStatus.online();
      if (st == 'in_progress') driverStatus = const DriverStatus.onTrip();

      return Right(
        ProfileEntity(
          firstName: nameParts.isNotEmpty ? nameParts.first : null,
          lastName: nameParts.length > 1
              ? nameParts.sublist(1).join(' ')
              : null,
          countryCode: 'BR',
          gender: parseGender(data['gender']?.toString()),
          email: data['email']?.toString(),
          status: driverStatus,
          number: data['phone']?.toString() ?? '',
          searchRadius: data['search_distance'] as int? ?? 5000,
          profilePicture: MediaEntity(id: image.id, address: image.address),
          orders: [],
          wallets: [],
        ),
      );
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, FeedbacksSummary>> getFeedbacksSummary() async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) return const Left(Failure.error());

      // Buscar avaliações RECEBIDAS pelo motorista na tabela 'reviews'
      // (é onde a edge function submit-review grava as notas dos passageiros).
      final feedbacksResult = await firebaseDatasource.supabaseClient
          .from('reviews')
          .select()
          .eq('reviewed_id', uid)
          .order('created_at', ascending: false);

      final feedbacksList = feedbacksResult as List;

      // Calcular rating médio real dos feedbacks
      double totalRating = 0;
      for (final data in feedbacksList) {
        totalRating += (data['rating'] as num?)?.toDouble() ?? 0;
      }
      final avgRating = feedbacksList.isNotEmpty
          ? totalRating / feedbacksList.length
          : 5.0;

      final reviews = feedbacksList.map<ReviewEntity>((rd) {
        return ReviewEntity(
          serviceName: 'Corrida',
          description: rd['comment']?.toString() ?? '',
          rating: (rd['rating'] as num?)?.toDouble() ?? 5.0,
          goodPoints: const [],
        );
      }).toList();

      return Right(
        FeedbacksSummary(
          averageRating: avgRating,
          goodPoints: const [],
          badPoints: const [],
          goodReviews: reviews,
        ),
      );
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }

  @override
  Stream<Either<Failure, FeedbacksSummary>>
  startFeedbacksSummarySubscription() async* {
    final uid = firebaseDatasource.uid;
    if (uid == null) {
      yield const Left(Failure.error());
      return;
    }

    // Emitir imediatamente via REST — não depender do websocket realtime.
    yield await getFeedbacksSummary();

    // Stream na tabela reviews — qualquer nova avaliação recebida
    // dispara re-cálculo do resumo de feedbacks.
    yield* firebaseDatasource.supabaseClient
        .from('reviews')
        .stream(primaryKey: ['id'])
        .eq('reviewed_id', uid)
        .asyncMap((_) async {
      return await getFeedbacksSummary();
    }).handleError((_) {});
  }
}
