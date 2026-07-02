import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/config/constants.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:flutter_common/core/presentation/markers/app_marker_pickup.dart';
import 'package:generic_map/generic_map.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:flutter_common/core/blocs/settings.dart';
import 'package:rider_flutter/core/datasources/geo_datasource.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:flutter_common/core/presentation/markers/app_marker_drop_off.dart';
import 'package:rider_flutter/core/presentation/app_generic_map.dart';
import 'package:rider_flutter/features/home/presentation/blocs/home.dart';
import 'package:rider_flutter/features/home/presentation/blocs/home.extensions.dart';
import 'package:rider_flutter/features/home/presentation/blocs/place_confirm.dart';
import 'package:latlong2/latlong.dart';
import 'current_location_marker.dart';

class HomeMap extends StatefulWidget {
  static final ValueNotifier<int> trackDriverTrigger = ValueNotifier<int>(0);
  static final ValueNotifier<int> centerOnUserLocationTrigger = ValueNotifier<int>(0);
  static final ValueNotifier<double?> confirmLocationZoom = ValueNotifier<double?>(null);
  static final ValueNotifier<bool> isPreviewExpanded = ValueNotifier<bool>(false);

  const HomeMap({super.key});

  @override
  State<HomeMap> createState() => _HomeMapState();
}

class _HomeMapState extends State<HomeMap> {
  MapViewController? mapViewController;
  String? _lastFitRideId;
  OrderStatus? _lastFitStatus;
  bool _hasMovedToCurrentLocation = false;
  bool _isFollowing = true;
  bool _isMapDragged = false;
  bool _isMovingProgrammatically = false;



  @override
  void initState() {
    super.initState();
    HomeMap.trackDriverTrigger.addListener(_onTrackDriverRequested);
    HomeMap.centerOnUserLocationTrigger.addListener(_onCenterOnUserLocationRequested);
    HomeMap.confirmLocationZoom.addListener(_onConfirmLocationZoomChanged);
    HomeMap.isPreviewExpanded.addListener(_onIsPreviewExpandedChanged);
  }

  @override
  void dispose() {
    HomeMap.trackDriverTrigger.removeListener(_onTrackDriverRequested);
    HomeMap.centerOnUserLocationTrigger.removeListener(_onCenterOnUserLocationRequested);
    HomeMap.confirmLocationZoom.removeListener(_onConfirmLocationZoomChanged);
    HomeMap.isPreviewExpanded.removeListener(_onIsPreviewExpandedChanged);
    super.dispose();
  }

