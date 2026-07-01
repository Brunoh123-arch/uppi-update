import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/blocs/auth_bloc.dart';
import 'package:flutter_common/core/blocs/settings.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/core/entities/order_request.dart';
import 'package:uppi_motorista/core/presentation/app_generic_map.dart';
import 'package:uppi_motorista/core/utils/driver_speed.dart';
import 'package:uppi_motorista/core/utils/route_snap.dart';
import 'package:flutter_common/core/presentation/animated_driver_marker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/config/constants.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:generic_map/generic_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:maps_toolkit/maps_toolkit.dart' as map_toolkit;
import 'package:flutter_compass/flutter_compass.dart';

import '../blocs/home.dart';
import 'navigation_overlay.dart';
import 'package:uppi_motorista/features/home/presentation/screens/sheets/rides_radar_sheet.dart';

class HomeMapView extends StatefulWidget {
  const HomeMapView({super.key});

  @override
  State<HomeMapView> createState() => _HomeMapViewState();
}

class _HomeMapViewState extends State<HomeMapView> {
  MapViewController? controller;
  List<Map<String, dynamic>> _activeSurgeZones = [];
  RealtimeChannel? _surgeRealtimeChannel;
  Timer? _surgeTimer;
  final Map<String, LatLng> _polygonCenterCache = {};

  List<LatLng>? _lastWaypoints;
  String? _lastOfferId;

  // Heading-up estável (estilo Google): guardamos o último ponto usado para
  // calcular a direção e a última direção válida da câmera, para não "rodopiar"
  // quando o motorista está parado/lento (quando o heading do GPS é instável).
  double _navBearing = 0.0;

  // Sensor de Bússola magnética do celular (para girar parado)
  StreamSubscription? _compassSubscription;
  double _deviceHeading = 0.0;

  // Modo "seguindo o motorista" (navegação). Quando o usuário arrasta o mapa,
  // pausamos o follow e mostramos o botão "Recentralizar", igual Google/Waze.
  bool _isFollowing = true;
  // Força a câmera a se alinhar instantaneamente (sem suavização) na próxima atualização.
  // Usado ao iniciar navegação, recentralizar ou sair da corrida.
  bool _snapNextCameraUpdate = true;
  bool _wasOnTrip = false;
  DateTime? _entryAnimationStartTime;
  // Volta a seguir sozinho após alguns segundos sem interação (igual Google).
  Timer? _recenterTimer;
  LatLng? _lastGpsPosition;
  LatLng? _lastSnappedGpsPosition;
  SnappedPoint? _cachedSnappedPoint;
  DateTime? _lastLocationUpdateTime;
  Duration _markerAnimationDuration = const Duration(milliseconds: 900);

  // Histerese do estado "em movimento": entra acima de 8 km/h e só sai abaixo
  // de 3 km/h. Sem isso, com a velocidade oscilando em torno de 5 km/h (ex.:
  // semáforo), a câmera/seta alternava entre bússola e rumo da rota sem parar.
  bool _wasMoving = false;
  bool _isMovingNow() {
    final kmh = DriverSpeed.kmh.value;
    if (_wasMoving) {
      if (kmh < 3.0) _wasMoving = false;
    } else {
      if (kmh > 8.0) _wasMoving = true;
    }
    return _wasMoving;
  }

