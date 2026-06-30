import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/dto/calculate_fare_args.dart';
import 'package:rider_flutter/core/dto/calculate_fare_response.dart';
import 'package:rider_flutter/core/error/failure.dart';
import 'package:rider_flutter/core/repositories/order_repository.dart';
import 'package:rider_flutter/core/entities/service_category.dart';
import 'package:rider_flutter/core/entities/service.dart';
import 'package:flutter_common/core/entities/payment_gateway.dart';
import 'package:flutter_common/core/entities/saved_payment_method.dart';
import 'package:flutter_common/core/enums/card_type.dart';
import 'package:flutter_common/core/enums/gateway_link_method.dart';
import 'package:flutter_common/core/entities/place.dart';

@prod
@LazySingleton(as: OrderRepository)
class OrderRepositoryImpl implements OrderRepository {
  final FirebaseDatasource firebaseDatasource;

  OrderRepositoryImpl(this.firebaseDatasource);

  @override
  Future<Either<Failure, CalculateFareResponse>> calculateFare({
    required CalculateFareArgs args,
  }) async {
    try {
      // Obter rota estritamente de acordo com o provedor de mapa configurado pelo admin
      double totalDistanceMeters = 0;
      int durationSeconds = 0;
      List<LatLngEntity> directions = [];
      
      String mapProvider = 'googleMaps';
      String googleApiKey = '';
      String osrmBaseUrl = 'https://router.project-osrm.org';
      
      try {
        final settingsRows = await firebaseDatasource.supabaseClient
            .from('app_settings')
            .select();
        
        final Map<String, String> settings = {};
        for (final row in settingsRows) {
          final key = row['key']?.toString() ?? '';
          final value = row['value']?.toString() ?? '';
          if (key.isNotEmpty) settings[key] = value;
        }

        Map<String, dynamic>? globalConfigRow;
        for (final row in settingsRows) {
          if (row['key'] == 'global_config') {
            globalConfigRow = Map<String, dynamic>.from(row);
            break;
          }
        }
        
        if (globalConfigRow != null) {
          mapProvider = globalConfigRow['map_provider']?.toString() ?? 'googleMaps';
          googleApiKey = globalConfigRow['google_map_api_key']?.toString() ?? '';
        } else {
          mapProvider = settings['map_provider'] ?? 'googleMaps';
          googleApiKey = settings['google_map_api_key'] ?? '';
        }
        
        if (settings['osrm_routing_url'] != null && settings['osrm_routing_url']!.isNotEmpty) {
          osrmBaseUrl = settings['osrm_routing_url']!.replaceAll(RegExp(r'/$'), '');
        }
      } catch (e) {
        debugPrint('[Rider-OrderRepo] Error loading app settings: $e');
      }

      bool useGoogleMaps = mapProvider == 'googleMaps';
      if (useGoogleMaps) {
        if (googleApiKey.isNotEmpty && args.waypoints.length >= 2) {
          try {
            final origin = '${args.waypoints[0].coordinates.lat},${args.waypoints[0].coordinates.lng}';
            final destination = '${args.waypoints[args.waypoints.length - 1].coordinates.lat},${args.waypoints[args.waypoints.length - 1].coordinates.lng}';
            String url = 'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&key=$googleApiKey';
            if (args.waypoints.length > 2) {
              final intermediates = args.waypoints.sublist(1, args.waypoints.length - 1)
                  .map((w) => 'via:${w.coordinates.lat},${w.coordinates.lng}')
                  .join('|');
              url += '&waypoints=${Uri.encodeComponent(intermediates)}';
            }

            debugPrint('[Google-Rider] Requesting directions: $url');
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
                  directions = _decodePolyline(overviewPolyline['points'].toString());
                  debugPrint('[Google-Rider] Parsed route with ${directions.length} points');
                }
              } else {
                debugPrint('[Google-Rider] Google Maps status not OK: ${directionsData['status']}');
              }
            }
          } catch (e) {
            debugPrint('[Google-Rider] Exception: $e');
          }
        }
      } else {
        try {
          debugPrint('[OSRM-Rider] Requesting OSRM routing');
          final coords = args.waypoints.map((w) => '${w.coordinates.lng},${w.coordinates.lat}').join(';');
          final url = '$osrmBaseUrl/route/v1/driving/$coords?overview=full&geometries=geojson';
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
          if (response.statusCode == 200) {
            final osrmData = json.decode(response.body);
            if (osrmData['routes'] != null && (osrmData['routes'] as List).isNotEmpty) {
              final route = osrmData['routes'][0];
              totalDistanceMeters = (route['distance'] as num).toDouble();
              durationSeconds = (route['duration'] as num).round();
              
              final geometry = route['geometry'];
              if (geometry != null && geometry['coordinates'] != null) {
                final coordsList = geometry['coordinates'] as List;
                directions = coordsList
                    .map((c) => LatLngEntity(
                          lat: (c[1] as num).toDouble(),
                          lng: (c[0] as num).toDouble(),
                        ))
                    .toList();
              }
            }
          }
        } catch (e) {
          debugPrint('[OSRM-Rider] Exception: $e');
        }
      }

      // Fallback 2: Haversine
      if (totalDistanceMeters == 0) {
        if (args.waypoints.length >= 2) {
          for (int i = 0; i < args.waypoints.length - 1; i++) {
            totalDistanceMeters += _haversineDistance(
              args.waypoints[i].coordinates.lat,
              args.waypoints[i].coordinates.lng,
              args.waypoints[i + 1].coordinates.lat,
              args.waypoints[i + 1].coordinates.lng,
            );
          }
        }
        durationSeconds = (totalDistanceMeters / 1000 / 30 * 3600).round();
      }

      // CALL EDGE FUNCTION
      final response = await firebaseDatasource.supabaseClient.functions.invoke(
        'rider-flow-actions',
        body: {
          'action': 'calculate-fare',
          'args': {
            'waypoints': args.waypoints.map((e) => {
              'coordinates': {'lat': e.coordinates.lat, 'lng': e.coordinates.lng}
            }).toList(),
            'couponCode': args.couponCode,
            'distance_meters': totalDistanceMeters,
            'duration_seconds': durationSeconds,
          }
        }
      );

      final data = response.data;
      if (data['error'] != null) {
        return Left(Failure.serverError(data['error'].toString()));
      }

      final servicesList = data['services'] as List<dynamic>;
      final services = servicesList.map((srv) {
        return ServiceEntity(
          id: srv['id']?.toString() ?? '',
          name: srv['name'] ?? 'Regular',
          description: srv['description'],
          price: (srv['fare'] as num).toDouble(),
          priceAfterCouponApplied: (srv['fareAfterCoupon'] as num).toDouble(),
          capacity: 4,
          imageUrl: srv['image_url'] ?? '',
          rideOptions: [],
          isCashAllowed: true,
          isOnlinePaymentAllowed: true,
        );
      }).toList();

      // Buscar saldo da wallet na tabela dedicada
      double walletBalance = 0.0;
      final uid = firebaseDatasource.uid;
      if (uid != null) {
        final walletDoc = await firebaseDatasource.supabaseClient
            .from('wallets')
            .select('balance')
            .eq('user_id', uid)
            .maybeSingle();
        if (walletDoc != null) {
          walletBalance =
              (walletDoc['balance'] as num?)?.toDouble() ?? 0.0;
        }
      }

      final category = ServiceCategoryEntity(
        id: '1',
        name: 'All',
        services: services,
      );

      // Puxa a moeda oficial
      String appCurrency = 'BRL';
      try {
        final configRow = await firebaseDatasource.supabaseClient
            .from('app_settings')
            .select('value')
            .eq('key', 'currency')
            .maybeSingle();
        if (configRow != null && configRow['value'] != null) {
          appCurrency = configRow['value'].toString();
        }
      } catch (_) {}

      // Buscar gateways de pagamento
      final gatewaysData = await firebaseDatasource.supabaseClient
          .from('payment_gateways')
          .select()
          .eq('is_active', true);
          
      final paymentGateways = gatewaysData.map((data) {
        final linkMethodStr = data['link_method']?.toString() ?? 'redirect';
        final linkMethod = GatewayLinkMethod.values.firstWhere(
          (e) => e.name == linkMethodStr,
          orElse: () => GatewayLinkMethod.redirect,
        );
        return PaymentGatewayEntity(
          id: data['id'].toString(),
          name: data['title']?.toString() ?? data['name']?.toString() ?? 'Gateway',
          logoUrl: data['logo_url']?.toString() ?? '',
          linkMethod: linkMethod,
        );
      }).toList();

      // Buscar métodos de pagamento salvos
      List<SavedPaymentMethodEntity> savedPaymentMethods = [];
      if (uid != null) {
        final savedMethodsData = await firebaseDatasource.supabaseClient
            .from('payment_methods')
            .select()
            .eq('user_id', uid)
            .eq('is_enabled', true);
            
        savedPaymentMethods = savedMethodsData.map((data) {
          return SavedPaymentMethodEntity(
            id: data['id'].toString(),
            cardType: CardType.unknown, // Default until parsing is needed
            last4Digits: data['last_four']?.toString() ?? '0000',
            isEnabled: data['is_enabled'] as bool? ?? true,
            isDefault: data['is_default'] as bool? ?? false,
            cardHolderName: data['card_holder_name']?.toString() ?? '',
            expiryDate: data['expiry_date'] != null ? DateTime.tryParse(data['expiry_date'].toString()) : null,
          );
        }).toList();
      }

      final cashEnabled = data['cash_enabled'] as bool? ?? true;
      final walletEnabled = data['wallet_enabled'] as bool? ?? true;

      final fareResponse = CalculateFareResponse(
        paymentGateways: paymentGateways,
        savedPaymentMethods: savedPaymentMethods,
        services: [category],
        wallets: [(appCurrency, walletBalance)],
        currency: appCurrency,
        durationInSeconds: durationSeconds,
        distanceInMeters: totalDistanceMeters.round(),
        directions: directions,
        cashEnabled: cashEnabled,
        walletEnabled: walletEnabled,
      );

      return Right(fareResponse);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
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
}
