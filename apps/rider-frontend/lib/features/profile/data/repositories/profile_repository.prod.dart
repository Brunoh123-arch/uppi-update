import 'package:dartz/dartz.dart';
import 'package:flutter_common/core/entities/media.dart';
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/entities/favorite_driver.dart';
import 'package:rider_flutter/core/entities/profile.dart';
import 'package:rider_flutter/core/error/failure.dart';
import 'package:rider_flutter/features/profile/data/models/profile_aggregations_info.dart';
import 'package:rider_flutter/features/profile/domain/repositories/profile_repository.dart';

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
      if (uid == null) {
        return const Right(ProfileAggregationsInfo(
            totalRides: 0, totalDistance: 0, favoriteDrivers: 0));
      }

      final result = await firebaseDatasource.getDocument('profiles', uid);
      if (result == null) {
        return const Right(ProfileAggregationsInfo(
            totalRides: 0, totalDistance: 0, favoriteDrivers: 0));
      }

      return Right(ProfileAggregationsInfo(
        totalRides: (result['total_rides'] as num?)?.toInt() ?? 0,
        totalDistance: (result['total_distance'] as num?)?.toInt() ?? 0,
        favoriteDrivers: 0,
      ));
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  @override
  Stream<Either<Failure, ProfileAggregationsInfo>>
      startProfileAggregationsSubscription() async* {
    final uid = firebaseDatasource.uid;
    if (uid == null) {
      yield const Right(ProfileAggregationsInfo(
          totalRides: 0, totalDistance: 0, favoriteDrivers: 0));
      return;
    }

    yield* firebaseDatasource.supabaseClient
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', uid)
        .asyncMap((_) async {
      return await getProfileAggregationsInfo();
    });
  }

  @override
  Future<Either<Failure, ProfileEntity>> uploadProfileImage({
    required Either<int, MediaEntity> image,
  }) async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) return Left(Failure.serverError('User not logged in'));

      final updates = <String, dynamic>{};
      image.fold((l) {
        updates['preset_avatar_number'] = l;
        updates['avatar_url'] = null;
      }, (r) {
        updates['preset_avatar_number'] = null;
        updates['avatar_url'] = r.address;
      });

      // Sincronizar avatar via sync-profile EF (servidor valida autoria)
      await firebaseDatasource.supabaseClient.functions.invoke(
        'sync-profile',
        body: updates,
      );

      final userData = await firebaseDatasource.getDocument('profiles', uid);
      if (userData == null) {
        return Left(Failure.serverError('Profile not found'));
      }

      MediaEntity? profileImage;
      final profilePic = userData['avatar_url'];
      if (profilePic != null && profilePic is String && profilePic.isNotEmpty) {
        profileImage = MediaEntity(id: '', address: profilePic);
      }

      final fullName = userData['full_name'] as String? ?? '';
      final nameParts = fullName.split(' ');

      return Right(ProfileEntity(
        firstName: nameParts.isNotEmpty ? nameParts.first : null,
        lastName: nameParts.length > 1 ? nameParts.sublist(1).join(' ') : null,
        countryCode: 'BR',
        email: userData['email'] as String?,
        gender: null,
        profileImage: profileImage,
        presetProfileImage: userData['preset_avatar_number'] as int?,
        number: userData['phone'] as String? ?? '',
        idNumber: userData['id_number'] as String?,
      ));
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<FavoriteDriverEntity>>>
      getFavoriteDrivers() async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) return const Right([]);

      final result = await firebaseDatasource.supabaseClient
          .from('favorite_drivers')
          .select()
          .eq('user_id', uid);

      final drivers = (result as List).map((data) {
        return FavoriteDriverEntity(
          id: data['driver_id'] as String? ?? '',
          firstName: data['first_name'] as String?,
          lastName: data['last_name'] as String?,
          avatarUrl: data['avatar_url'] as String?,
          services: (data['services'] as List<dynamic>?)?.cast<String>() ?? [],
          carModel: data['car_model'] as String?,
          carColor: data['car_color'] as String?,
          carPlateNumber: data['car_plate_number'] as String?,
          rating: data['rating'] as int?,
          ratingsCount: data['ratings_count'] as int?,
        );
      }).toList();

      return Right<Failure, List<FavoriteDriverEntity>>(drivers);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  @override
  Stream<Either<Failure, List<FavoriteDriverEntity>>>
      startFavoriteDriversSubscription() async* {
    final uid = firebaseDatasource.uid;
    if (uid == null) {
      yield const Right([]);
      return;
    }

    yield* firebaseDatasource.supabaseClient
        .from('favorite_drivers')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .map((events) {
      final drivers = events.map((data) {
        return FavoriteDriverEntity(
          id: data['driver_id'] as String? ?? '',
          firstName: data['first_name'] as String?,
          lastName: data['last_name'] as String?,
          avatarUrl: data['avatar_url'] as String?,
          services:
              (data['services'] as List<dynamic>?)?.cast<String>() ?? [],
          carModel: data['car_model'] as String?,
          carColor: data['car_color'] as String?,
          carPlateNumber: data['car_plate_number'] as String?,
          rating: data['rating'] as int?,
          ratingsCount: data['ratings_count'] as int?,
        );
      }).toList();
      return Right<Failure, List<FavoriteDriverEntity>>(drivers);
    });
  }

  @override
  Future<Either<Failure, void>> deleteFavoriteDriver({
    required FavoriteDriverEntity entity,
  }) async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid != null) {
        await firebaseDatasource.supabaseClient.functions.invoke(
          'user-actions',
          body: {
            'action': 'delete',
            'table': 'favorite_drivers',
            'id': entity.id, // Em user-actions, isso mapeia para driver_id
          },
        );
      }
      return const Right(null);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteAccount() async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid != null) {
        // Exclusão segura via Edge Function (LGPD - apaga dados sensíveis do servidor)
        await firebaseDatasource.supabaseClient.functions.invoke(
          'delete-user-account',
          body: {'userId': uid},
        );
        await firebaseDatasource.signOut();
      }
      return const Right(null);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }
}
