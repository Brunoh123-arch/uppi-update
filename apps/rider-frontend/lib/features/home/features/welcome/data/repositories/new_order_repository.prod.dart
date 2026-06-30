import 'package:dartz/dartz.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/entities/favorite_location.dart';
import 'package:rider_flutter/core/enums/address_type.dart';
import 'package:rider_flutter/core/error/failure.dart';

import '../../../welcome/domain/repositories/new_order_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@prod
@LazySingleton(as: NewOrderRepository)
class NewOrderRepositoryImpl implements NewOrderRepository {
  final FirebaseDatasource firebaseDatasource;
  final SupabaseClient supabaseClient;

  NewOrderRepositoryImpl(this.firebaseDatasource)
      : supabaseClient = Supabase.instance.client;

  AddressType _parseType(dynamic value) {
    final str = value?.toString() ?? 'other';
    return AddressType.values.firstWhere(
      (e) => e.toString().split('.').last == str,
      orElse: () => AddressType.other,
    );
  }

  @override
  Future<Either<Failure, (List<FavoriteLocationEntity>, List<PlaceEntity>)>>
      getDestinationSuggestions() async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) return const Right(([], []));

      // Buscar endereços favoritos da tabela normalizada favorite_addresses
      List<FavoriteLocationEntity> favoriteLocations = [];
      try {
        final favRows = await supabaseClient
            .from('favorite_addresses')
            .select()
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(20);
        favoriteLocations = (favRows as List).map((addr) {
          return FavoriteLocationEntity(
            id: addr['id']?.toString() ?? '',
            name: addr['title']?.toString() ?? addr['name']?.toString() ?? '',
            place: PlaceEntity(
              coordinates: LatLngEntity(
                lat: (addr['lat'] as num?)?.toDouble() ?? 0,
                lng: (addr['lng'] as num?)?.toDouble() ?? 0,
              ),
              address: addr['address']?.toString() ?? '',
            ),
            type: _parseType(addr['type']),
          );
        }).toList();
      } catch (_) {}

      // Buscar últimos destinos das corridas recentes no Supabase
      final ordersSnapshot = await supabaseClient
          .from('rides')
          .select('dropoff_address, dropoff_lat, dropoff_lng')
          .eq('rider_id', uid)
          .order('created_at', ascending: false)
          .limit(10);

      final uniquePlaces = <String, PlaceEntity>{};
      for (final doc in ordersSnapshot as List<dynamic>) {
        final address = doc['dropoff_address'] as String? ?? 'Unknown Address';
        final lat = (doc['dropoff_lat'] as num?)?.toDouble() ?? 0;
        final lng = (doc['dropoff_lng'] as num?)?.toDouble() ?? 0;
        final key = address.trim().toLowerCase();
        if (!uniquePlaces.containsKey(key)) {
          uniquePlaces[key] = PlaceEntity(
            coordinates: LatLngEntity(lat: lat, lng: lng),
            address: address,
          );
        }
      }
      final places = uniquePlaces.values.toList();

      return Right((favoriteLocations, places));
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }
}
