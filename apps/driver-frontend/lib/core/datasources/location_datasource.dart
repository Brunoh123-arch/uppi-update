import 'dart:async';

import 'package:uppi_motorista/core/enums/location_permission.dart';
import 'package:flutter_common/core/entities/driver_location.dart';

abstract class LocationDatasource {
  final _controller = StreamController<DriverLocation>();

  late final Stream<DriverLocation> driverLocation =
      _controller.stream.asBroadcastStream();

  Future<LocationPermission> getLocationPermissionStatus();
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> requestLocationPermission();
  Future<bool> requestLocationService();
  Future<DriverLocation?> getCurrentLocation();
  Future<void> startGettingLocationUpdates();
  void updateLocationSettings({required bool inRide});
  void updateBatterySaverMode(bool enabled);
  void stopGettingLocationUpdates();
  Future<bool> openAppSettings();

  /// Coordenadas pendentes armazenadas em buffer local (para envio quando a rede voltar)
  List<DriverLocation> get pendingCoordinates;

  /// Limpa o buffer de coordenadas pendentes após envio bem-sucedido
  void clearPendingCoordinates();

  void addLocation(DriverLocation location) {
    if (!_controller.isClosed) {
      _controller.add(location);
    }
  }
}

