import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:collection/collection.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_common/core/entities/cancel_reason.dart';
import 'package:flutter_common/core/entities/payment_method_union.dart';
import 'package:flutter_common/core/entities/payment_gateway.dart';
import 'package:flutter_common/core/entities/saved_payment_method.dart';
import 'package:flutter_common/core/enums/card_type.dart';
import 'package:flutter_common/core/enums/gateway_link_method.dart';
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:flutter_common/core/entities/driver_location.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:flutter_common/features/chat/chat.dart';
import 'package:rider_flutter/core/entities/order.dart';
import 'package:rider_flutter/core/error/failure.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../domain/repositories/track_order_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rider_flutter/core/entities/driver.dart';
import 'package:flutter_common/core/enums/order_status.dart';

@prod
@LazySingleton(as: TrackOrderRepository)
class TrackOrderRepositoryImpl implements TrackOrderRepository {
  final FirebaseDatasource firebaseDatasource;
  final SupabaseClient supabaseClient;
  final List<ChatMessageEntity> messagesSent = [];

  String? _cachedRideId;
  List<LatLngEntity> _cachedRideDirections = const [];
  List<LatLngEntity> _cachedDriverDirections = const [];
  double? _cachedLastDriverLat;
  double? _cachedLastDriverLng;
  double? _lastKnownDriverLat;
  double? _lastKnownDriverLng;
  // Tipo de veículo do motorista (carro/moto) + URL de marcador custom.
  // Cacheado da tabela driver_locations para o marcador do passageiro mostrar
  // o veículo correto (ex.: moto não aparecer como carro). O broadcast não
  // carrega esse dado, então reaproveitamos o cache aqui.
  String? _driverVehicleType;
  String? _driverMarkerUrl;
  int? _cachedDriverEtaSeconds;

  TrackOrderRepositoryImpl(this.firebaseDatasource)
      : supabaseClient = Supabase.instance.client;

  ChatMessageEntity _rowToMessage(Map<String, dynamic> row) {
    return ChatMessageEntity(
      id: row['id'] as String? ?? '',
      message: row['content'] as String? ?? '',
      isSender: !(row['sent_by_driver'] as bool? ?? false),
      createdAt: row['created_at'] != null
          ? (DateTime.tryParse(row['created_at'].toString())?.toLocal() ?? DateTime.now())
          : DateTime.now(),
    );
  }

  Future<List<LatLngEntity>> _getGoogleRoute(List<LatLngEntity> waypoints) async {
    try {
      String googleApiKey = '';
      try {
        final configRow = await supabaseClient
            .from('app_settings')
            .select('value')
            .eq('key', 'google_map_api_key')
            .maybeSingle();
        if (configRow != null && configRow['value'] != null) {
          googleApiKey = configRow['value'].toString();
        }
      } catch (_) {}

      if (googleApiKey.isNotEmpty && waypoints.length >= 2) {
        final origin = '${waypoints.first.lat},${waypoints.first.lng}';
        final destination = '${waypoints.last.lat},${waypoints.last.lng}';
        String url = 'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&key=$googleApiKey';
        if (waypoints.length > 2) {
          final intermediates = waypoints.sublist(1, waypoints.length - 1)
              .map((w) => 'via:${w.lat},${w.lng}')
              .join('|');
          url += '&waypoints=${Uri.encodeComponent(intermediates)}';
        }

        debugPrint('[Google-Rider] Requesting route: $url');
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final directionsData = json.decode(response.body);
          if (directionsData['status'] == 'OK' && directionsData['routes'] != null && (directionsData['routes'] as List).isNotEmpty) {
            final route = directionsData['routes'][0];
            // Extrair duração da rota para cálculo de ETA client-side
            try {
              final legs = route['legs'] as List?;
              if (legs != null && legs.isNotEmpty) {
                final durationValue = legs[0]['duration']?['value'] as int?;
                if (durationValue != null) {
                  _cachedDriverEtaSeconds = durationValue;
                  debugPrint('[Google-Rider] Driver ETA: ${durationValue}s (${(durationValue / 60).round()} min)');
                }
              }
            } catch (_) {}
            final overviewPolyline = route['overview_polyline'];
            if (overviewPolyline != null && overviewPolyline['points'] != null) {
              final pts = _decodePolyline(overviewPolyline['points'].toString());
              debugPrint('[Google-Rider] Route parsed with ${pts.length} points');
              return pts;
            }
          } else {
            debugPrint('[Google-Rider] Google Maps status: ${directionsData['status']}');
          }
        }
      }
    } catch (e) {
      debugPrint('[Google-Rider] Exception during Google Directions call: $e');
    }

