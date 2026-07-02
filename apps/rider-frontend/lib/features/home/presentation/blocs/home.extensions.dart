import 'package:flutter/material.dart';
import 'package:flutter_common/core/presentation/animated_driver_marker.dart';
import 'package:flutter_common/core/presentation/markers/app_marker.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:generic_map/generic_map.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/blocs/location.dart';
import 'package:flutter_common/core/blocs/settings.dart';
import '../components/current_location_marker.dart';
import 'package:flutter_common/core/presentation/markers/app_marker_pickup.dart';
import 'package:flutter_common/core/presentation/markers/app_marker_drop_off.dart';

import 'home.dart';

extension HomeStateX on HomeState {
  List<CustomMarker> get markers => map(
        loading: (_) => [],
        error: (_) => [],
        welcome: (value) {
          final settingsState = locator<SettingsCubit>().state;
          final isGoogleMaps = settingsState.mapProviderEnum == MapProviderEnum.googleMaps;
          final markersList = <CustomMarker>[];
          markersList.addAll(value.driversAround.animatedMarkersWith(isGoogleMaps: isGoogleMaps));
          final userLocation = locator<LocationCubit>().state.mapOrNull(
                determined: (determinedState) => determinedState.place,
              );
          if (userLocation != null) {
            markersList.add(
              CustomMarker(
                id: 'current_location',
                position: userLocation.latLng2,
                widget: const CurrentLocationMarker(),
                width: 60,
                height: 60,
                alignment: Alignment.center,
              ),
            );
          }
          return markersList;
        },
        inputWaypoints: (value) {
          void onTap() {
            locator<HomeCubit>().showWaypoints(waypoints: value.waypoints);
          }
          return value.waypoints.nonNulls.toList().markersWithOnTap(onTap: onTap);
        },
        confirmLocation: (value) {
          final markersList = <CustomMarker>[];
          final userLocation = locator<LocationCubit>().state.mapOrNull(
                determined: (determinedState) => determinedState.place,
              );
          if (userLocation != null) {
            markersList.add(
              CustomMarker(
                id: 'current_location',
                position: userLocation.latLng2,
                widget: const CurrentLocationMarker(),
                width: 60,
                height: 60,
                alignment: Alignment.center,
              ),
            );
          }
          return markersList;
        },
        ridePreview: (value) {
          void onTap() {
            locator<HomeCubit>().showWaypoints(waypoints: value.waypoints);
          }
          final markers = <CustomMarker>[];
          final list = value.waypoints;

          if (list.isNotEmpty) {
            final homeCubit = locator<HomeCubit>();
            final hasRoute = homeCubit.durationInSeconds > 0;
            final rawMin = (homeCubit.durationInSeconds / 60).round();
            final durationMin = rawMin > 0 ? rawMin : 1;
            final distanceKm = (homeCubit.distanceInMeters / 1000).toStringAsFixed(1).replaceAll('.', ',');

            final firstElement = list.first;
            final pickupAddress = hasRoute ? "5 min ${firstElement.address}" : firstElement.address;

            markers.add(
              AppMarkerPickup(
                address: pickupAddress,
                onTap: onTap,
              ).genericMarker(firstElement.latLng2),
            );

            if (list.length >= 2) {
              final lastElement = list.last;
              final dropoffAddress = hasRoute ? "$distanceKm km\n$durationMin min ${lastElement.address}" : lastElement.address;
              markers.add(
                AppMarkerDropoff(
                  address: dropoffAddress,
                  onTap: onTap,
                ).genericMarker(lastElement.latLng2),
              );
            }

            if (list.length > 2) {
              for (int i = 1; i < list.length - 1; i++) {
                markers.add(
                  AppMarkerStop(
                    address: list[i].address,
                    stopIndex: i,
                    onTap: onTap,
                  ).genericMarker(list[i].latLng2),
                );
              }
            }
          }

          if (value._directions.isNotEmpty) {
            markers.addAll(value._directions.directionsCapMarkers);
          }
          return markers;
        },
        rideInProgress: (value) {
          final markers = <CustomMarker>[];
          void onTap() {
            locator<HomeCubit>().showWaypoints(waypoints: value.order.waypoints);
          }
          if (value.order.status.viewMode == OrderStatusViewMode.looking) {
            markers.addAll(value.order.waypoints.markersWithOnTap(onTap: onTap));
            return markers;
          }
          final settingsState = locator<SettingsCubit>().state;
          final isGoogleMaps = settingsState.mapProviderEnum == MapProviderEnum.googleMaps;
          if (value.driverLocation != null) {
            markers.add(value.driverLocation!.animatedMarker(
              isGoogleMaps: isGoogleMaps,
              navigationMode: false,
            ));
          }
          final arrivedToWaypointIndex = value.order.arrivedAtWaypointIndex;
          if (arrivedToWaypointIndex != null && arrivedToWaypointIndex >= 0) {
            int? remainingMin;
            final expectedAt = value.order.expectedAt;
            remainingMin = expectedAt.difference(DateTime.now()).inMinutes;
            final minutesStr = (remainingMin != null && remainingMin > 0) ? "$remainingMin min " : "";

            markers.add(
              AppMarkerDropoff(
                address: "$minutesStr${value.order.waypoints[arrivedToWaypointIndex + 1].address}",
                onTap: onTap,
              ).genericMarker(value.order.waypoints[arrivedToWaypointIndex + 1].latLng2),
            );
          } else {
            int? remainingMin;
            final etaPickup = value.order.etaPickup;
            if (etaPickup != null) {
              remainingMin = etaPickup.difference(DateTime.now()).inMinutes;
            }
            final minutesStr = (remainingMin != null && remainingMin > 0) ? "$remainingMin min " : "";

            markers.add(
              AppMarkerPickup(
                address: "$minutesStr${value.order.waypoints.first.address}",
                onTap: onTap,
              ).genericMarker(value.order.waypoints.first.latLng2),
            );
          }

          if (_directions.isNotEmpty) {
            markers.addAll(_directions.directionsCapMarkers);
          }

          return markers;
        },
        rateDriver: (value) => value.order.waypoints.markers,
      );