  void _onIsPreviewExpandedChanged() {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
      final state = locator<HomeCubit>().state;
      state.mapOrNull(
        ridePreview: (value) {
          final points = value.directions.isNotEmpty
              ? value.directions.map((e) => e.latLng).toList()
              : value.waypoints.latLngs;
          _fitRidePreviewBounds(points);
        },
      );
    }
  }

  void _fitRidePreviewBounds(List<LatLng> points) {
    debugPrint("UPPI BRASIL - _fitRidePreviewBounds: points length = ${points.length}, mapViewController is null: ${mapViewController == null}");
    if (points.length < 2) return;

    // O SDK nativo do Google Maps aplica o padding de forma assíncrona.
    // Chamamos fitBounds em 3 momentos distintos para garantir que o
    // SDK já processou o padding do bottom sheet antes de animar a câmera.

    // 1ª tentativa: após o mapa estar inicializado
    Future.delayed(const Duration(milliseconds: 800), () {
      debugPrint("UPPI BRASIL - fitBounds 1st try (800ms): mounted=$mounted, mapViewController is null: ${mapViewController == null}");
      if (mounted) mapViewController?.fitBounds(points);
    });

    // 2ª tentativa: após a transição do card completar
    Future.delayed(const Duration(milliseconds: 1500), () {
      debugPrint("UPPI BRASIL - fitBounds 2nd try (1500ms): mounted=$mounted, mapViewController is null: ${mapViewController == null}");
      if (mounted) mapViewController?.fitBounds(points);
    });

    // 3ª tentativa: garantia final com padding nativo 100% aplicado
    Future.delayed(const Duration(milliseconds: 2500), () {
      debugPrint("UPPI BRASIL - fitBounds 3rd try (2500ms): mounted=$mounted, mapViewController is null: ${mapViewController == null}");
      if (mounted) mapViewController?.fitBounds(points);
    });
  }

  void _onConfirmLocationZoomChanged() {
    final zoom = HomeMap.confirmLocationZoom.value;
    if (zoom != null && mapViewController != null) {
      final state = locator<HomeCubit>().state;
      state.mapOrNull(
        confirmLocation: (value) {
          final placeState = locator<PlaceConfirmCubit>().state;
          final targetLatLng = placeState.maybeMap(
            loaded: (loaded) => loaded.data.latLng2,
            orElse: () => value.selectedLocation.latLng2,
          );
          mapViewController?.moveCamera(
            targetLatLng,
            zoom,
            bearing: 0.0,
            tilt: 0.0,
          );
        },
      );
    }
  }

  void _updateCameraRotation() {
    if (mapViewController == null || !_isFollowing) return;
    final state = locator<HomeCubit>().state;
    state.mapOrNull(
      rideInProgress: (value) {
        if (value.driverLocation != null) {
          mapViewController?.moveCamera(
            LatLng(value.driverLocation!.lat, value.driverLocation!.lng),
            18,
            bearing: 0.0,
            tilt: 0.0,
          );
        }
      },
      welcome: (value) {
        if (value.waypoints.first != null) {
          mapViewController?.moveCamera(
            value.waypoints.first!.toGenericMapPlace.latLng,
            16,
            bearing: 0.0,
            tilt: 0.0,
          );
        }
      },
    );
  }

  void _onTrackDriverRequested() {
    setState(() {
      _isFollowing = true;
    });
    _updateCameraRotation();
  }

  void _onCenterOnUserLocationRequested() {
    setState(() {
      _isFollowing = true;
    });
    _updateCameraRotation();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<HomeCubit, HomeState>(
      buildWhen: (previous, current) {
        return previous.mapViewMode != current.mapViewMode ||
            previous.isInteractive != current.isInteractive ||
            previous.polylines != current.polylines ||
            previous.markers != current.markers;
      },
      listenWhen: (previous, current) {
        final wasWelcome = previous.maybeMap(welcome: (_) => true, orElse: () => false);
        final isWelcome = current.maybeMap(welcome: (_) => true, orElse: () => false);
        if (!wasWelcome && isWelcome) {
          _hasMovedToCurrentLocation = false;
        }
        return true;
      },
      listener: (context, state) {
        state.mapOrNull(
          welcome: (value) {
            if (value.waypoints.first == null) return;
            if (!_hasMovedToCurrentLocation && mapViewController != null) {
              _hasMovedToCurrentLocation = true;
              mapViewController?.moveCamera(
                value.waypoints.first!.toGenericMapPlace.latLng,
                16,
              );
            }
          },
          ridePreview: (value) {
            final points = value.directions.isNotEmpty
                ? value.directions.map((e) => e.latLng).toList()
                : value.waypoints.latLngs;
            _fitRidePreviewBounds(points);
          },
          rideInProgress: (value) {
            if (value.markers.length < 2) return;
            if (_lastFitRideId != value.order.id || _lastFitStatus != value.order.status) {
              _lastFitRideId = value.order.id;
              _lastFitStatus = value.order.status;
              _isFollowing = true;
              if (mapViewController != null) {
                mapViewController?.fitBounds(
                  value.markers.map((e) => e.position).toList(),
                );
              }
            } else if (_isFollowing && value.driverLocation != null && mapViewController != null) {
              mapViewController?.moveCamera(
                LatLng(value.driverLocation!.lat, value.driverLocation!.lng),
                18,
                bearing: 0.0,
                tilt: 0.0,
              );
            }
          },
          confirmLocation: (value) {
            debugPrint("UPPI BRASIL - confirmLocation: ${value.selectedLocation.address} at ${value.selectedLocation.latLng2.latitude}, ${value.selectedLocation.latLng2.longitude}");
            locator<PlaceConfirmCubit>().onLoaded(place: value.selectedLocation);
            _isMapDragged = false;
            _isMovingProgrammatically = true;
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) {
                mapViewController?.moveCamera(
                  value.selectedLocation.latLng2,
                  16,
                  tilt: 0.0,
                  bearing: 0.0,
                );
              }
            });
          },
          rateDriver: (value) {
            if (value.markers.length < 2) return;
            mapViewController?.fitBounds(
              value.markers.map((e) => e.position).toList(),
            );
          },
        );
      },
      builder: (context, state) {
        return BlocBuilder<SettingsCubit, SettingsState>(
          buildWhen: (previous, current) =>
              previous.mapProvider != current.mapProvider ||
              previous.themeMode != current.themeMode,
          builder: (context, settingsState) {
            final isDarkMode = settingsState.themeMode == ThemeMode.dark ||
                (settingsState.themeMode == ThemeMode.system &&
                    MediaQuery.of(context).platformBrightness == Brightness.dark);
            return Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) {
                      // Do not mark as dragged on pointer down, as taps on overlays/sheets propagate here
                    },
                    onPointerMove: (_) {
                      _isMapDragged = true;
                      _isMovingProgrammatically = false;
                      if (_isFollowing) {
                        setState(() {
                          _isFollowing = false;
                        });
                      }
                    },
                    child: AppGenericMap(
                      key: const ValueKey('home_app_generic_map'),
                      mapProvider: settingsState.mapProviderEnum,
                      padding: () {
                        if (state.mapViewMode == MapViewMode.picker) {
                          return EdgeInsets.zero;
                        }
                        final mediaQuery = MediaQuery.of(context);
                        final isMobile = mediaQuery.size.width < 600;
                        final screenHeight = mediaQuery.size.height;
                        
                        final double bottomSheetHeight = state.maybeMap(
                          ridePreview: (_) => HomeMap.isPreviewExpanded.value ? 560.0 : 220.0,
                          rideInProgress: (_) => 300.0,
                          rateDriver: (_) => 300.0,
                          orElse: () => 160.0,
                        );

                        if (isMobile) {
                          double topPadding = 120.0;
                          double bottomPadding = bottomSheetHeight;
                          
                          final maxAllowedPadding = screenHeight - 120.0;
                          if (topPadding + bottomPadding > maxAllowedPadding) {
                            bottomPadding = maxAllowedPadding - topPadding;
                            if (bottomPadding < 0) {
                              bottomPadding = 0;
                              topPadding = maxAllowedPadding;
                            }
                          }

                          return EdgeInsets.only(
                            left: 48,
                            right: 48,
                            top: topPadding,
                            bottom: bottomPadding,
                          );
                        } else {
                          return const EdgeInsets.symmetric(horizontal: 148, vertical: 148)
                              .copyWith(bottom: 80);
                        }
                      }(),
                      mode: state.mapViewMode,
                      interactive: state.isInteractive,
                      polylines: state.polylines,
                      onControllerReady: (controller) {
                        mapViewController = controller;
                        state.mapOrNull(
                          welcome: (value) {
                            if (value.waypoints.first != null && !_hasMovedToCurrentLocation) {
                              _hasMovedToCurrentLocation = true;
                              controller.moveCamera(
                                value.waypoints.first!.toGenericMapPlace.latLng,
                                16,
                              );
                            }
                          },
                          confirmLocation: (value) {
                            _isMovingProgrammatically = true;
                            controller.moveCamera(
                              value.selectedLocation.latLng2,
                              16,
                              tilt: 0.0,
                              bearing: 0.0,
                            );
                          },
                          ridePreview: (value) {
                            final points = value.directions.isNotEmpty
                                ? value.directions.map((e) => e.latLng).toList()
                                : value.waypoints.latLngs;
                            _fitRidePreviewBounds(points);
                          },
                          rideInProgress: (value) {
                            if (value.markers.length >= 2) {
                              _lastFitRideId = value.order.id;
                              _lastFitStatus = value.order.status;
                              controller.fitBounds(
                                value.markers.map((e) => e.position).toList(),
                              );
                            }
                          },
                          rateDriver: (value) {
                            if (value.markers.length >= 2) {
                              controller.fitBounds(
                                value.markers.map((e) => e.position).toList(),
                              );
                            }
                          },
                        );
                      },
                      centerMarkerBuilder: state.maybeMap(
                        orElse: () => null,
                        confirmLocation: (value) {
                          return (context, key, address) {
                            final dragSubtitle = Localizations.localeOf(context).languageCode == 'pt'
                                ? "Arraste para ajustar"
                                : "Drag to adjust";
                            if (value.index == 0) {
                              return AppMarkerPickup(
                                address: dragSubtitle,
                                key: key,
                              ).centerMarker;
                            } else {
                              return AppMarkerDropoff(
                                address: dragSubtitle,
                                key: key,
                              ).centerMarker;
                            }
                          };
                        },
                        welcome: (value) =>
                            (context, key, address) => CurrentLocationMarker(
                                  key: key,
                                ).marker,
                      ),
                      addressResolver: state.mapViewMode == MapViewMode.static
                          ? null
                          : (provider, location) async {
                              final settingsState = locator<SettingsCubit>().state;
                              final result =
                                  await locator<GeoDatasource>().getAddressForLocation(
                                latLng: location,
                                language: settingsState.locale,
                                mapProvider: settingsState.mapProviderEnum,
                              );
                              return result.fold(
                                (l) => Place(location, "${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}", ""),
                                (r) => Place(
                                  location,
                                  r.address,
                                  r.title,
                                ),
                              );
                            },
                      onMapMoved: (place) {
                        state.mapOrNull(
                          confirmLocation: (confirmLocation) {
                            if (_isMovingProgrammatically) {
                              if (place != null) {
                                _isMovingProgrammatically = false;
                              }
                              return;
                            }
                            if (!_isMapDragged) return;
                            if (place == null) {
                              locator<PlaceConfirmCubit>().onLoading();
                            } else {
                              locator<PlaceConfirmCubit>().onLoaded(
                                place: place.toPlaceEntity,
                              );
                            }
                          },
                          welcome: (welcome) {
                            if (place != null &&
                                state.mapViewMode == MapViewMode.picker) {
                              locator<HomeCubit>().onMapMoved(
                                selectedLocation: place.toPlaceEntity,
                              );
                            }
                          },
                        );
                      },
                      markers: state.markers,
                      initialLocation: state.waypoints.firstOrNull?.toGenericMapPlace ??
                          Constants.defaultLocation.toGenericMapPlace,
                      myLocationEnabled: false,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
