import 'package:flutter/material.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:generic_map/interfaces/map_provider_enum.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:latlong2/latlong.dart';
import 'package:rider_flutter/core/datasources/geo_datasource.dart';
import 'package:rider_flutter/core/datasources/location_datasource.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';

part 'location.state.dart';
part 'location.freezed.dart';
part 'location.g.dart';

@lazySingleton
class LocationCubit extends HydratedCubit<LocationState> {
  final LocationDatasource locationDatasource;
  final GeoDatasource geoDatasource;

  LocationCubit(this.locationDatasource, this.geoDatasource)
      : super(
          const LocationState.loading(),
        );

  void fetchCurrentLocation({
    required String language,
    required MapProviderEnum mapProvider,
  }) async {
    emit(const LocationState.loading());
    final serviceEnabled = await locationDatasource.isLocationServiceEnabled();
    if (serviceEnabled == false) {
      emit(const LocationState.error(error: LocationError.serviceDisabled));
      return;
    }
    bool permissionGranted = false;
    try {
      permissionGranted =
          await locationDatasource.isLocationPermissionGranted();
    } catch (error) {
      permissionGranted = false;
    }
    if (permissionGranted == false) {
      emit(const LocationState.error(error: LocationError.permissionDenied));
      return;
    }
    try {
      // 1. Obtém as coordenadas físicas do GPS de forma imediata (lat/lng)
      final currentPosition = await locationDatasource.getCurrentLocation();
      
      // 2. Emite imediatamente um estado determinado com coordenadas formatadas para exibir a bolinha azul e número na hora
      final tempPlace = PlaceEntity(
        coordinates: LatLngEntity(lat: currentPosition.latitude, lng: currentPosition.longitude),
        address: '${currentPosition.latitude.toStringAsFixed(6)}, ${currentPosition.longitude.toStringAsFixed(6)}',
      );
      emit(LocationState.determined(place: tempPlace));
      
      // 3. Resolve o endereço legível (Nominatim ou Google) em segundo plano (assíncrono)
      final addressResult = await geoDatasource.getAddressForLocation(
        latLng: currentPosition,
        language: language,
        mapProvider: mapProvider,
      );
      addressResult.fold(
        (l) {
          // Se falhar a geocodificação, mantemos o local temporário sem travar a bolinha
          debugPrint('[GPS-RDR] Erro na geocodificação reversa de inicialização: $l');
        },
        (r) {
          emit(LocationState.determined(place: r));
        },
      );
    } catch (e) {
      debugPrint('[GPS-RDR] Erro ao obter localização atual: $e');
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('denied') || errorStr.contains('permission')) {
        emit(const LocationState.error(error: LocationError.permissionDenied));
      } else {
        emit(const LocationState.error(error: LocationError.unknown));
      }
    }
  }

  @override
  LocationState? fromJson(Map<String, dynamic> json) {
    return LocationState.fromJson(json);
  }

  @override
  Map<String, dynamic>? toJson(LocationState state) {
    return state.toJson();
  }
}