  bool get isInteractive => map(
        loading: (_) => false,
        welcome: (_) => true,
        inputWaypoints: (_) => false,
        confirmLocation: (_) => true,
        ridePreview: (_) => true,
        rideInProgress: (_) => true,
        rateDriver: (_) => false,
        error: (_) => false,
      );

  MapViewMode get mapViewMode {
    return maybeMap(
      orElse: () => MapViewMode.static,
      confirmLocation: (_) => MapViewMode.picker,
    );
  }

  List<LatLngEntity> get _directions {
    return maybeMap(
      orElse: () => [],
      ridePreview: (preview) => preview.directions,
      rideInProgress: (ride) {
        switch (ride.order.status) {
          case OrderStatus.driverAccepted:
            return ride.order.driverDirections;
          case OrderStatus.arrived:
            return [];

          case OrderStatus.waitingForPrePay:
          case OrderStatus.waitingForPostPay:
          case OrderStatus.found:
          case OrderStatus.requested:
          case OrderStatus.noCloseFound:
          case OrderStatus.notFound:
          case OrderStatus.waitingForReview:
          case OrderStatus.booked:
          case OrderStatus.started:
            return ride.order.rideDirections;

          case OrderStatus.driverCanceled:
          case OrderStatus.riderCanceled:
          case OrderStatus.finished:
          case OrderStatus.expired:
            return [];
        }
      },
    );
  }

  List<PolyLineLayer> get polylines => [
        if (_directions.isNotEmpty)
          // Linha estilo Ridy Taxi — gradiente azul → ciano
          PolyLineLayer(
            points: _directions.map((e) => e.latLng).toList(),
            width: 3,
            color: const Color(0xff2892FF),
            gradientColors: const [
              Color(0xff2892FF), // Azul brilhante (início / partida)
              Color(0xff45FCDE), // Ciano / verde-água (fim / destino)
            ],
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
      ];
}
