import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_common/core/entities/driver_location.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:flutter_common/core/entities/payment_method_union.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/entities/order.dart';
import 'package:rider_flutter/core/entities/driver.dart';
import 'package:rider_flutter/core/error/failure.dart';

import '../domain/repositories/home_repository.dart';
import 'package:rider_flutter/core/mappers/firestore_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@prod
@LazySingleton(as: HomeRepository)
class HomeRepositoryImpl implements HomeRepository {
  final FirebaseDatasource firebaseDatasource;
  final SupabaseClient supabaseClient;

  // Cache de motoristas próximos recebidos via Broadcast
  final Map<String, DriverLocation> _driversCache = {};
  final Map<String, RealtimeChannel> _activeChannels = {};
  final StreamController<List<DriverLocation>> _driversStreamController =
      StreamController<List<DriverLocation>>.broadcast();

  Timer? _cacheCleanupTimer;

  @override
  Stream<List<DriverLocation>> get driversAroundStream =>
      _driversStreamController.stream;

  HomeRepositoryImpl(this.firebaseDatasource)
      : supabaseClient = Supabase.instance.client {
    _startListeningBroadcast();
  }

  // Timestamps de última atualização de cada motorista
  final Map<String, DateTime> _driversLastSeen = {};

  // Rastreamento híbrido otimizado: escuta individualmente apenas os canais
  // track_driver_$driverId dos motoristas localizados na busca inicial.
  void _startListeningBroadcast() {
    // Limpa cache e canais inativos periodicamente
    _cacheCleanupTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final cutoff = DateTime.now().subtract(const Duration(minutes: 2));
      _driversLastSeen.removeWhere((id, lastSeen) {
        if (lastSeen.isBefore(cutoff)) {
          _driversCache.remove(id);
          final channel = _activeChannels.remove(id);
          if (channel != null) {
            try {
              supabaseClient.removeChannel(channel);
            } catch (_) {}
          }
          return true;
        }
        return false;
      });
      if (!_driversStreamController.isClosed) {
        _driversStreamController.add(_driversCache.values.toList());
      }
    });
  }

  void _subscribeToDriverBroadcast(String driverId) {
    if (_activeChannels.containsKey(driverId)) return;

    final channel = supabaseClient.channel('track_driver_$driverId');
    channel.onBroadcast(
      event: 'location_update',
      callback: (payload) {
        final lat = (payload['lat'] as num?)?.toDouble();
        final lng = (payload['lng'] as num?)?.toDouble();
        final heading = (payload['heading'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          final loc = DriverLocation(
            id: driverId,
            lat: lat,
            lng: lng,
            rotation: heading?.toInt() ?? 0,
            vehicleType: payload['vehicle_type'] as String?,
            markerUrl: payload['marker_url'] as String?,
          );
          _driversCache[driverId] = loc;
          _driversLastSeen[driverId] = DateTime.now();

          if (!_driversStreamController.isClosed) {
            _driversStreamController.add(_driversCache.values.toList());
          }
        }
      },
    );
    try {
      channel.subscribe();
      _activeChannels[driverId] = channel;
    } catch (_) {}
  }

  @override
  Future<Either<Failure, (OrderEntity, DriverLocation?)?>>
      getCurrentOrder() async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) return const Right(null);

      final queryResult = await supabaseClient
          .from('rides')
          .select()
          .eq('rider_id', uid)
          .not('status', 'in', '("completed","finished","canceled","rider_canceled","driver_canceled","expired","no_driver","no_close_found")')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (queryResult == null) return const Right(null);

      final orderData = queryResult;
      final statusStr = orderData['status'] as String?;

      String mappedStatus;
      switch (statusStr) {
        case 'requested':
        case 'searching':
          mappedStatus = 'Requested';
          break;
        case 'accepted':
        case 'driver_accepted':
          mappedStatus = 'DriverAccepted';
          break;
        case 'arrived':
          mappedStatus = 'Arrived';
          break;
        case 'in_progress':
        case 'started':
          mappedStatus = 'Started';
          break;
        case 'waiting_for_review':
          mappedStatus = 'WaitingForReview';
          break;
        default:
          mappedStatus = 'WaitingForPostPay';
      }

      final pickupLat = (orderData['pickup_lat'] as num?)?.toDouble() ?? 0.0;
      final pickupLng = (orderData['pickup_lng'] as num?)?.toDouble() ?? 0.0;
      final pickupAddress = orderData['pickup_address']?.toString() ?? '';
      
      final dropoffLat = (orderData['dropoff_lat'] as num?)?.toDouble() ?? 0.0;
      final dropoffLng = (orderData['dropoff_lng'] as num?)?.toDouble() ?? 0.0;
      final dropoffAddress = orderData['dropoff_address']?.toString() ?? '';

      final List<PlaceEntity> waypoints = [
        PlaceEntity(
          coordinates: LatLngEntity(lat: pickupLat, lng: pickupLng),
          address: pickupAddress,
        ),
        PlaceEntity(
          coordinates: LatLngEntity(lat: dropoffLat, lng: dropoffLng),
          address: dropoffAddress,
        ),
      ];

      final mockData = {
        'id': orderData['id'].toString(),
        'status': mappedStatus,
        'createdAt': orderData['created_at'],
        'distanceBest': (orderData['distance_meters'] as num?)?.toInt() ?? 0,
        'durationBest': (orderData['duration_seconds'] as num?)?.toInt() ?? 0,
        'costBest': orderData['fare'] ?? 0.0,
        'etaPickup': orderData['eta_pickup'],
        'expectedAt': orderData['expected_at'],
        'startedAt': orderData['started_at'],
        'boarding_pin': orderData['boarding_pin'],
      };

      final driverId = orderData['driver_id']?.toString();
      DriverEntity? driverEntity;
      if (driverId != null && driverId.isNotEmpty) {
        try {
          final driverData = await supabaseClient
              .from('profiles')
              .select()
              .eq('id', driverId)
              .maybeSingle();
          if (driverData != null) {
            final dbRating = double.tryParse(driverData['rating']?.toString() ?? '5.0') ?? 5.0;
            driverEntity = DriverEntity(
              firstName: driverData['full_name']?.toString() ?? 'Motorista',
              lastName: '',
              mobileNumber: driverData['id']?.toString() ?? '',
              imageUrl: driverData['avatar_url']?.toString() ??
                  'https://ui-avatars.com/api/?name=Motorista&background=096EFF&color=fff&size=128',
              rating: (dbRating * 20).toInt(),
              ratingCount: (driverData['rating_count'] as num?)?.toInt() ?? 0,
              vehiclePlateNumber:
                  driverData['vehicle_details']?['plate']?.toString() ?? '',
              vehicleColor:
                  driverData['vehicle_details']?['color']?.toString() ?? '',
              vehicleModel:
                  driverData['vehicle_details']?['model']?.toString() ?? '',
            );
          }
        } catch (_) {}
      }

      final paymentMethodStr = orderData['payment_method']?.toString();
      PaymentMethodUnion? paymentMethod;
      if (paymentMethodStr == 'cash') {
        paymentMethod = const PaymentMethodUnion.cash();
      } else if (paymentMethodStr == 'wallet') {
        paymentMethod = const PaymentMethodUnion.wallet();
      } else if (paymentMethodStr != null && paymentMethodStr.isNotEmpty) {
        paymentMethod = const PaymentMethodUnion.cash();
      }

      final order = FirestoreMapper.toOrderEntity(mockData).copyWith(
        waypoints: waypoints,
        driver: driverEntity,
        paymentMethod: paymentMethod,
      );

      // Tenta pegar posição do motorista do cache Broadcast primeiro
      DriverLocation? driverLocation;

      if (driverId != null && driverId.isNotEmpty) {
        // 1. Cache Broadcast (sem custo de banco)
        driverLocation = _driversCache[driverId];

        // 2. Fallback: lê do banco apenas se não tiver no cache
        if (driverLocation == null) {
          final driverDoc = await supabaseClient
              .from('driver_locations')
              .select()
              .eq('driver_id', driverId)
              .maybeSingle();

          if (driverDoc != null) {
            final lat = (driverDoc['lat'] as num?)?.toDouble();
            final lng = (driverDoc['lng'] as num?)?.toDouble();
            final heading = (driverDoc['heading'] as num?)?.toDouble();
            if (lat != null && lng != null) {
              driverLocation = DriverLocation(
                id: driverId,
                lat: lat,
                lng: lng,
                rotation: heading?.toInt() ?? 0,
                vehicleType: null,
                markerUrl: null,
              );
            }
          }
        }
      }

      return Right((order, driverLocation));
    } catch (e) {
      return Left(Failure.serverError('Não foi possível obter os dados da corrida atual. Tente novamente.'));
    }
  }

  @override
  Future<Either<Failure, List<DriverLocation>>> getDriversAround(
      LatLng origin) async {
    try {
      // Tenta puxar o raio de busca oficial configurado no Admin Panel (em km)
      int searchRadiusMeters = 5000; // Fallback 5km
      try {
        final configRow = await supabaseClient
            .from('app_settings')
            .select('value')
            .eq('key', 'driver_search_radius')
            .maybeSingle();
        if (configRow != null) {
          final radiusKm = int.tryParse(configRow['value']?.toString() ?? '') ?? 5;
          searchRadiusMeters = radiusKm * 1000;
        }
      } catch (_) {}

      // Em vez de buscar todos do banco (inviável com 1M+ users),
      // chama a função RPC com PostGIS para pegar no raio correto
      final queryResult = await supabaseClient.rpc(
        'nearby_drivers',
        params: {
          'p_lat': origin.latitude,
          'p_lng': origin.longitude,
          'p_radius_meters': searchRadiusMeters,
        },
      );

      final drivers = <DriverLocation>[];
      for (final data in queryResult) {
        final lat = (data['lat'] as num?)?.toDouble();
        final lng = (data['lng'] as num?)?.toDouble();
        final heading = (data['heading'] as num?)?.toDouble();
        final driverId = data['driver_id']?.toString();

        if (lat != null && lng != null) {
          final loc = DriverLocation(
            id: driverId,
            lat: lat,
            lng: lng,
            rotation: heading?.toInt(),
            vehicleType: data['vehicle_type'] as String?,
            markerUrl: data['marker_url'] as String?,
          );
          drivers.add(loc);

          if (driverId != null && driverId.isNotEmpty) {
            _driversCache[driverId] = loc;
            _driversLastSeen[driverId] = DateTime.now();
            _subscribeToDriverBroadcast(driverId);
          }
        }
      }

      if (!_driversStreamController.isClosed) {
        _driversStreamController.add(_driversCache.values.toList());
      }

      return Right(drivers);
    } catch (e) {
      debugPrint('[HomeRepository] getDriversAround error: $e. Retornando lista vazia.');
      return const Right([]);
    }
  }

  void dispose() {
    _cacheCleanupTimer?.cancel();
    _driversCache.clear();
    _driversLastSeen.clear();
    for (final channel in _activeChannels.values) {
      try {
        supabaseClient.removeChannel(channel);
      } catch (_) {}
    }
    _activeChannels.clear();
    _driversStreamController.close();
  }
}
