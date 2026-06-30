import 'package:dartz/dartz.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/entities/favorite_location.dart';
import 'package:rider_flutter/core/enums/address_type.dart';
import 'package:rider_flutter/core/error/failure.dart';

import '../../domain/repositories/favorite_locations_repository.dart';
import '../../models/update_favorite_location_input.dart';

@prod
@LazySingleton(as: FavoriteLocationsRepository)
class FavoriteLocationsRepositoryImpl implements FavoriteLocationsRepository {
  final FirebaseDatasource firebaseDatasource;

  FavoriteLocationsRepositoryImpl(this.firebaseDatasource);

  AddressType _parseType(dynamic value) {
    final str = value?.toString() ?? 'other';
    return AddressType.values.firstWhere(
      (e) => e.toString().split('.').last == str,
      orElse: () => AddressType.other,
    );
  }

  FavoriteLocationEntity _rowToEntity(Map<String, dynamic> doc) {
    return FavoriteLocationEntity(
      id: doc['id']?.toString() ?? '',
      name: doc['name'] as String? ?? '',
      place: PlaceEntity(
        coordinates: LatLngEntity(
          lat: (doc['lat'] as num?)?.toDouble() ?? 0,
          lng: (doc['lng'] as num?)?.toDouble() ?? 0,
        ),
        address: doc['address'] as String? ?? doc['details'] as String? ?? '',
        title: doc['title'] as String?,
      ),
      type: _parseType(doc['type']),
    );
  }

  Map<String, dynamic> _inputToMap(
      UpdateFavoriteLocationInput input, String userId) {
    return {
      'user_id': userId,
      'name': input.name,
      'lat': input.place.coordinates.lat,
      'lng': input.place.coordinates.lng,
      'address': input.place.address,
      'title': input.place.title,
      'type': input.type.name,
    };
  }

  @override
  Stream<Either<Failure, List<FavoriteLocationEntity>>> startFavoriteLocationsSubscription() async* {
    yield await getFavoriteLocations();
  }

  @override
  Future<Either<Failure, List<FavoriteLocationEntity>>>
      getFavoriteLocations() async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) return const Right([]);

      final result = await firebaseDatasource.supabaseClient
          .from('favorite_addresses')
          .select()
          .eq('user_id', uid);

      final locations =
          (result as List).map((data) => _rowToEntity(data)).toList();
      return Right(locations);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteFavoriteLocation(
      {required String id}) async {
    try {
      await firebaseDatasource.supabaseClient.functions.invoke(
        'user-actions',
        body: {
          'action': 'delete',
          'table': 'favorite_addresses',
          'id': id,
        },
      );
      return const Right(unit);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  @override
  Future<Either<Failure, FavoriteLocationEntity>> addFavoriteLocation({
    required UpdateFavoriteLocationInput input,
  }) async {
    try {
      final uid = firebaseDatasource.uid!;
      final result = await firebaseDatasource.supabaseClient.functions.invoke(
        'user-actions',
        body: {
          'action': 'insert',
          'table': 'favorite_addresses',
          'data': _inputToMap(input, uid),
        },
      );

      final data = result.data['data'];

      return Right(FavoriteLocationEntity(
        id: data['id']?.toString() ?? '',
        name: input.name,
        place: input.place,
        type: input.type,
      ));
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  @override
  Future<Either<Failure, FavoriteLocationEntity>> updateFavoriteLocation({
    required String id,
    required UpdateFavoriteLocationInput input,
  }) async {
    try {
      final uid = firebaseDatasource.uid!;
      await firebaseDatasource.supabaseClient.functions.invoke(
        'user-actions',
        body: {
          'action': 'update',
          'table': 'favorite_addresses',
          'id': id,
          'data': _inputToMap(input, uid),
        },
      );

      return Right(FavoriteLocationEntity(
        id: id,
        name: input.name,
        place: input.place,
        type: input.type,
      ));
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }
}