  @override
  void initState() {
    super.initState();
    _fetchActiveSurgeZones();
    _startSurgeRealtimeListener();
    _surgeTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      final homeState = context.read<HomeBloc>().state;
      final isOnTrip = homeState.driverStatus.maybeMap(
        onTrip: (_) => true,
        orElse: () => false,
      );
      if (!isOnTrip) {
        _fetchActiveSurgeZones();
      }
    });
    HomeNavigationOverlay.activeRouteNotifier.addListener(_onActiveRouteChanged);
    HomeNavigationOverlay.driverIdxNotifier.addListener(_onIndexChanged);
    HomeNavigationOverlay.nextManeuverIdxNotifier.addListener(_onIndexChanged);
    RidesRadarSheet.selectedRadarRideNotifier.addListener(_onRadarRideChanged);
    
    // Iniciar escuta da bússola em tempo real
    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (event.heading != null && mounted) {
        // Se o veículo estiver em movimento, ignoramos a bússola para evitar
        // jitter no movimento reto (com histerese para não alternar no semáforo).
        if (_isMovingNow()) {
          return;
        }

        final newHeading = (event.heading! + 360) % 360;
        // Evitamos rebuilds desnecessários se a rotação variar muito pouco (limiar de 2 graus)
        if ((newHeading - _deviceHeading).abs() > 2.0) {
          if (_isFollowing) {
            setState(() {
              _deviceHeading = newHeading;
            });
            // Se estivermos seguindo, atualiza a câmera para responder à rotação do celular.
            // Em corrida a bússola NÃO comanda mais a câmera: parado, a câmera
            // aponta para a rota (estilo Google Maps), então girar o celular
            // não deve girar o mapa.
            final homeState = context.read<HomeBloc>().state;
            final isOnTrip = homeState.driverStatus.maybeMap(
              onTrip: (_) => true,
              orElse: () => false,
            );
            if (!isOnTrip) {
              _updateMapCameraWithState(homeState);
            }
          } else {
            _deviceHeading = newHeading;
          }
        }
      }
    });
  }

  void _onIndexChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _startSurgeRealtimeListener() {
    _surgeRealtimeChannel?.unsubscribe();
    _surgeRealtimeChannel = Supabase.instance.client
        .channel('public:surge_zones')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'surge_zones',
          callback: (payload) {
            _fetchActiveSurgeZones();
          },
        );
    _surgeRealtimeChannel!.subscribe();
  }

  void _onActiveRouteChanged() {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
          _updateMapCameraWithState(context.read<HomeBloc>().state);
        }
      });
    }
  }

  @override
  void dispose() {
    _surgeTimer?.cancel();
    _recenterTimer?.cancel();
    _compassSubscription?.cancel();
    _surgeRealtimeChannel?.unsubscribe();
    HomeNavigationOverlay.activeRouteNotifier.removeListener(_onActiveRouteChanged);
    HomeNavigationOverlay.driverIdxNotifier.removeListener(_onIndexChanged);
    HomeNavigationOverlay.nextManeuverIdxNotifier.removeListener(_onIndexChanged);
    RidesRadarSheet.selectedRadarRideNotifier.removeListener(_onRadarRideChanged);
    super.dispose();
  }

  void _onRadarRideChanged() {
    if (mounted) {
      setState(() {});
      _updateMapCameraWithState(context.read<HomeBloc>().state);
    }
  }

  /// Reativa o follow automaticamente após alguns segundos sem o usuário
  /// arrastar o mapa (igual Google/Waze).
  void _scheduleAutoRecenter() {
    _recenterTimer?.cancel();
    _recenterTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      setState(() {
        _isFollowing = true;
        _snapNextCameraUpdate = true;
      });
      _updateMapCameraWithState(context.read<HomeBloc>().state);
    });
  }

  Future<void> _fetchActiveSurgeZones() async {
    try {
      final data = await Supabase.instance.client
          .from('vw_surge_zones')
          .select()
          .eq('is_active', true);

      final filtered = List<Map<String, dynamic>>.from(data).where((zone) {
        final expiresAtStr = zone['expires_at'] as String?;
        if (expiresAtStr == null) return true;
        final expiresAt = DateTime.tryParse(expiresAtStr);
        if (expiresAt == null) return true;
        return expiresAt.toUtc().isAfter(DateTime.now().toUtc());
      }).toList();

      debugPrint('UPPI SURGE - Zonas de calor ativas buscadas: ${filtered.length} zonas. Detalhes: $filtered');

      if (mounted) {
        setState(() {
          _activeSurgeZones = filtered;
        });
      }
    } catch (e) {
      debugPrint('Error fetching active surge zones: $e');
    }
  }

  LatLng _getCenterOfSurgeZone(Map<String, dynamic> zone) {
    final lat = (zone['center_lat'] as num?)?.toDouble();
    final lng = (zone['center_lng'] as num?)?.toDouble();
    if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
      return LatLng(lat, lng);
    }

    final wkt = zone['boundary_wkt'] as String? ?? '';
    if (wkt.isNotEmpty && RegExp(r'POLYGON', caseSensitive: false).hasMatch(wkt)) {
      return _getPolygonCenter(wkt);
    }

    final coords = zone['polygon_coords'] as List?;
    if (coords != null && coords.isNotEmpty) {
      try {
        double sumLat = 0;
        double sumLng = 0;
        int count = 0;
        for (final p in coords) {
          if (p is List && p.length >= 2) {
            sumLng += (p[0] as num).toDouble();
            sumLat += (p[1] as num).toDouble();
            count++;
          }
        }
        if (count > 0) {
          return LatLng(sumLat / count, sumLng / count);
        }
      } catch (e) {
        debugPrint('Error calculating center from polygon_coords: $e');
      }
    }

    // Fallback
    if (mounted) {
      final driverLoc = context.read<HomeBloc>().state.driverLocation;
      if (driverLoc != null) {
        return LatLng(driverLoc.lat, driverLoc.lng);
      }
    }
    return LatLng(Constants.defaultLocation.coordinates.lat, Constants.defaultLocation.coordinates.lng);
  }

  LatLng _getPolygonCenter(String wkt) {
    if (_polygonCenterCache.containsKey(wkt)) {
      return _polygonCenterCache[wkt]!;
    }

    LatLng getFallback() {
      if (mounted) {
        final driverLoc = context.read<HomeBloc>().state.driverLocation;
        if (driverLoc != null) {
          return LatLng(driverLoc.lat, driverLoc.lng);
        }
      }
      return LatLng(Constants.defaultLocation.coordinates.lat, Constants.defaultLocation.coordinates.lng);
    }

    try {
      final match = RegExp(r'POLYGON\s*\(\((.*?)\)\)', caseSensitive: false)
          .firstMatch(wkt);
      if (match == null) return getFallback();
      final coordsStr = match.group(1)!;
      final points = coordsStr.split(',').map((coord) {
        final parts = coord.trim().split(RegExp(r'\s+'));
        final lng = double.parse(parts[0]);
        final lat = double.parse(parts[1]);
        return LatLng(lat, lng);
      }).toList();

      if (points.isEmpty) return getFallback();

      double sumLat = 0;
      double sumLng = 0;
      for (final p in points) {
        sumLat += p.latitude;
        sumLng += p.longitude;
      }
      final center = LatLng(sumLat / points.length, sumLng / points.length);
      _polygonCenterCache[wkt] = center;
      return center;
    } catch (e) {
      return getFallback();
    }
  }

  double _interpolateAngle(double current, double target, double lerpFactor) {
    double diff = (target - current) % 360;
    if (diff > 180) {
      diff -= 360;
    } else if (diff < -180) {
      diff += 360;
    }
    return (current + diff * lerpFactor) % 360;
  }

  ({double zoom, double tilt}) _getDynamicZoomAndTilt(double speedKmh) {
    if (speedKmh <= 30.0) {
      return (zoom: 17.0, tilt: 55.0);
    } else if (speedKmh <= 70.0) {
      return (zoom: 16.0, tilt: 50.0);
    } else {
      return (zoom: 15.0, tilt: 45.0);
    }
  }

  double _getDynamicOffRouteThreshold(double speedKmh) {
    if (speedKmh <= 30.0) {
      return 20.0;
    } else if (speedKmh <= 70.0) {
      return 35.0;
    } else {
      return 50.0;
    }
  }

  void _updateMapCameraWithState(HomeState state) {
    final isOnTrip = state.driverStatus.maybeMap(
      onTrip: (_) => true,
      orElse: () => false,
    );

    final justEnteredTrip = isOnTrip && !_wasOnTrip;
    final justExitedTrip = !isOnTrip && _wasOnTrip;
    _wasOnTrip = isOnTrip;

    if (justEnteredTrip || justExitedTrip) {
      _isFollowing = true;
    }

    if (!_isFollowing) {
      _entryAnimationStartTime = null;
      return;
    }

    if (justEnteredTrip) {
      _entryAnimationStartTime = DateTime.now();
    } else if (_entryAnimationStartTime != null) {
      final elapsed = DateTime.now().difference(_entryAnimationStartTime!);
      if (elapsed < const Duration(milliseconds: 2200)) {
        return;
      } else {
        _entryAnimationStartTime = null;
      }
    }

    // Em corrida a câmera anima no mesmo ritmo do marcador (90% do intervalo
    // real entre fixes de GPS); fora dela usa um deslize curto fixo. O Google
    // Maps agora também anima (antes era Duration.zero = teleporte seco).
    Duration cameraDuration =
        isOnTrip ? _markerAnimationDuration : const Duration(milliseconds: 350);

    if (justEnteredTrip) {
      // Animação cinematográfica de entrada (swoop 3D estilo Google Maps):
      // Damos uma duração maior para planar a câmera rotacionando e inclinando de uma vez.
      cameraDuration = const Duration(milliseconds: 2200);
      _snapNextCameraUpdate = true;
    }

    final hasCurrentRequest = state.driverStatus.maybeMap(
      online: (online) => online.currentOrderRequest != null || RidesRadarSheet.selectedRadarRideNotifier.value != null,
      orElse: () => false,
    );

    // Só movemos a câmera com bússola estática se NÃO estivermos em corrida ativa e NÃO houver oferta de corrida na tela.
    // Durante a corrida, a câmera deve seguir o rumo do tráfego (bearing de movimento).
    if (state.driverLocation != null && !isOnTrip && !hasCurrentRequest) {
      final driverLatLng = LatLng(state.driverLocation!.lat, state.driverLocation!.lng);
      final isMoving = _isMovingNow();
      double bearing = _deviceHeading;
      if (isMoving) {
        final gpsHeading = state.driverLocation!.rotation?.toDouble();
        if (gpsHeading != null && gpsHeading != 0) {
          bearing = gpsHeading;
        } else if (_lastGpsPosition != null) {
          final dist = driverLatLng.distanceWith(_lastGpsPosition!);
          if (dist >= 4.0) {
            final calculatedHeading = map_toolkit.SphericalUtil.computeHeading(
              map_toolkit.LatLng(_lastGpsPosition!.latitude, _lastGpsPosition!.longitude),
              map_toolkit.LatLng(driverLatLng.latitude, driverLatLng.longitude),
            ).toDouble();
            bearing = (calculatedHeading + 360) % 360;
          }
        }
      }
      _lastGpsPosition = driverLatLng;
      controller?.moveCamera(
        driverLatLng,
        18.0,
        bearing: bearing,
        tilt: 55.0,
        duration: cameraDuration,
      );
      return;
    }
    state.driverStatus.maybeMap(
      onTrip: (onTripState) {
        final currentWaypoints = onTripState.order.waypoints.markers.map((m) => m.position).toList();
        bool waypointsChanged = false;

        if (_lastWaypoints == null) {
          waypointsChanged = true;
        } else if (_lastWaypoints!.length != currentWaypoints.length) {
          waypointsChanged = true;
        } else {
          for (int i = 0; i < currentWaypoints.length; i++) {
            if (_lastWaypoints![i] != currentWaypoints[i]) {
              waypointsChanged = true;
              break;
            }
          }
        }

        if (waypointsChanged) {
          _lastWaypoints = currentWaypoints;
          _snapNextCameraUpdate = true;
        }

        // Se o usuário arrastou o mapa, não forçamos a câmera de volta
        if (!_isFollowing) return;
        if (state.driverLocation != null) {
          final driverLatLng = LatLng(state.driverLocation!.lat, state.driverLocation!.lng);
          
          final isMoving = _isMovingNow();
          
          // Tenta fazer o snap na rota apenas se estiver ativo
          final routePoints = HomeNavigationOverlay.activeRouteNotifier.value;
          final snapped = _getSnappedPoint(driverLatLng, routePoints);

          double targetBearing = _navBearing;
          if (isMoving) {
            // Em movimento: usa direção da rota (se grudado) ou rumo do GPS
            if (snapped != null) {
              targetBearing = snapped.bearing;
            } else {
              final gpsHeading = state.driverLocation!.rotation?.toDouble();
              if (gpsHeading != null && gpsHeading != 0) {
                targetBearing = gpsHeading;
              } else if (_lastGpsPosition != null) {
                final dist = driverLatLng.distanceWith(_lastGpsPosition!);
                if (dist >= 4.0) {
                  final calculatedHeading = map_toolkit.SphericalUtil.computeHeading(
                    map_toolkit.LatLng(_lastGpsPosition!.latitude, _lastGpsPosition!.longitude),
                    map_toolkit.LatLng(driverLatLng.latitude, driverLatLng.longitude),
                  ).toDouble();
                  targetBearing = (calculatedHeading + 360) % 360;
                }
              }
            }
          } else {
            // Parado em corrida: a câmera vira sozinha e aponta na DIREÇÃO DA
            // ROTA (linha azul), igual o Google Maps faz ao entrar na
            // navegação. Sem snap, mantém o último rumo bom (_navBearing) —
            // a bússola dentro do carro sofre interferência magnética e
            // fazia a câmera rodopiar para direções erradas.
            if (snapped != null) {
              targetBearing = snapped.bearing;
            }
          }
          // Aplica a rotação de forma instantânea na primeira atualização/recentralização para alinhar
          // imediatamente com a rota. Usa interpolação suave nas atualizações subsequentes em movimento.
          if (_snapNextCameraUpdate) {
            _navBearing = targetBearing;
            _snapNextCameraUpdate = false;
          } else {
            _navBearing = _interpolateAngle(_navBearing, targetBearing, 0.45);
          }
          _lastGpsPosition = driverLatLng;

          // Cruise Mode: Zoom e Tilt baseados na velocidade
          final cruise = _getDynamicZoomAndTilt(DriverSpeed.kmh.value);
          double targetZoom = cruise.zoom;
          double targetTilt = cruise.tilt;

          // Ajuste dinâmico ao se aproximar de manobras (Auto-Zoom e Auto-Tilt estilo Google Maps/Waze)
          final nextManeuver = HomeNavigationOverlay.nextManeuverNotifier.value;
          if (nextManeuver != null) {
            final distance = HomeNavigationOverlay.distanceToNextManeuverNotifier.value;
            if (distance <= 120.0 && distance > 0.0) {
              // Interpolamos de 120m a 20m: quanto mais perto, mais zoom e menos tilt (tela mais vertical/em pé)
              final double t = (1.0 - (distance - 20.0) / 100.0).clamp(0.0, 1.0);
              targetZoom = cruise.zoom + (0.8 * t); // Aumenta o zoom em até 0.8
              targetTilt = cruise.tilt - ((cruise.tilt - 20.0) * t); // Tilt diminui suavemente até atingir exatos 20.0
            }
          }

          final cameraTarget = snapped?.position ?? driverLatLng;
          controller?.moveCamera(
            cameraTarget,
            targetZoom,
            bearing: _navBearing,
            tilt: targetTilt,
            duration: cameraDuration,
          );
        } else if (state.markers.isNotEmpty) {
          controller?.moveCamera(state.markers.first.position, 16.0, duration: cameraDuration);
        }
      },
      orElse: () {
        // Fora de corrida o mapa volta a ser "norte pra cima"; zera o histórico
        // de direção para a próxima navegação começar limpa.
        _lastWaypoints = null;
        _navBearing = 0.0;
        _snapNextCameraUpdate = true;

        // UPPI BRASIL: Se houver oferta de corrida ativa na tela, enquadramos a rota inteira
        // (fitBounds na lista completa de pontos da polyline) para dar o "efeito maps" e mostrar
        // o percurso completo.
        bool fittedOfferRoute = false;
        state.driverStatus.mapOrNull(
          online: (onlineState) {
            final currentRequest = onlineState.currentOrderRequest ?? RidesRadarSheet.selectedRadarRideNotifier.value;
            if (currentRequest != null) {
              fittedOfferRoute = true;
              if (_lastOfferId != currentRequest.id) {
                _lastOfferId = currentRequest.id;
                _isFollowing = true;
                _animateOfferRoute(currentRequest);
              }
            } else {
              _lastOfferId = null;
            }
          },
        );

        if (!fittedOfferRoute) {
          if (state.markers.length > 1) {
            final markersDistances = state.markers
                .map(
                  (e) =>
                      e.position.distanceWith(state.markers.first.position),
                )
                .reduce((value, element) => value + element);
            if (markersDistances > 10) {
              controller?.fitBounds(
                state.markers.map((e) => e.position).toList(),
              );
            } else {
              controller?.moveCamera(state.markers.first.position, null, bearing: 0.0, tilt: 0.0);
            }
          } else if (state.markers.length == 1) {
          state.driverStatus.maybeMap(
            online: (value) {
              final radius = locator<AuthBloc>().state.maybeMap(
                    orElse: () => null,
                    authenticated: (authenticated) =>
                        authenticated.profile.searchRadius,
                  );
              fitMapToCenterAndRadius(
                state.markers.first.position,
                radius ?? 10000,
              );
            },
            orElse: () {
              controller?.moveCamera(state.markers.first.position, null, bearing: 0.0, tilt: 0.0);
            },
          );
        }
      }
    },
  );
}

  void _animateOfferRoute(OrderRequestEntity currentRequest) async {
    final routePoints = currentRequest.route;
    LatLng? startPoint;
    LatLng? endPoint;

    if (routePoints.isNotEmpty) {
      startPoint = LatLng(routePoints.first.lat, routePoints.first.lng);
      endPoint = LatLng(routePoints.last.lat, routePoints.last.lng);
    } else if (currentRequest.waypoints.isNotEmpty) {
      startPoint = currentRequest.waypoints.first.coordinates.latLng;
      if (currentRequest.waypoints.length > 1) {
        endPoint = currentRequest.waypoints.last.coordinates.latLng;
      }
    }

    if (startPoint == null) return;

    if (endPoint == null) {
      controller?.moveCamera(
        startPoint,
        16.0,
        bearing: 0.0,
        tilt: 45.0,
        duration: const Duration(milliseconds: 1500),
      );
      return;
    }

    // Calculamos o bearing (direção) da viagem (da origem ao destino)
    final double bearing = (map_toolkit.SphericalUtil.computeHeading(
      map_toolkit.LatLng(startPoint.latitude, startPoint.longitude),
      map_toolkit.LatLng(endPoint.latitude, endPoint.longitude),
    ).toDouble() + 360) % 360;

    // Calculamos a distância entre origem e destino em metros
    final double distanceMeters = map_toolkit.SphericalUtil.computeDistanceBetween(
      map_toolkit.LatLng(startPoint.latitude, startPoint.longitude),
      map_toolkit.LatLng(endPoint.latitude, endPoint.longitude),
    ).toDouble();

    // Ponto médio entre a origem e o destino da viagem
    final centerPoint = LatLng(
      (startPoint.latitude + endPoint.latitude) / 2,
      (startPoint.longitude + endPoint.longitude) / 2,
    );

    // Ajusta o nível de zoom dinâmico baseado na distância do percurso
    double zoom = 15.0;
    if (distanceMeters < 500) {
      zoom = 16.5;
    } else if (distanceMeters < 1000) {
      zoom = 15.5;
    } else if (distanceMeters < 2500) {
      zoom = 14.5;
    } else if (distanceMeters < 6000) {
      zoom = 13.5;
    } else if (distanceMeters < 12000) {
      zoom = 12.5;
    } else if (distanceMeters < 25000) {
      zoom = 11.5;
    } else {
      zoom = 10.5;
    }

    // UPPI BRASIL - Efeito Maps Cinemático 3D (fly-in + giratório):
    // Primeiro focamos na origem da corrida com zoom mais aproximado e tilt inicial...
    controller?.moveCamera(
      startPoint,
      16.5,
      bearing: bearing,
      tilt: 50.0,
      duration: Duration.zero,
    );

    // ...e em seguida recuamos suavemente a câmera para o centro da rota, inclinando
    // e enquadrando o trajeto completo de forma elegante voltada em direção ao destino!
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      controller?.moveCamera(
        centerPoint,
        zoom,
        bearing: bearing,
        tilt: 38.0, // Inclinação 3D premium
        duration: const Duration(milliseconds: 2000),
      );
    });
  }

  SnappedPoint? _getSnappedPoint(LatLng driverLatLng, List<LatLng> routePoints) {
    if (_lastSnappedGpsPosition == driverLatLng) {
      return _cachedSnappedPoint;
    }
    _lastSnappedGpsPosition = driverLatLng;
    if (routePoints.isEmpty) {
      _cachedSnappedPoint = null;
      return null;
    }
    final rawSnap = snapPointToRoute(driverLatLng, routePoints);
    if (rawSnap != null) {
      final distToRoute = driverLatLng.distanceWith(rawSnap.position);
      final dynamicOffRouteThreshold = _getDynamicOffRouteThreshold(DriverSpeed.kmh.value);
      if (distToRoute <= dynamicOffRouteThreshold) {
        _cachedSnappedPoint = rawSnap;
      } else {
        _cachedSnappedPoint = null;
      }
    } else {
      _cachedSnappedPoint = null;
    }
    return _cachedSnappedPoint;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      buildWhen: (previous, current) =>
          previous.mapProvider != current.mapProvider,
      builder: (context, settingsState) {
        return BlocConsumer<HomeBloc, HomeState>(
          buildWhen: (previous, current) {
            if (previous.driverStatus != current.driverStatus) return true;

            // Se os waypoints da corrida ativa mudaram (comparação de segurança explícita)
            final prevWaypoints = previous.driverStatus.maybeMap(
              onTrip: (onTrip) => onTrip.order.waypoints,
              orElse: () => null,
            );
            final currWaypoints = current.driverStatus.maybeMap(
              onTrip: (onTrip) => onTrip.order.waypoints,
              orElse: () => null,
            );
            if (prevWaypoints != currWaypoints) return true;

            // Se não estamos seguindo a câmera (o motorista está arrastando/interagindo),
            // evitamos rebuildar a árvore de widgets para eliminar lag no mapa.
            if (!_isFollowing) return false;

            return previous.driverLocation != current.driverLocation;
          },
          listenWhen: (previous, current) {
            if (previous.driverStatus != current.driverStatus) return true;

            // Se os waypoints da corrida ativa mudaram (comparação de segurança explícita)
            final prevWaypoints = previous.driverStatus.maybeMap(
              onTrip: (onTrip) => onTrip.order.waypoints,
              orElse: () => null,
            );
            final currWaypoints = current.driverStatus.maybeMap(
              onTrip: (onTrip) => onTrip.order.waypoints,
              orElse: () => null,
            );
            if (prevWaypoints != currWaypoints) return true;

            return previous.driverLocation != current.driverLocation;
          },
          listener: (context, state) {
            if (state.driverLocation != null) {
              final now = DateTime.now();
              if (_lastLocationUpdateTime != null) {
                final diff = now.difference(_lastLocationUpdateTime!).inMilliseconds;
                // Ajusta a duração da animação para 90% do intervalo real entre pacotes (evita stutters)
                if (diff >= 200 && diff <= 3000) {
                  _markerAnimationDuration = Duration(milliseconds: (diff * 0.9).round());
                }
              }
              _lastLocationUpdateTime = now;
            }
            final isOnTrip = state.driverStatus.maybeMap(
              onTrip: (_) => true,
              orElse: () => false,
            );
            if (!isOnTrip && _activeSurgeZones.isEmpty) {
              _fetchActiveSurgeZones();
            }
            _updateMapCameraWithState(state);
          },
          builder: (context, state) {
            return BlocConsumer<AuthBloc, AuthState>(
              bloc: locator<AuthBloc>(),
              listenWhen: (previous, current) => previous.maybeMap(
                orElse: () => true,
                authenticated: (authenticatedPrevious) => current.maybeMap(
                  orElse: () => false,
                  authenticated: (authenticated) =>
                      authenticatedPrevious.profile.searchRadius !=
                      authenticated.profile.searchRadius,
                ),
              ),
              listener: (context, stateAuth) {
                state.driverStatus.maybeMap(
                  online: (value) {
                    final radius = stateAuth.maybeMap(
                      orElse: () => null,
                      authenticated: (authenticated) =>
                          authenticated.profile.searchRadius,
                    );

                    if (state.markers.isNotEmpty &&
                        value.orderRequests.isEmpty) {
                      fitMapToCenterAndRadius(
                        state.markers.first.position,
                        radius ?? 10000,
                      );
                    }
                  },
                  orElse: () {
                    if (state.markers.isNotEmpty) {
                      controller?.moveCamera(
                        state.markers.first.position,
                        null,
                      );
                    }
                  },
                );
              },
              builder: (context, stateAuth) {
                final radius = stateAuth.maybeMap(
                  orElse: () => null,
                  authenticated: (authenticated) =>
                      authenticated.profile.searchRadius,
                );
                debugPrint('[MapView] AuthBloc builder — stateAuth: ${stateAuth.runtimeType}, radius: $radius, driverLocation: ${state.driverLocation}, driverStatus: ${state.driverStatus.runtimeType}');
                debugPrint('[MapView] circleMarkers count: ${state.circleMarkers(radius).length}');
                final surgeCircles = _activeSurgeZones.map((zone) {
                  final center = _getCenterOfSurgeZone(zone);
                  return CircleMarker(
                    id: 'surge_circle_${zone['id']}',
                    position: center,
                    radius: 400.0,
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderColor: Colors.orangeAccent.withValues(alpha: 0.8),
                    borderWidth: 1.5,
                  );
                }).toList();

                final surgeMarkers = _activeSurgeZones.map((zone) {
                  final center = _getCenterOfSurgeZone(zone);
                  final multiplier =
                      (zone['multiplier'] as num?)?.toDouble() ?? 1.0;
                  return CustomMarker(
                    // O multiplicador faz parte do id: o cache de bitmap do
                    // Google é por id — sem isso o badge ficava congelado em
                    // "1.5x" mesmo depois do valor mudar.
                    id: 'surge_${zone['id']}_${multiplier.toStringAsFixed(1)}',
                    position: center,
                    width: 70,
                    height: 36,
                    widget: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: Colors.orangeAccent, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orangeAccent.withValues(alpha: 0.4),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.flash_on,
                            color: Colors.orangeAccent,
                            size: 14,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${multiplier.toStringAsFixed(1)}x',
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList();

                // Marcador do motorista na navegação: seta (chevron) "grudada"
                // na rua mais próxima da rota (map-matching visual). Calculado
                // aqui, no mesmo instante do GPS novo, para não ter atraso.
                final isOnTrip = state.driverStatus.maybeMap(
                  onTrip: (_) => true,
                  orElse: () => false,
                );
                final isGoogleMaps = settingsState.mapProviderEnum == MapProviderEnum.googleMaps;
                CustomMarker? navDriverMarker;
                
                 // Desenha o marcador dinâmico do motorista (seta na navegação, carro/moto fora dela).
                 // Em ambos os casos, a rotação e a posição são computadas e animadas em tempo real.
                 if (state.driverLocation != null) {
                   final raw = LatLng(
                     state.driverLocation!.lat,
                     state.driverLocation!.lng,
                   );
                   
                   SnappedPoint? snapped;
                   if (isOnTrip) {
                     final routePoints = HomeNavigationOverlay.activeRouteNotifier.value;
                     snapped = _getSnappedPoint(raw, routePoints);
                   }

                   // Prioridade da rotação da seta: rota snapped > GPS em
                   // movimento > último rumo bom (em corrida) > bússola (fora
                   // de corrida). A bússola dentro do carro sofre interferência
                   // magnética e fazia a seta apontar para qualquer lado.
                   final isMoving = _isMovingNow();
                   final int markerRot;
                   if (snapped != null) {
                     markerRot = snapped.bearing.toInt();
                   } else if (isMoving) {
                     final gpsRot = state.driverLocation!.rotation;
                     // rotation == 0 em muitos aparelhos significa "heading
                     // indisponível", não "norte" (mesma checagem da câmera).
                     markerRot = (gpsRot != null && gpsRot != 0)
                         ? gpsRot
                         : _navBearing.toInt();
                   } else if (isOnTrip) {
                     markerRot = _navBearing.toInt();
                   } else {
                     markerRot = _deviceHeading.toInt();
                   }

                   navDriverMarker = state.driverLocation!.animatedMarker(
                     navigationMode: isOnTrip,
                     overridePosition: snapped?.position,
                     overrideRotation: markerRot,
                     isGoogleMaps: isGoogleMaps,
                     animationDuration: _markerAnimationDuration,
                   );
                 }

                // Marcador de manobra idêntico ao Google Maps:
                // Balão azul com bico/ponteiro apontando para baixo (speech bubble).
                CustomMarker? maneuverMarker;
                final nextManeuver = HomeNavigationOverlay.nextManeuverNotifier.value;
                if (isOnTrip && nextManeuver != null) {
                  maneuverMarker = CustomMarker(
                    id: 'next_maneuver',
                    position: nextManeuver.location,
                    width: 42,
                    height: 45,
                    alignment: Alignment.bottomCenter,
                    flat: false,
                    widget: SizedBox(
                      width: 42,
                      height: 45,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Corpo do balão azul
                          Container(
                            width: 42,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A73E8), // Azul Google
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 2.5,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              HomeNavigationOverlay.getManeuverIcon(
                                nextManeuver.maneuverType,
                                nextManeuver.modifier,
                              ),
                              color: Colors.white,
                              size: 24,
                              key: const ValueKey('maneuver_icon'),
                            ),
                          ),
                          // Bico apontando para baixo (quadrado rotacionado 45 graus)
                          Transform.translate(
                            offset: const Offset(0, -4.0),
                            child: Transform.rotate(
                              angle: 3.14159265 / 4, // 45 graus (pi / 4)
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF1A73E8), // Mesmo azul Google
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 1,
                                      offset: Offset(0.5, 0.5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Stack(
                  children: [
                    Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerMove: (_) {
                        // Arrastou o mapa ou deu zoom → pausa o follow
                        // e deixa o botão "Recentralizar" aparecer.
                        if (_isFollowing) {
                          setState(() => _isFollowing = false);
                        }
                      },
                      onPointerUp: (_) {
                        final isOnTrip = state.driverStatus
                            .maybeMap(onTrip: (_) => true, orElse: () => false);
                        if (isOnTrip && !_isFollowing) {
                          _scheduleAutoRecenter();
                        }
                      },
                      onPointerCancel: (_) {
                        final isOnTrip = state.driverStatus
                            .maybeMap(onTrip: (_) => true, orElse: () => false);
                        if (isOnTrip && !_isFollowing) {
                          _scheduleAutoRecenter();
                        }
                      },
                      child: AppGenericMap(
                      animateMarkers: _isFollowing,
                      // Desabilitamos a bolinha nativa sempre, usando o marcador customizado do motorista
                      // (carro/moto fora de corrida, chevron na corrida) para evitar duplicação no Google Maps.
                      myLocationEnabled: false,
                      padding: state.mapPadding(
                        settingsState.mapProviderEnum,
                        context,
                      ),
                      onControllerReady: (p0) {
                        controller = p0;
                        _updateMapCameraWithState(context.read<HomeBloc>().state);
                      },
                      circleMarkers: [
                        ...state.circleMarkers(radius),
                        if (!isOnTrip) ...surgeCircles,
                      ],
                      polylines: () {
                          // Debug: verificar se polylines estão sendo geradas para ofertas
                          final statePolylines = state.polylines;
                          final hasNavRoute = isOnTrip && HomeNavigationOverlay.activeRouteNotifier.value.isNotEmpty;
                          if (!isOnTrip) {
                            debugPrint('[MapView] polylines check — isOnTrip: $isOnTrip, hasNavRoute: $hasNavRoute, statePolylines: ${statePolylines.length}, statePolylines points: ${statePolylines.map((p) => p.points.length).toList()}');
                          }
                          if (hasNavRoute) {
                              final routeColors = const [Color(0xFF33CCFF), Color(0xFF33CCFF)];
                              final routeBorderColor = const Color(0xFF0D5F7A);
                              final fullRoute = HomeNavigationOverlay.activeRouteNotifier.value;
                              final driverLoc = state.driverLocation;

                              int driverIdx = 0;
                              if (isOnTrip && driverLoc != null && fullRoute.length > 1) {
                                driverIdx = HomeNavigationOverlay.driverIdxNotifier.value;
                                if (driverIdx >= fullRoute.length) {
                                  driverIdx = fullRoute.length - 1;
                                }
                              }

                              // Trajeto percorrido fica cinza (estilo Waze/Uber)
                              PolyLineLayer? grayLine;
                              List<LatLng> remainingRoute = fullRoute;
                              if (isOnTrip && driverIdx > 0 && driverIdx < fullRoute.length) {
                                final traveledPoints = fullRoute.sublist(0, driverIdx + 1);
                                grayLine = PolyLineLayer(
                                  points: traveledPoints,
                                  width: 8,
                                  gradientColors: [Colors.grey.withOpacity(0.5), Colors.grey.withOpacity(0.5)],
                                  strokeCap: StrokeCap.round,
                                  strokeJoin: StrokeJoin.round,
                                  borderStrokeWidth: 1.2,
                                  borderColor: Colors.grey.shade600.withOpacity(0.5),
                                );
                                remainingRoute = fullRoute.sublist(driverIdx);
                              }

                              // Rota azul base (trajeto restante)
                              List<LatLng> remainingRoutePoints = remainingRoute;
                              if (isOnTrip && driverLoc != null && remainingRoutePoints.isNotEmpty) {
                                final driverLatLng = LatLng(driverLoc.lat, driverLoc.lng);
                                final distToStart = driverLatLng.distanceWith(remainingRoutePoints.first);
                                if (distToStart > 2.0 && distToStart < 150.0) {
                                  remainingRoutePoints = [driverLatLng, ...remainingRoutePoints];
                                }
                              }

                              final blueLine = PolyLineLayer(
                                points: remainingRoutePoints,
                                width: 8,
                                gradientColors: routeColors,
                                strokeCap: StrokeCap.round,
                                strokeJoin: StrokeJoin.round,
                                borderStrokeWidth: 1.2,
                                borderColor: routeBorderColor,
                              );

                              // Trecho verde neon: posição atual → próxima manobra (estilo 99)
                              // Só desenhamos quando há próxima manobra conhecida e motorista em corrida.
                              final maneuver = HomeNavigationOverlay.nextManeuverNotifier.value;
                              PolyLineLayer? greenLine;

                              if (isOnTrip && maneuver != null && driverLoc != null && fullRoute.length > 1) {
                                int maneuverIdx = HomeNavigationOverlay.nextManeuverIdxNotifier.value;
                                if (maneuverIdx >= fullRoute.length) {
                                  maneuverIdx = fullRoute.length - 1;
                                }

                                // Só pinta verde se o trecho tiver pelo menos 2 pontos
                                // e a manobra estiver à frente do motorista na rota
                                if (maneuverIdx > driverIdx) {
                                  List<LatLng> greenPoints = fullRoute.sublist(driverIdx, maneuverIdx + 1);
                                  if (greenPoints.isNotEmpty) {
                                    final driverLatLng = LatLng(driverLoc.lat, driverLoc.lng);
                                    final distToStart = driverLatLng.distanceWith(greenPoints.first);
                                    if (distToStart > 2.0 && distToStart < 150.0) {
                                      greenPoints = [driverLatLng, ...greenPoints];
                                    }
                                  }
                                  greenLine = PolyLineLayer(
                                    points: greenPoints,
                                    width: 8,
                                    // Verde neon estilo 99 Motoristas
                                    gradientColors: const [Color(0xFF00E676), Color(0xFF00E676)],
                                    strokeCap: StrokeCap.round,
                                    strokeJoin: StrokeJoin.round,
                                    borderStrokeWidth: 1.2,
                                    borderColor: const Color(0xFF00843D),
                                  );
                                }
                              }

                              return [
                                if (grayLine != null) grayLine,
                                blueLine,
                                if (greenLine != null) greenLine,
                              ];
                            } else {
                              final radarRequest = RidesRadarSheet.selectedRadarRideNotifier.value;
                              if (radarRequest != null && radarRequest.route.isNotEmpty) {
                                return [radarRequest.route.toPolyLineLayer];
                              }
                              return statePolylines;
                            }
                          }(),
                      interactive: true,
                      mode: MapViewMode.static,
                      initialLocation: Constants.defaultLocation.toGenericMapPlace,
                      markers: [
                        ...state.markers,
                        if (!isOnTrip) ...surgeMarkers,
                        if (!isOnTrip) ...() {
                          final radarRequest = RidesRadarSheet.selectedRadarRideNotifier.value;
                          if (radarRequest != null) {
                            return radarRequest.waypoints.markers;
                          }
                          return <CustomMarker>[];
                        }(),
                        if (navDriverMarker != null) navDriverMarker,
                        if (maneuverMarker != null) maneuverMarker,
                      ],
                      ),
                    ),
                    ...state.driverStatus.maybeMap(
                      onTrip: (onTripState) => [
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: HomeNavigationOverlay(
                            driverLocation: state.driverLocation,
                            onTripStatus: onTripState,
                          ),
                        ),
                        // Velocímetro estilo Waze
                        Positioned(
                          left: 16,
                          top: MediaQuery.of(context).size.height * 0.45,
                          child: const SpeedometerBadge(),
                        ),
                        // Nome da via atual (pílula azul estilo Google Maps)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 14,
                          child: Center(
                            child: ValueListenableBuilder<String>(
                              valueListenable:
                                  HomeNavigationOverlay.currentRoadNotifier,
                              builder: (context, road, _) {
                                if (road.isEmpty) return const SizedBox.shrink();
                                return Container(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width * 0.7,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A73E8),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.35),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.25),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    road,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                      orElse: () => const <Widget>[],
                    ),
                    if (!_isFollowing)
                      Positioned(
                        right: 16,
                        top: MediaQuery.of(context).size.height * 0.45,
                        child: _RecenterButton(
                          onTap: () {
                            _recenterTimer?.cancel();
                            setState(() {
                              _isFollowing = true;
                              _snapNextCameraUpdate = true;
                            });
                            // UPPI BRASIL: Se houver oferta de corrida ativa na tela, recentraliza a rota de forma animada
                            final homeState = context.read<HomeBloc>().state;
                            homeState.driverStatus.mapOrNull(
                              online: (onlineState) {
                                final currentRequest = onlineState.currentOrderRequest;
                                if (currentRequest != null) {
                                  _animateOfferRoute(currentRequest);
                                }
                              },
                            );
                            _updateMapCameraWithState(
                              homeState,
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void fitMapToCenterAndRadius(LatLng center, int radius) {
    final northeast = map_toolkit.SphericalUtil.computeOffset(
      map_toolkit.LatLng(center.latitude, center.longitude),
      radius.toDouble(),
      45,
    ).toLatLong;
    final southwest = map_toolkit.SphericalUtil.computeOffset(
      map_toolkit.LatLng(center.latitude, center.longitude),
      radius.toDouble(),
      225,
    ).toLatLong;
    controller?.fitBounds([northeast, southwest]);
  }

  /// Distância aproximada em metros entre dois pontos (projeção equiretangular).
  /// Suficiente para comparar pontos próximos ao longo da rota sem overhead do Haversine.
  static double _distanceBetween(LatLng a, LatLng b) {
    const double earthR = 6371000;
    final dLat = (b.latitude - a.latitude) * (3.14159265358979 / 180);
    final dLng = (b.longitude - a.longitude) * (3.14159265358979 / 180);
    final x = dLng * math.cos((a.latitude + b.latitude) / 2 * (3.14159265358979 / 180));
    return earthR * math.sqrt(dLat * dLat + x * x);
  }
}

extension MapToolkitLatLng on map_toolkit.LatLng {
  LatLng get toLatLong => LatLng(latitude, longitude);
}

/// Velocímetro estilo iOS: mostra a velocidade atual do motorista (km/h).
/// Lê o valor do GPS via [DriverSpeed.kmh] — sem stream extra, sem custo.
class SpeedometerBadge extends StatelessWidget {
  const SpeedometerBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: HomeNavigationOverlay.speedLimitNotifier,
      builder: (context, limit, _) {
        return ValueListenableBuilder<double>(
          valueListenable: DriverSpeed.kmh,
          builder: (context, kmh, _) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final speed = kmh.round();
            
            // Lógica de cores profissional baseada no limite dinâmico
            Color bgColor = isDark ? Colors.black.withOpacity(0.72) : Colors.white.withOpacity(0.85);
            Color borderColor = isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.45);
            Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);
            Color labelColor = isDark ? Colors.white70 : const Color(0xFF64748B);
            
            if (kmh > limit) {
              // Limite ultrapassado: borda laranja
              borderColor = Colors.orange;
            }
            // Alerta vermelho para velocidades muito altas — vale mesmo quando
            // o limite da via é desconhecido (limit = infinity).
            if (kmh > 110.0 || kmh > limit + 20) {
              bgColor = Colors.red.withOpacity(isDark ? 0.85 : 0.9);
              borderColor = Colors.redAccent;
              textColor = Colors.white;
              labelColor = Colors.white70;
            }

            return Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 10,
                    spreadRadius: 1,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: borderColor,
                        width: kmh > limit ? 2.5 : 1.2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          speed.toString(),
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            color: textColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          ),
                        ),
                        Text(
                          'km/h',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            color: labelColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Botão flutuante "Recentralizar" (estilo Google/Waze) para voltar a seguir
/// o motorista depois que o usuário arrastou o mapa.
class _RecenterButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RecenterButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.my_location, color: Color(0xFF1A73E8), size: 18),
              SizedBox(width: 6),
              Text(
                'Recentralizar',
                style: TextStyle(
                  color: Color(0xFF1A73E8),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SpeechBubblePainter extends CustomPainter {
  final Color color;

  SpeechBubblePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const radius = 6.0;
    const tailHeight = 5.0;
    const tailWidth = 8.0;
    final bodyHeight = size.height - tailHeight;

    final path = Path();
    // Início no canto superior esquerdo
    path.moveTo(radius, 0);
    path.lineTo(size.width - radius, 0);
    path.arcToPoint(Offset(size.width, radius), radius: const Radius.circular(radius));
    
    // Lateral direita
    path.lineTo(size.width, bodyHeight - radius);
    path.arcToPoint(Offset(size.width - radius, bodyHeight), radius: const Radius.circular(radius));
    
    // Parte inferior (direita do bico)
    path.lineTo(size.width / 2 + tailWidth / 2, bodyHeight);
    // Bico apontando para baixo
    path.lineTo(size.width / 2, size.height);
    path.lineTo(size.width / 2 - tailWidth / 2, bodyHeight);
    
    // Parte inferior (esquerda do bico)
    path.lineTo(radius, bodyHeight);
    path.arcToPoint(Offset(0, bodyHeight - radius), radius: const Radius.circular(radius));
    
    // Lateral esquerda
    path.lineTo(0, radius);
    path.arcToPoint(Offset(radius, 0), radius: const Radius.circular(radius));
    path.close();

    // Sombra sutil ao redor do balão
    canvas.drawShadow(path, Colors.black, 3.0, true);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant SpeechBubblePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
