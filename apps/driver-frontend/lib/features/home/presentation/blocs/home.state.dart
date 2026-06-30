part of 'home.dart';

@freezed
sealed class HomeState with _$HomeState {
  const factory HomeState({
    DriverLocation? driverLocation,
    DateTime? lastLocationUpdate,
    Failure? error,
    @Default(HomeStateDriverStatus.initial())
    HomeStateDriverStatus driverStatus,
  }) = _HomeState;

  factory HomeState.fromJson(Map<String, dynamic> json) =>
      _$HomeStateFromJson(json);

  const HomeState._();

  List<LatLngEntity> get _directions {
    return driverStatus.maybeMap(
      orElse: () => [],
      onTrip: (ride) {
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

  EdgeInsets mapPadding(MapProviderEnum map, BuildContext context) {
    switch (driverStatus) {
      case OnlineDriverStatus(:final orderRequests):
        if (orderRequests.isEmpty) {
          return EdgeInsets.only(
            bottom: 20,
            left: map == MapProviderEnum.googleMaps ? 16 : 100,
            right: map == MapProviderEnum.googleMaps ? 16 : 100,
            top: 100,
          );
        } else {
          return EdgeInsets.only(
            bottom: 280,
            left: map == MapProviderEnum.googleMaps ? 16 : 100,
            right: map == MapProviderEnum.googleMaps ? 16 : 100,
            top: 80,
          );
        }
      case OnTripDriverStatus():
        // Navegação: top alto empurra o motorista para a parte de baixo da
        // tela, deixando mais rua visível à frente (sensação "Google dirigindo").
        return EdgeInsets.only(
          bottom: 16,
          left: map == MapProviderEnum.googleMaps ? 16 : 100,
          right: map == MapProviderEnum.googleMaps ? 16 : 100,
          top: 260,
        );
      case OfflineDriverStatus():
      case AccessDeniedDriverStatus():
      case InitialDriverStatus():
      case LoadingDriverStatus():
        return EdgeInsets.only(
          bottom: 16,
          left: map == MapProviderEnum.googleMaps ? 16 : 100,
          right: map == MapProviderEnum.googleMaps ? 16 : 100,
          top: 140,
        );
    }
  }

  List<CustomMarker> get markers {
    return driverStatus.maybeMap(
      orElse: () => [],
      online: (online) {
        final currentRequest = online.currentOrderRequest;
        if (currentRequest != null) {
          return currentRequest.waypoints.markers;
        }
        return [];
      },
      onTrip: (onTrip) {
        // Em navegação, o marcador do motorista (seta/chevron "grudada na rua")
        // é montado no HomeMapView, que tem a geometria da rota para o
        // map-matching. Aqui devolvemos só waypoints e marcadores de direção.
        final List<CustomMarker> waypointsMarkers = switch (onTrip
            .order
            .status) {
          OrderStatus.driverAccepted => onTrip.order.waypoints.markers.isNotEmpty
              ? [onTrip.order.waypoints.markers.first]
              : [],
          OrderStatus.arrived => onTrip.order.waypoints.markers.isNotEmpty
              ? [onTrip.order.waypoints.markers.first]
              : [],
          OrderStatus.waitingForPrePay => onTrip.order.waypoints.markers,
          OrderStatus.waitingForPostPay => onTrip.order.waypoints.markers,
          OrderStatus.started => () {
              final index = onTrip.order.destinationArrivedTo != null
                  ? onTrip.order.destinationArrivedTo! + 2
                  : 1;
              if (onTrip.order.waypoints.markers.isNotEmpty &&
                  index >= 0 &&
                  index < onTrip.order.waypoints.markers.length) {
                return [onTrip.order.waypoints.markers[index]];
              }
              return <CustomMarker>[];
            }(),
          _ => onTrip.order.waypoints.markers,
        };
        return [
          ...waypointsMarkers,
        ];
      },
      offline: (offline) {
        return [];
      },
    );
  }

  List<PolyLineLayer> get polylines => driverStatus.maybeMap(
    orElse: () => [],
    online: (online) {
      final currentRequest = online.currentOrderRequest;
      if (currentRequest != null && currentRequest.route.isNotEmpty) {
        return [currentRequest.route.toPolyLineLayer];
      }
      return [];
    },
    onTrip: (onTrip) {
      return [_directions.toPolyLineLayer];
    },
  );

  List<CircleMarker> circleMarkers(int? radius) => driverStatus.maybeMap(
    orElse: () => [],
    online: (value) {
      if (radius == null || driverLocation == null) return [];
      return [
        CircleMarker(
          id: 'search_radius_circle',
          position: LatLng(driverLocation!.lat, driverLocation!.lng),
          radius: radius.toDouble(),
          color: ColorPalette.primary80.withValues(alpha: 0.2),
          borderColor: ColorPalette.primary80.withValues(alpha: 0.8),
          borderWidth: 1,
        ),
      ];
    },
  );
}

@freezed
sealed class OnTripPage with _$OnTripPage {
  const factory OnTripPage.overview() = _Overview;

  const factory OnTripPage.chat() = _Chat;

  const factory OnTripPage.payment() = _Payment;

  const factory OnTripPage.rate() = _Rate;

  factory OnTripPage.fromJson(Map<String, dynamic> json) =>
      _$OnTripPageFromJson(json);
}

@freezed
sealed class HomeStateDriverStatus with _$HomeStateDriverStatus {
  const factory HomeStateDriverStatus.initial() = InitialDriverStatus;

  const factory HomeStateDriverStatus.loading() = LoadingDriverStatus;

  const factory HomeStateDriverStatus.online({
    required List<OrderRequestEntity> orderRequests,
    OrderRequestEntity? currentOrderRequest,
  }) = OnlineDriverStatus;

  const factory HomeStateDriverStatus.offline() = OfflineDriverStatus;

  const factory HomeStateDriverStatus.onTrip({
    required OrderEntity order,
    @Default(OnTripPage.overview()) OnTripPage page,
    DriverLocation? driverLocation,
    Failure? error,
  }) = OnTripDriverStatus;

  const factory HomeStateDriverStatus.accessDenied() = AccessDeniedDriverStatus;

  factory HomeStateDriverStatus.fromJson(Map<String, dynamic> json) =>
      _$HomeStateDriverStatusFromJson(json);
}
