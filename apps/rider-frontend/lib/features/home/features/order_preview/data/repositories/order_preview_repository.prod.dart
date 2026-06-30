import 'package:flutter/foundation.dart';
import 'dart:math';
import 'dart:convert';
import 'package:dartz/dartz.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/dto/new_order_args.dart';
import 'package:rider_flutter/core/entities/order.dart';
import 'package:rider_flutter/core/error/failure.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:flutter_common/core/enums/order_status.dart';

import '../../domain/repositories/order_preview_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@prod
@LazySingleton(as: OrderPreviewRepository)
class OrderPreviewRepositoryImpl implements OrderPreviewRepository {
  final FirebaseDatasource firebaseDatasource;
  final SupabaseClient supabaseClient;

  OrderPreviewRepositoryImpl(this.firebaseDatasource)
      : supabaseClient = Supabase.instance.client;

  @override
  Future<Either<Failure, OrderEntity>> submitOrder({
    required NewOrderArgs args,
  }) async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) return Left(Failure.serverError('User not logged in'));

      final now = DateTime.now();

      // pickup/dropoff waypoints used below for OSRM route calculation

      double totalDistanceMeters = 0;
      int durationSeconds = 0;
      List<Map<String, double>> directionsList = [];

      // Tentar obter distância pela Google Directions API
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

        if (googleApiKey.isNotEmpty && args.waypoints.length >= 2) {
          final origin = '${args.waypoints[0].coordinates.lat},${args.waypoints[0].coordinates.lng}';
          final destination = '${args.waypoints[args.waypoints.length - 1].coordinates.lat},${args.waypoints[args.waypoints.length - 1].coordinates.lng}';
          String url = 'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&key=$googleApiKey';
          if (args.waypoints.length > 2) {
            final intermediates = args.waypoints.sublist(1, args.waypoints.length - 1)
                .map((w) => 'via:${w.coordinates.lat},${w.coordinates.lng}')
                .join('|');
            url += '&waypoints=${Uri.encodeComponent(intermediates)}';
          }

          debugPrint('[Google-Rider-Preview] Requesting directions: $url');
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
          if (response.statusCode == 200) {
            final directionsData = json.decode(response.body);
            if (directionsData['status'] == 'OK' && directionsData['routes'] != null && (directionsData['routes'] as List).isNotEmpty) {
              final route = directionsData['routes'][0];
              
              double routeDistance = 0;
              int routeDuration = 0;
              for (var leg in route['legs']) {
                routeDistance += (leg['distance']['value'] as num).toDouble();
                routeDuration += (leg['duration']['value'] as num).toInt();
              }
              totalDistanceMeters = routeDistance;
              durationSeconds = routeDuration;

              final overviewPolyline = route['overview_polyline'];
              if (overviewPolyline != null && overviewPolyline['points'] != null) {
                final points = _decodePolyline(overviewPolyline['points'].toString());
                directionsList = points.map((p) => {
                  'lat': p.lat,
                  'lng': p.lng,
                }).toList();
                debugPrint('[Google-Rider-Preview] Parsed route with ${directionsList.length} points');
              }
            } else {
              debugPrint('[Google-Rider-Preview] Google Maps status not OK: ${directionsData['status']}');
            }
          }
        }
      } catch (e) {
        debugPrint('[Google-Rider-Preview] Exception: $e');
      }

      if (totalDistanceMeters == 0) {
        // Fallback 1: Rota real pelo OSRM (Gratuito, via OpenStreetMap)
        final osrmData = await _getOSRMRoute(
            args.waypoints.map((e) => e.coordinates).toList());

        if (osrmData != null &&
            osrmData['routes'] != null &&
            (osrmData['routes'] as List).isNotEmpty) {
          final route = osrmData['routes'][0];
          totalDistanceMeters = (route['distance'] as num).toDouble();
          durationSeconds = (route['duration'] as num).round();

          final geometry = route['geometry'];
          if (geometry != null && geometry['coordinates'] != null) {
            final coords = geometry['coordinates'] as List;
            directionsList = coords
                .map((c) => {
                      'lng': (c[0] as num).toDouble(),
                      'lat': (c[1] as num).toDouble(),
                    })
                .toList();
          }
        } else {
          // Fallback 2: Calcular distância em linha reta (Haversine)
          for (int i = 0; i < args.waypoints.length - 1; i++) {
            totalDistanceMeters += _haversineDistance(
              args.waypoints[i].coordinates.lat,
              args.waypoints[i].coordinates.lng,
              args.waypoints[i + 1].coordinates.lat,
              args.waypoints[i + 1].coordinates.lng,
            );
          }
          durationSeconds = (totalDistanceMeters / 1000 / 30 * 3600).round();
        }
      }

      // waitTime from args, calculate expectedAt
      final waitMinutes = args.waitTime;
      final expectedAt = waitMinutes > 0
          ? now.add(Duration(minutes: waitMinutes)).toIso8601String()
          : null;

      final paymentMethodStr = args.paymentMethod.map(
        cash: (_) => 'cash',
        wallet: (_) => 'wallet',
        paymentGateway: (g) => 'credit_card',
        savedPaymentMethod: (s) => 'credit_card',
      );

      final efArgs = {
        'waypoints': args.waypoints.map((e) => {
          'address': e.address,
          'coordinates': {'lat': e.coordinates.lat, 'lng': e.coordinates.lng}
        }).toList(),
        'serviceId': args.serviceId,
        'couponCode': args.couponCode,
        'paymentMethod': { paymentMethodStr: true },
        'distance_meters': totalDistanceMeters.round(),
        'duration_seconds': durationSeconds,
        'expected_at': expectedAt,
        'routePolyline': directionsList,
      };

      final efResponse = await supabaseClient.functions.invoke(
        'rider-flow-actions',
        body: {
          'action': 'create-order',
          'args': efArgs,
        },
      );

      final response = efResponse.data;
      if (efResponse.status != 200 && efResponse.status != 201) {
        String errMsg = 'Erro no servidor (status: ${efResponse.status})';
        if (response is Map && response['error'] != null) {
          errMsg = response['error'].toString();
        } else if (response != null) {
          errMsg = response.toString();
        }
        return Left(Failure.serverError(errMsg));
      }
      if (response == null) {
        return Left(Failure.serverError('Resposta vazia do servidor'));
      }
      if (response is Map && response['error'] != null) {
        return Left(Failure.serverError(response['error'].toString()));
      }
      if (response is! Map) {
        return Left(Failure.serverError('Resposta inválida do servidor'));
      }

      String appCurrency = 'BRL';
      try {
        final configRow = await supabaseClient.from('app_settings').select('value').eq('key', 'currency').maybeSingle();
        if (configRow != null && configRow['value'] != null) {
          appCurrency = configRow['value'].toString();
        }
      } catch (_) {}

      final responseMap = Map<String, dynamic>.from(response);
      return Right(_buildOrderEntityFromMemory(
          responseMap,
          args,
          directionsList,
          (responseMap['fare'] as num?)?.toDouble() ?? 0.0,
          appCurrency));

    } catch (e, stackTrace) {
      debugPrint('[OrderPreviewRepositoryImpl] ERROR: $e');
      debugPrint('[OrderPreviewRepositoryImpl] STACK: $stackTrace');
      return Left(Failure.serverError('Falha ao processar o pedido de corrida. Erro: $e'));
    }
  }

  /// Integração OSRM Routing API usando http package (web-compatible)
  Future<Map<String, dynamic>?> _getOSRMRoute(
      List<LatLngEntity> waypoints) async {
    try {
      final coords = waypoints.map((w) => '${w.lng},${w.lat}').join(';');
      
      // Carregar url customizada de OSRM do banco de dados (app_settings) para evitar rate limit de produção
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

      final url = '$osrmBaseUrl/route/v1/driving/$coords?overview=full&geometries=geojson';

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'UppiTaxiApp/3.2.8'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (_) {}
    return null;
  }



  List<LatLngEntity> _decodePolyline(String encoded) {
    List<LatLngEntity> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLngEntity(
        lat: lat / 1E5,
        lng: lng / 1E5,
      ));
    }
    return points;
  }

  /// Fórmula Haversine: distância em metros entre duas coordenadas
  double _haversineDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  OrderEntity _buildOrderEntityFromMemory(
      Map<String, dynamic> dbData,
      NewOrderArgs args,
      List<Map<String, double>> directionsList,
      double finalCost,
      String appCurrency) {
    final statusStr = dbData['status']?.toString() ?? 'requested';
    OrderStatus status = OrderStatus.requested;
    if (statusStr == 'accepted' || statusStr == 'driver_accepted') status = OrderStatus.driverAccepted;
    if (statusStr == 'arrived') status = OrderStatus.arrived;
    if (statusStr == 'in_progress' || statusStr == 'started') status = OrderStatus.started;
    if (statusStr == 'completed' || statusStr == 'finished') status = OrderStatus.finished;
    if (statusStr == 'canceled' || statusStr == 'rider_canceled') status = OrderStatus.riderCanceled;
    if (statusStr == 'driver_canceled') status = OrderStatus.driverCanceled;
    if (statusStr == 'expired') status = OrderStatus.expired;
    if (statusStr == 'no_driver') status = OrderStatus.notFound;
    if (statusStr == 'no_close_found') status = OrderStatus.noCloseFound;

    List<LatLngEntity> directions = directionsList
        .map((e) => LatLngEntity(lat: e['lat'] ?? 0, lng: e['lng'] ?? 0))
        .toList();

    DateTime createdAt = DateTime.now();
    if (dbData['created_at'] != null) {
      createdAt = DateTime.parse(dbData['created_at'].toString());
    }

    return OrderEntity(
      id: dbData['id']?.toString() ?? '',
      status: status,
      waypoints: args.waypoints,
      arrivedAtWaypointIndex: null,
      rideDirections: directions,
      driverDirections: const [],
      driver: null,
      serviceName: args.serviceId ?? 'Standard',
      serviceImageUrl: '',
      cancellationFee: 0,
      cost: finalCost,
      costAfterCoupon: finalCost,
      currency: appCurrency,
      distance: (dbData['distance_meters'] as num?)?.toInt() ?? 0,
      duration: (dbData['duration_seconds'] as num?)?.toInt() ?? 0,
      waitTime: args.waitTime,
      etaPickup: null,
      createdAt: createdAt,
      expectedAt: createdAt,
      startedAt: null,
      lastSeenMessagesAt: DateTime.now(),
      paymentMethod: args.paymentMethod,
      chatMessages: const [],
      walletCredit: 0,
      cashPaymentAllowed: true,
      boardingPin: dbData['boarding_pin']?.toString(),
    );
  }
}
