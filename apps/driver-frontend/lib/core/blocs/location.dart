import 'dart:async';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:uppi_motorista/core/datasources/location_update_datasource.dart';
import 'package:flutter_common/core/entities/driver_location.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:uppi_motorista/core/datasources/location_datasource.dart';

part 'location.event.dart';
part 'location.state.dart';
part 'location.freezed.dart';
part 'location.g.dart';

@LazySingleton()
class LocationBloc extends HydratedBloc<LocationEvent, LocationState> {
  final LocationDatasource locationDatasource;
  final LocationUpdateDatasource locationUpdateDatasource;
  DateTime? _lastUploadTime;
  DriverLocation? _lastUploadedLocation;

  LocationBloc(this.locationDatasource, this.locationUpdateDatasource)
    : super(const LocationState.loading()) {
    on<LocationEvent>((event, emit) async {
      await event.map(
        fetchCurrentLocation: (fetchCurrentLocation) async {
          final location = await locationDatasource.getCurrentLocation();
          if (location != null) {
            emit(LocationState.determined(location: location));
          }
        },
        startGettingLocationUpdates: (_) async {
          locationDatasource.getCurrentLocation();
          locationDatasource.startGettingLocationUpdates();
          await emit.forEach(
            locationDatasource.driverLocation,
              onData: (onData) {
                // Filtro inteligente: só envia ao servidor se 4s passaram, 5m de deslocamento ou 15° de rotação
                final now = DateTime.now();
                bool shouldUpload = false;
                if (_lastUploadTime == null || _lastUploadedLocation == null) {
                  shouldUpload = true;
                } else {
                  final timeDiff = now.difference(_lastUploadTime!).inSeconds;
                  final dist = geo.Geolocator.distanceBetween(
                    _lastUploadedLocation!.lat,
                    _lastUploadedLocation!.lng,
                    onData.lat,
                    onData.lng,
                  );
                  final rot1 = onData.rotation ?? 0;
                  final rot2 = _lastUploadedLocation!.rotation ?? 0;
                  final rotDiff = (rot1 - rot2).abs();
                  shouldUpload = timeDiff >= 4 || dist >= 5 || rotDiff >= 15;
                }
                if (shouldUpload) {
                  _lastUploadTime = now;
                  _lastUploadedLocation = onData;
                  unawaited(Future(() => locationUpdateDatasource.updateDriverLocation(location: onData)));
                }
                return LocationState.determined(location: onData);
            },
          );
        },
        stopGettingLocationUpdates: (_) async {
          locationDatasource.stopGettingLocationUpdates();
        },
        uploadDriverLocation: (_UpdateDriverLocation value) {
          unawaited(locationUpdateDatasource.updateDriverLocation(
            location: value.location,
          ));
        },
      );
    });
  }

  @override
  LocationState? fromJson(Map<String, dynamic> json) => null;

  @override
  Map<String, dynamic>? toJson(LocationState state) => null;

  void fetchCurrentLocation() =>
      add(const LocationEvent.fetchCurrentLocation());

  void startGettingLocationUpdates() =>
      add(const LocationEvent.startGettingLocationUpdates());

  void stopGettingLocationUpdates() =>
      add(const LocationEvent.stopGettingLocationUpdates());
}