    // FALLBACK: OSRM se o Google Maps falhar ou a chave de API não estiver ativa
    try {
      debugPrint('[OSRM-Rider] Falling back to OSRM routing');
      String osrmBaseUrl = 'https://router.project-osrm.org';
      try {
        final configRow = await supabaseClient
            .from('app_settings')
            .select('value')
            .eq('key', 'osrm_routing_url')
            .maybeSingle();
        if (configRow != null && configRow['value'] != null && configRow['value'].toString().isNotEmpty) {
          osrmBaseUrl = configRow['value'].toString().replaceAll(RegExp(r'/$'), '');
        }
      } catch (_) {}

      final coords = waypoints.map((w) => '${w.lng},${w.lat}').join(';');
      final url = '$osrmBaseUrl/route/v1/driving/$coords?overview=full&geometries=geojson';

      debugPrint('[OSRM-Rider] Requesting route: $url');
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'UppiRiderApp/1.0.0'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null && data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry'];
          if (geometry != null && geometry['coordinates'] != null) {
            final coordsList = geometry['coordinates'] as List;
            final routePoints = coordsList
                .map((c) => LatLngEntity(
                      lat: (c[1] as num).toDouble(),
                      lng: (c[0] as num).toDouble(),
                    ))
                .toList();
            return routePoints;
          }
        }
      }
    } catch (e) {
      debugPrint('[OSRM-Rider] Fallback Exception: $e');
    }
    return [];
  }

  List<LatLngEntity> _decodePolyline(String polyline) {
    List<LatLngEntity> points = [];
    int index = 0, len = polyline.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;
      points.add(LatLngEntity(lat: lat / 1E5, lng: lng / 1E5));
    }
    return points;
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    final double dLat = (lat2 - lat1) * pi / 180.0;
    final double dLon = (lon2 - lon1) * pi / 180.0;
    final double rLat1 = lat1 * pi / 180.0;
    final double rLat2 = lat2 * pi / 180.0;

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        sin(dLon / 2) * sin(dLon / 2) * cos(rLat1) * cos(rLat2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return 6371000 * c; // Earth radius in meters
  }

  /// Converte dados brutos da tabela `rides` para [OrderEntity].
  /// Compartilhado entre o stream CDC e o polling de fallback.
  Future<OrderEntity> _mapRideDataToOrder(
    Map<String, dynamic> data,
    OrderEntity orderEntity,
  ) async {
    final rideId = data['id']?.toString() ?? '';
    final statusStr = data['status']?.toString() ?? 'requested';
    OrderStatus status = OrderStatus.requested;
    if (statusStr == 'accepted' || statusStr == 'driver_accepted') status = OrderStatus.driverAccepted;
    if (statusStr == 'arrived') status = OrderStatus.arrived;
    if (statusStr == 'in_progress' || statusStr == 'started') status = OrderStatus.started;
    if (statusStr == 'waiting_for_review') status = OrderStatus.waitingForReview;
    if (statusStr == 'completed' || statusStr == 'finished') status = OrderStatus.finished;
    if (statusStr == 'canceled' || statusStr == 'rider_canceled' || statusStr == 'driver_canceled' || statusStr == 'no_driver' || statusStr == 'no_close_found' || statusStr == 'expired') status = OrderStatus.riderCanceled;

    // 1. MAPEAMENTO DE DADOS DO MOTORISTA E SEU RATING CORRETO
    DriverEntity? driverEntity = orderEntity.driver;
    final driverId = data['driver_id']?.toString();
    double? driverLat;
    double? driverLng;

    if (driverId != null && (driverEntity == null || driverEntity.mobileNumber != driverId)) {
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
            rating: (dbRating * 20).toInt(), // Multiplicar por 20 para bater com a divisão /20 no widget
            ratingCount: (driverData['rating_count'] as num?)?.toInt() ?? 0,
            vehiclePlateNumber:
                driverData['vehicle_details']?['plate']?.toString() ?? '',
            vehicleColor:
                driverData['vehicle_details']?['color']?.toString() ?? '',
            vehicleModel:
                driverData['vehicle_details']?['model']?.toString() ?? '',
          );
        }
      } catch (e, st) {
        Sentry.captureException(e, stackTrace: st);
      }
    }

    // 2. BUSCA DO NOME DO SERVIÇO E IMAGEM URL DO BANCO
    String serviceName = orderEntity.serviceName;
    String serviceImageUrl = 'https://cdn-icons-png.flaticon.com/512/3097/3097180.png';
    final supabaseUrl = dotenv.maybeGet('SUPABASE_URL') ?? 'https://kqfmahrxjuqlvxngeurj.supabase.co';
    if (orderEntity.serviceImageUrl.isNotEmpty && !orderEntity.serviceImageUrl.contains('uploads.Uppi.io')) {
      if (orderEntity.serviceImageUrl.startsWith('http://') || orderEntity.serviceImageUrl.startsWith('https://')) {
        serviceImageUrl = orderEntity.serviceImageUrl;
      } else {
        serviceImageUrl = '$supabaseUrl/storage/v1/object/public/service-images/${orderEntity.serviceImageUrl}';
      }
    }
    
    final serviceId = data['service_id']?.toString();
    if (serviceId != null && (serviceName == serviceId || serviceName == 'Standard' || serviceImageUrl == 'https://cdn-icons-png.flaticon.com/512/3097/3097180.png')) {
      try {
        final serviceData = await supabaseClient
            .from('services')
            .select('name, image_url')
            .eq('id', serviceId)
            .maybeSingle();
        if (serviceData != null) {
          serviceName = serviceData['name']?.toString() ?? 'Uppi';
          final dbImg = serviceData['image_url']?.toString();
          if (dbImg != null && dbImg.isNotEmpty && !dbImg.contains('uploads.Uppi.io')) {
            if (dbImg.startsWith('http://') || dbImg.startsWith('https://')) {
              serviceImageUrl = dbImg;
            } else {
              serviceImageUrl = '$supabaseUrl/storage/v1/object/public/service-images/$dbImg';
            }
          }
        }
      } catch (_) {}
    }

    // 3. RECUPERAR POSIÇÃO ATUAL DO MOTORISTA PARA CALCULAR driverDirections (HÍBRIDO BROADCAST + DB)
    final isRideActive = status == OrderStatus.driverAccepted ||
        status == OrderStatus.arrived ||
        status == OrderStatus.started;
    if (isRideActive && driverId != null) {
      if (_lastKnownDriverLat != null && _lastKnownDriverLng != null) {
        driverLat = _lastKnownDriverLat;
        driverLng = _lastKnownDriverLng;
      } else {
        try {
          final locData = await supabaseClient
              .from('driver_locations')
              .select('lat, lng')
              .eq('driver_id', driverId)
              .maybeSingle();
          if (locData != null) {
            driverLat = (locData['lat'] as num?)?.toDouble();
            driverLng = (locData['lng'] as num?)?.toDouble();
          }
        } catch (_) {}
      }
    }

    // 4. CÁLCULO E CACHE DE ROTAS DO PASSAGEIRO E SEUS WAYPOINTS
    List<LatLngEntity> rideDirections = orderEntity.rideDirections;
    List<LatLngEntity> driverDirections = orderEntity.driverDirections;

    final pickupLat = (data['pickup_lat'] as num?)?.toDouble();
    final pickupLng = (data['pickup_lng'] as num?)?.toDouble();
    final dropoffLat = (data['dropoff_lat'] as num?)?.toDouble();
    final dropoffLng = (data['dropoff_lng'] as num?)?.toDouble();

    debugPrint('[TrackOrder] _mapRideDataToOrder: status=$status, pickup=($pickupLat,$pickupLng), dropoff=($dropoffLat,$dropoffLng), driverLat=$driverLat, driverLng=$driverLng');
    debugPrint('[TrackOrder] orderEntity.rideDirections.length=${orderEntity.rideDirections.length}, orderEntity.driverDirections.length=${orderEntity.driverDirections.length}');

    List<PlaceEntity> waypoints = orderEntity.waypoints;
    if (waypoints.isEmpty && pickupLat != null && pickupLng != null && dropoffLat != null && dropoffLng != null) {
      final pickupAddress = data['pickup_address']?.toString() ?? 'Origem';
      final dropoffAddress = data['dropoff_address']?.toString() ?? 'Destino';
      waypoints = [
        PlaceEntity(
          coordinates: LatLngEntity(lat: pickupLat, lng: pickupLng),
          address: pickupAddress,
        ),
        PlaceEntity(
          coordinates: LatLngEntity(lat: dropoffLat, lng: dropoffLng),
          address: dropoffAddress,
        ),
      ];
    }

    if (_cachedRideId != rideId) {
      _cachedRideId = rideId;
      _cachedRideDirections = const [];
      _cachedDriverDirections = const [];
      _cachedLastDriverLat = null;
      _cachedLastDriverLng = null;
    }

    // Rota do motorista até o ponto de embarque (status: driverAccepted)
    if (status == OrderStatus.driverAccepted && pickupLat != null && pickupLng != null && driverLat != null && driverLng != null) {
      bool shouldFetch = true;
      if (_cachedLastDriverLat != null && _cachedLastDriverLng != null) {
        final dist = _calculateDistance(driverLat, driverLng, _cachedLastDriverLat!, _cachedLastDriverLng!);
        if (dist < 100 && _cachedDriverDirections.isNotEmpty) {
          shouldFetch = false;
        }
      }
      if (shouldFetch) {
        debugPrint('[TrackOrder] Buscando rota do motorista até embarque...');
        _cachedLastDriverLat = driverLat;
        _cachedLastDriverLng = driverLng;
        _cachedDriverDirections = await _getGoogleRoute([
          LatLngEntity(lat: driverLat, lng: driverLng),
          LatLngEntity(lat: pickupLat, lng: pickupLng),
        ]);
        debugPrint('[TrackOrder] driverDirections: ${_cachedDriverDirections.length} pontos');
      }
      driverDirections = _cachedDriverDirections;
    }

    // Rota do passageiro: embarque → desembarque (status: started OU driverAccepted/arrived)
    // Calcula a rota do passageiro assim que os dados estiverem disponíveis,
    // não apenas quando o status for "started", para que a rota esteja pronta.
    if (pickupLat != null && pickupLng != null && dropoffLat != null && dropoffLng != null) {
      if (_cachedRideDirections.isEmpty) {
        debugPrint('[TrackOrder] Buscando rota do passageiro (pickup→dropoff)... status=$status');
        _cachedRideDirections = await _getGoogleRoute([
          LatLngEntity(lat: pickupLat, lng: pickupLng),
          LatLngEntity(lat: dropoffLat, lng: dropoffLng),
        ]);
        debugPrint('[TrackOrder] rideDirections: ${_cachedRideDirections.length} pontos');
      }
      rideDirections = _cachedRideDirections;
    }

    final distanceBest = (data['distance_meters'] as num?)?.toInt() ?? orderEntity.distance;
    final durationBest = (data['duration_seconds'] as num?)?.toInt() ?? orderEntity.duration;

    DateTime? etaPickup = orderEntity.etaPickup;
    if (data['eta_pickup'] != null) {
      try {
        etaPickup = DateTime.parse(data['eta_pickup'].toString()).toLocal();
      } catch (_) {}
    }
    // Fallback: calcular ETA client-side a partir da duração da rota do motorista
    if (etaPickup == null && _cachedDriverEtaSeconds != null && status == OrderStatus.driverAccepted) {
      etaPickup = DateTime.now().add(Duration(seconds: _cachedDriverEtaSeconds!));
      debugPrint('[TrackOrder] ETA calculado client-side: ${_cachedDriverEtaSeconds}s → $etaPickup');
    }

    DateTime? startedAt = orderEntity.startedAt;
    if (data['started_at'] != null) {
      try {
        startedAt = DateTime.parse(data['started_at'].toString()).toLocal();
      } catch (_) {}
    }

    DateTime? expectedAt = orderEntity.expectedAt;
    if (data['expected_at'] != null) {
      try {
        expectedAt = DateTime.parse(data['expected_at'].toString()).toLocal();
      } catch (_) {}
    }

    final paymentMethodStr = data['payment_method']?.toString();
    PaymentMethodUnion? paymentMethod = orderEntity.paymentMethod;
    if (paymentMethodStr != null) {
      if (paymentMethodStr == 'cash') {
        paymentMethod = const PaymentMethodUnion.cash();
      } else if (paymentMethodStr == 'wallet') {
        paymentMethod = const PaymentMethodUnion.wallet();
      } else if (paymentMethodStr.isNotEmpty) {
        paymentMethod = const PaymentMethodUnion.cash();
      }
    }

    int? arrivedAtWaypointIndex = orderEntity.arrivedAtWaypointIndex;
    final destinationArrivedTo = data['destination_arrived_to'] as int?;
    if (destinationArrivedTo != null) {
      arrivedAtWaypointIndex = destinationArrivedTo + 1;
    } else if (status == OrderStatus.started) {
      arrivedAtWaypointIndex = 0;
    }

    return orderEntity.copyWith.call(
      status: status,
      driver: driverEntity,
      serviceName: serviceName,
      serviceImageUrl: serviceImageUrl,
      rideDirections: rideDirections,
      driverDirections: driverDirections,
      waypoints: waypoints,
      paymentMethod: paymentMethod,
      distance: distanceBest,
      duration: durationBest,
      etaPickup: etaPickup,
      startedAt: startedAt,
      expectedAt: expectedAt ?? orderEntity.expectedAt,
      arrivedAtWaypointIndex: arrivedAtWaypointIndex,
      boardingPin: data['boarding_pin']?.toString(),
    );
  }

  @override
  Stream<(OrderEntity, DriverLocation?)> listenToOrderUpdates({
    required OrderEntity orderEntity,
  }) {
    // Escutar ordem em tempo real via Supabase Realtime CDC, preenchendo as rotas imediatamente
    final orderStream = Rx.defer<OrderEntity>(() {
      // 1. Fetch inicial reativo para obter a corrida atualizada do banco e calcular a rota imediatamente
      final initialFetchStream = Stream.fromFuture(() async {
        try {
          final data = await supabaseClient
              .from('rides')
              .select()
              .eq('id', orderEntity.id)
              .maybeSingle();
          if (data != null) {
            debugPrint('[TrackOrder] Fetch inicial com sucesso. Mapeando rota...');
            return await _mapRideDataToOrder(data, orderEntity);
          }
        } catch (e) {
          debugPrint('[TrackOrder] Erro no fetch inicial da corrida: $e');
        }
        return orderEntity;
      }());

      // 2. Stream do CDC em tempo real para mudanças subsequentes
      final realTimeStream = supabaseClient
          .from('rides')
          .stream(primaryKey: ['id'])
          .eq('id', orderEntity.id)
          .where((events) => events.isNotEmpty)
          .asyncMap((events) async {
            final data = events.first;
            return await _mapRideDataToOrder(data, orderEntity);
          });

      // Começa com a ordem que já temos para resposta instantânea,
      // depois concatena o fetch inicial (que busca a rota assincronamente)
      // e depois se inscreve na stream em tempo real para atualizações.
      return Rx.concat([
        Stream.value(orderEntity),
        initialFetchStream,
        realTimeStream,
      ]);
    })
    .distinct((a, b) =>
        a.status == b.status &&
        a.driver?.mobileNumber == b.driver?.mobileNumber &&
        listEquals(a.driverDirections, b.driverDirections) &&
        listEquals(a.rideDirections, b.rideDirections) &&
        listEquals(a.waypoints, b.waypoints));


    // Escutar localização do motorista em tempo real via Supabase Broadcast
    final driverLocationStream = orderStream.switchMap((order) {
      final driverId = order.driver?.mobileNumber;
      if (driverId == null || driverId.isEmpty) {
        return Stream<DriverLocation?>.value(null);
      }

      final controller = StreamController<DriverLocation?>();
      RealtimeChannel? channel;
      Timer? reconnectTimer;
      int reconnectDelay = 2; // Começa com 2 segundos para reconexão

      // 1. Busca a posição inicial imediatamente do banco de dados (apenas uma única vez!)
      void fetchInitialPosition() async {
        try {
          final row = await supabaseClient
              .from('driver_locations')
              .select('lat, lng, heading, vehicle_type, marker_url')
              .eq('driver_id', driverId)
              .maybeSingle();
          if (row != null && !controller.isClosed) {
            final lat = (row['lat'] as num?)?.toDouble();
            final lng = (row['lng'] as num?)?.toDouble();
            final heading = (row['heading'] as num?)?.toDouble();
            // Cacheia o veículo para reusar nos updates via broadcast.
            _driverVehicleType = row['vehicle_type']?.toString();
            _driverMarkerUrl = row['marker_url']?.toString();
            if (lat != null && lng != null) {
              _lastKnownDriverLat = lat;
              _lastKnownDriverLng = lng;
              controller.add(DriverLocation(
                id: driverId,
                lat: lat,
                lng: lng,
                rotation: heading?.toInt() ?? 0,
                vehicleType: _driverVehicleType,
                markerUrl: _driverMarkerUrl,
              ));
            }
          }
        } catch (e, st) {
          Sentry.captureException(e, stackTrace: st);
        }
      }

      fetchInitialPosition();

      // 2. Escuta via Broadcast reativo e autogestor com reconexão exponencial
      void subscribeToBroadcast() {
        if (controller.isClosed) return;

        final channelName = 'track_driver_$driverId';
        channel = supabaseClient.channel(channelName);

        channel!.onBroadcast(
          event: 'location_update',
          callback: (payload) {
            if (payload['driver_id']?.toString() == driverId) {
              final lat = (payload['lat'] as num?)?.toDouble();
              final lng = (payload['lng'] as num?)?.toDouble();
              final heading = (payload['heading'] as num?)?.toDouble();

              if (lat != null && lng != null && !controller.isClosed) {
                _lastKnownDriverLat = lat;
                _lastKnownDriverLng = lng;
                controller.add(DriverLocation(
                  id: driverId,
                  lat: lat,
                  lng: lng,
                  rotation: heading?.toInt() ?? 0,
                  vehicleType: _driverVehicleType,
                  markerUrl: _driverMarkerUrl,
                ));
              }
            }
          },
        );

        channel!.subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            reconnectDelay = 2; // Reseta delay de reconexão no sucesso
          } else if (status == RealtimeSubscribeStatus.channelError ||
                     status == RealtimeSubscribeStatus.timedOut) {
            reconnectTimer?.cancel();
            if (!controller.isClosed) {
              reconnectTimer = Timer(Duration(seconds: reconnectDelay), () {
                if (channel != null) {
                  try {
                    supabaseClient.removeChannel(channel!);
                  } catch (e, st) {
                    Sentry.captureException(e, stackTrace: st);
                  }
                }
                // Dobra o delay exponencialmente até o limite de 30s
                reconnectDelay = (reconnectDelay * 2).clamp(2, 30);
                subscribeToBroadcast();
              });
            }
          }
        });
      }

      subscribeToBroadcast();

      return controller.stream.doOnCancel(() {
        reconnectTimer?.cancel();
        if (channel != null) {
          try {
            supabaseClient.removeChannel(channel!);
          } catch (e, st) {
            Sentry.captureException(e, stackTrace: st);
          }
        }
        controller.close();
      });
    });

    // Escutar mensagens do chat em tempo real com tolerância a falhas temporárias
    final messagesStream = supabaseClient
        .from('ride_messages')
        .stream(primaryKey: ['id'])
        .eq('ride_id', orderEntity.id)
        .order('created_at')
        .map((rows) => rows.map(_rowToMessage).toList());

    final orderStreamWithHandler = orderStream.handleError((error, stackTrace) {
      debugPrint('[TrackOrder] Erro na stream de status da corrida: $error');
    });

    final driverLocationStreamWithHandler = driverLocationStream.handleError((error, stackTrace) {
      debugPrint('[TrackOrder] Erro na stream de telemetria: $error');
    });

    final messagesStreamWithHandler = messagesStream.handleError((error, stackTrace) {
      debugPrint('[TrackOrder] Erro na stream de chat: $error');
    });

    final combinedStream = Rx.combineLatest3(
      orderStreamWithHandler,
      driverLocationStreamWithHandler.startWith(null),
      messagesStreamWithHandler.startWith([]),
      (orderData, driverLocationData, messageData) {
        final List<ChatMessageEntity> messages = [
          ...orderData.chatMessages,
          ...messagesSent,
          ...messageData,
        ];
        messages.sortBy((element) => element.createdAt);
        return (
          orderData.copyWith.call(chatMessages: messages),
          driverLocationData,
        );
      },
    );

    return combinedStream.asyncMap((tuple) async {
      var order = tuple.$1;
      final driverLoc = tuple.$2;

      if (order.status == OrderStatus.driverAccepted && driverLoc != null) {
        final pickup = order.waypoints.firstOrNull;
        if (pickup != null) {
          final pickupLat = pickup.coordinates.lat;
          final pickupLng = pickup.coordinates.lng;
          final driverLat = driverLoc.lat;
          final driverLng = driverLoc.lng;

          bool shouldFetch = true;
          if (_cachedLastDriverLat != null && _cachedLastDriverLng != null) {
            final dist = _calculateDistance(driverLat, driverLng, _cachedLastDriverLat!, _cachedLastDriverLng!);
            if (dist < 100 && _cachedDriverDirections.isNotEmpty) {
              shouldFetch = false;
            }
          }

          if (shouldFetch) {
            debugPrint('[TrackOrder] Recalculando rota do motorista em tempo real...');
            _cachedLastDriverLat = driverLat;
            _cachedLastDriverLng = driverLng;
            _cachedDriverDirections = await _getGoogleRoute([
              LatLngEntity(lat: driverLat, lng: driverLng),
              LatLngEntity(lat: pickupLat, lng: pickupLng),
            ]);
          }

          DateTime? eta = order.etaPickup;
          if (eta == null && _cachedDriverEtaSeconds != null) {
            eta = DateTime.now().add(Duration(seconds: _cachedDriverEtaSeconds!));
          }

          order = order.copyWith.call(
            driverDirections: _cachedDriverDirections,
            etaPickup: eta,
          );
        }
      }
      return (order, driverLoc);
    });
  }

  @override
  Future<Either<Failure, bool>> cancelOrder({
    required String orderId,
    required String? cancelReasonId,
    required String? cancelReasonNote,
  }) async {
    try {
      // Call the cancel-order Edge Function so that:
      // 1. Cancellation fee is charged if applicable
      // 2. Driver gets push notification
      // 3. Driver status resets to 'online'
      // 4. Ride activity is logged
      final response = await supabaseClient.functions.invoke(
        'rider-flow-actions',
        body: {
          'action': 'cancel-order',
          'orderId': orderId,
          'reasonId': cancelReasonId,
          'reasonNote': cancelReasonNote,
        },
      );

      if (response.status != 200) {
        throw Exception('Erro ao cancelar corrida: ${response.data}');
      }

      return const Right(true);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<CancelReasonEntity>>> getCancelReasons() async {
    try {
      final rows = await supabaseClient
          .from('cancel_reasons')
          .select()
          .eq('role', 'rider')
          .eq('is_active', true);
      final reasons = rows
          .map((row) => CancelReasonEntity(
                id: row['id'].toString(),
                name: row['name'].toString(),
              ))
          .toList();
      return Right(reasons);
    } catch (e) {
      // Fallback local se a tabela ainda não tiver dados
      return const Right([
        CancelReasonEntity(id: '1', name: 'Motorista demorou muito'),
        CancelReasonEntity(id: '2', name: 'Solicitei por engano'),
        CancelReasonEntity(id: '3', name: 'Mudei de planos'),
        CancelReasonEntity(id: '4', name: 'Problemas pessoais'),
      ]);
    }
  }

  @override
  Stream<Either<Failure, List<CancelReasonEntity>>>
  startCancelReasonsSubscription() async* {
    yield* supabaseClient
        .from('cancel_reasons')
        .stream(primaryKey: ['id'])
        .map((events) {
      final reasons = events
          .where((row) => row['role'] == 'rider' && row['is_active'] == true)
          .map((row) => CancelReasonEntity(
                id: row['id'].toString(),
                name: row['name'].toString(),
              ))
          .toList();
      return Right<Failure, List<CancelReasonEntity>>(reasons);
    });
  }

  @override
  Future<Either<Failure, ChatMessageEntity>> sendMessage({
    required String orderId,
    required String message,
  }) async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) return Left(Failure.serverError('Not authenticated'));

      // UPPI BRASIL: Call edge function to ensure the driver gets a push notification
      final response = await supabaseClient.functions.invoke(
        'chat-send-message',
        body: {
          'orderId': orderId,
          'content': message,
        },
      );

      if (response.status != 200) {
        throw Exception('Falha ao enviar mensagem: ${response.data}');
      }

      final data = response.data as Map<String, dynamic>?;

      final msg = ChatMessageEntity(
        id: data?['message_id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        message: message,
        isSender: true,
        createdAt: DateTime.now(),
      );
      messagesSent.add(msg);
      return Right(msg);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> sendSOSSignal({required String orderId}) async {
    try {
      
      // UPPI BRASIL: Call edge function to ensure Admins get push notifications
      final response = await supabaseClient.functions.invoke(
        'send-sos',
        body: {
          'orderId': orderId,
        },
      );

      if (response.status != 200) {
        throw Exception('Erro ao enviar SOS: ${response.data}');
      }

      return const Right(null);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<PaymentMethodUnion>>> getPaymentMethods() async {
    try {
      final uid = supabaseClient.auth.currentUser?.id;
      if (uid == null) {
        return const Right([]);
      }

      final List<PaymentMethodUnion> methods = [];

      // Buscar gateways de pagamento
      final gatewaysData = await supabaseClient
          .from('payment_gateways')
          .select()
          .eq('is_active', true);
          
      for (var data in gatewaysData) {
        final linkMethodStr = data['link_method']?.toString() ?? 'redirect';
        final linkMethod = GatewayLinkMethod.values.firstWhere(
          (e) => e.name == linkMethodStr,
          orElse: () => GatewayLinkMethod.redirect,
        );
        methods.add(PaymentMethodUnion.paymentGateway(
          paymentGateway: PaymentGatewayEntity(
            id: data['id'].toString(),
            name: data['title']?.toString() ?? data['name']?.toString() ?? 'Gateway',
            logoUrl: data['logo_url']?.toString() ?? '',
            linkMethod: linkMethod,
          ),
        ));
      }

      // Buscar métodos de pagamento salvos
      final savedMethodsData = await supabaseClient
          .from('payment_methods')
          .select()
          .eq('user_id', uid)
          .eq('is_enabled', true);
          
      for (var data in savedMethodsData) {
        methods.add(PaymentMethodUnion.savedPaymentMethod(
          savedPaymentMethod: SavedPaymentMethodEntity(
            id: data['id'].toString(),
            cardType: CardType.unknown, // Default until parsing is needed
            last4Digits: data['last_four']?.toString() ?? '0000',
            isEnabled: data['is_enabled'] as bool? ?? true,
            isDefault: data['is_default'] as bool? ?? false,
            cardHolderName: data['card_holder_name']?.toString() ?? '',
            expiryDate: data['expiry_date'] != null ? DateTime.tryParse(data['expiry_date'].toString()) : null,
          ),
        ));
      }

      return Right(methods);
    } catch (e) {
      return const Right([]); // Fallback
    }
  }

  @override
  Stream<Either<Failure, List<PaymentMethodUnion>>>
  startPaymentMethodsSubscription() async* {
    final uid = supabaseClient.auth.currentUser?.id;
    if (uid == null) {
      yield const Right([]);
      return;
    }

    final methodsStream = supabaseClient
        .from('payment_methods')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid);

    final gatewaysStream = supabaseClient
        .from('payment_gateways')
        .stream(primaryKey: ['id'])
        .eq('is_active', true);

    yield* Rx.combineLatest2(
      methodsStream,
      gatewaysStream,
      (methods, gateways) => null,
    ).asyncMap((_) async => await getPaymentMethods());
  }

  @override
  Future<Either<Failure, void>> updateLastSeenMessages(
      {required String orderId}) async {
    return const Right(null);
  }
}
