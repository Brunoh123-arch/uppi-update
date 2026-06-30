import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:injectable/injectable.dart';
import 'package:uppi_motorista/core/enums/location_permission.dart';
import 'package:uppi_motorista/core/utils/driver_speed.dart';
import 'package:flutter_common/core/entities/driver_location.dart';
import 'location_datasource.dart';
import 'package:flutter_common/core/presentation/uppi_feedback.dart';

@prod
@LazySingleton(as: LocationDatasource)
class LocationDatasourceImpl extends LocationDatasource {
  StreamSubscription<geo.Position>? _positionSubscription;
  Timer? _webLocationTimer;
  geo.Position? _lastPosition;
  DateTime? _lastPositionTime;
  bool _inRide = false;

  /// Buffer local de coordenadas GPS para envio em batch quando a rede voltar
  final List<DriverLocation> _coordinateBuffer = [];

  /// Limite do buffer: a 2 Hz, 600 entradas ≈ 5 minutos de trajeto. Sem o
  /// limite o buffer cresceria sem parar durante todo o turno do motorista.
  static const int _maxBufferedCoordinates = 600;

  void _bufferLocation(DriverLocation loc) {
    _coordinateBuffer.add(loc);
    if (_coordinateBuffer.length > _maxBufferedCoordinates) {
      _coordinateBuffer.removeRange(
        0,
        _coordinateBuffer.length - _maxBufferedCoordinates,
      );
    }
  }

  @override
  List<DriverLocation> get pendingCoordinates => List.unmodifiable(_coordinateBuffer);

  @override
  void clearPendingCoordinates() => _coordinateBuffer.clear();

  LocationPermission _mapPermission(geo.LocationPermission p) {
    switch (p) {
      case geo.LocationPermission.denied:
        return LocationPermission.denied;
      case geo.LocationPermission.deniedForever:
        return LocationPermission.deniedForever;
      case geo.LocationPermission.whileInUse:
        return LocationPermission.whileInUse;
      case geo.LocationPermission.always:
        return LocationPermission.always;
      case geo.LocationPermission.unableToDetermine:
        return LocationPermission.denied;
    }
  }

  @override
  Future<LocationPermission> getLocationPermissionStatus() async {
    final permission = await geo.Geolocator.checkPermission();
    return _mapPermission(permission);
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    return geo.Geolocator.isLocationServiceEnabled();
  }

  @override
  Future<LocationPermission> requestLocationPermission() async {
    final permission = await geo.Geolocator.requestPermission();
    return _mapPermission(permission);
  }

  @override
  Future<bool> requestLocationService() async {
    if (await geo.Geolocator.isLocationServiceEnabled()) return true;
    // Abre a tela de configurações de localização do sistema para o motorista
    // ligar o GPS — antes só relíamos o estado e o botão Online falhava mudo.
    try {
      await geo.Geolocator.openLocationSettings();
    } catch (_) {}
    return geo.Geolocator.isLocationServiceEnabled();
  }

  @override
  Future<bool> openAppSettings() async {
    return geo.Geolocator.openAppSettings();
  }

  @override
  Future<DriverLocation?> getCurrentLocation() async {
    debugPrint('[GPS-DRV] getCurrentLocation chamado. kIsWeb = $kIsWeb');
    if (kIsWeb) {
      final loc = DriverLocation(
        lat: -1.2950,
        lng: -47.9250,
        rotation: 0,
      );
      debugPrint('[GPS-DRV] kIsWeb = true, retornando Castanhal: $loc');
      addLocation(loc);
      return loc;
    }
    try {
      final pos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      // 🛡️ ANTI-MOCK GPS: Rejeitar posições simuladas (Fake GPS / Mock Location) apenas em modo Release
      if (pos.isMocked && kReleaseMode) {
        debugPrint('[GPS-GUARD] ⚠️ Posição simulada detectada em getCurrentLocation! Ignorando em Release.');
        return null;
      }
      final loc = DriverLocation(
        lat: pos.latitude,
        lng: pos.longitude,
        rotation: pos.heading.toInt(),
      );
      DriverSpeed.updateFromMps(pos.speed);
      addLocation(loc);
      return loc;
    } catch (_) {
      try {
        final pos = await geo.Geolocator.getLastKnownPosition();
        if (pos != null) {
          final loc = DriverLocation(
            lat: pos.latitude,
            lng: pos.longitude,
            rotation: pos.heading.toInt(),
          );
          addLocation(loc);
          return loc;
        }
      } catch (_) {}
    }
    return null;
  }

  @override
  void updateLocationSettings({required bool inRide}) {
    if (_inRide == inRide) return;
    _inRide = inRide;
    debugPrint('[GPS-DRV] updateLocationSettings: inRide = $inRide. Reiniciando stream se ativo.');
    if (_positionSubscription != null) {
      _positionSubscription?.cancel();
      _positionSubscription = null;
      _startAndroidIosUpdates();
    }
  }

  @override
  void updateBatterySaverMode(bool enabled) {
    if (UppiPerformance.batterySaverMode == enabled && _positionSubscription != null) {
      return;
    }
    UppiPerformance.batterySaverMode = enabled;
    debugPrint('[GPS-DRV] updateBatterySaverMode: mudou para $enabled. Reiniciando stream se ativo.');
    if (_positionSubscription != null) {
      _positionSubscription?.cancel();
      _positionSubscription = null;
      _startAndroidIosUpdates();
    }
  }

  @override
  Future<void> startGettingLocationUpdates() async {
    debugPrint('[GPS-DRV] startGettingLocationUpdates chamado. kIsWeb = $kIsWeb');
    if (_positionSubscription != null || _webLocationTimer != null) {
      debugPrint('[GPS-DRV] startGettingLocationUpdates já rodando.');
      return;
    }

    if (kIsWeb) {
      debugPrint('[GPS-DRV] kIsWeb = true, iniciando timer periódico de 1s para Castanhal');
      _webLocationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final loc = DriverLocation(
          lat: -1.2950,
          lng: -47.9250,
          rotation: 0,
        );
        debugPrint('[GPS-DRV] Timer disparado, adicionando Castanhal: $loc');
        _bufferLocation(loc);
        addLocation(loc);
      });
      return;
    }

    _startAndroidIosUpdates();
  }

  void _startAndroidIosUpdates() {
    // Configuração de GPS adaptativa para economizar bateria quando parado/online
    final isBatterySaver = UppiPerformance.batterySaverMode;
    final geo.LocationSettings locationSettings;
    
    // Reset do histórico ao iniciar atualizações
    _lastPosition = null;
    _lastPositionTime = null;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = geo.AndroidSettings(
        accuracy: isBatterySaver
            ? (_inRide ? geo.LocationAccuracy.high : geo.LocationAccuracy.medium)
            : (_inRide ? geo.LocationAccuracy.bestForNavigation : geo.LocationAccuracy.high),
        distanceFilter: isBatterySaver
            ? (_inRide ? 20 : 30)
            : (_inRide ? 0 : 10),
        intervalDuration: Duration(
          milliseconds: isBatterySaver
              ? (_inRide ? 6000 : 12000)
              : (_inRide ? 500 : 4000),
        ),
        foregroundNotificationConfig: geo.ForegroundNotificationConfig(
          notificationText: 'Uppi está rastreando sua localização para corridas.',
          notificationTitle: 'Uppi — Motorista Online',
          enableWakeLock: _inRide && !isBatterySaver,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
               defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = geo.AppleSettings(
        accuracy: isBatterySaver
            ? (_inRide ? geo.LocationAccuracy.high : geo.LocationAccuracy.medium)
            : (_inRide ? geo.LocationAccuracy.bestForNavigation : geo.LocationAccuracy.high),
        distanceFilter: isBatterySaver
            ? (_inRide ? 20 : 30)
            : (_inRide ? 0 : 10),
        activityType: _inRide ? geo.ActivityType.automotiveNavigation : geo.ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = geo.LocationSettings(
        accuracy: isBatterySaver
            ? (_inRide ? geo.LocationAccuracy.high : geo.LocationAccuracy.medium)
            : (_inRide ? geo.LocationAccuracy.bestForNavigation : geo.LocationAccuracy.high),
        distanceFilter: isBatterySaver
            ? (_inRide ? 20 : 30)
            : (_inRide ? 0 : 10),
      );
    }

    _positionSubscription = geo.Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((geo.Position pos) {
      // 🛡️ ANTI-MOCK GPS: Rejeitar posições simuladas (Fake GPS / Mock Location) apenas em modo Release
      if (pos.isMocked && kReleaseMode) {
        debugPrint('[GPS-GUARD] ⚠️ Posição simulada detectada no stream! Ignorando coordenada em Release.');
        return;
      }

      double speedMps = pos.speed;

      // Prioriza a velocidade Doppler nativa do sensor. Calcula pelo delta geodésico
      // apenas se o hardware retornar velocidade inválida/negativa.
      if (speedMps < 0.0 && _lastPosition != null && _lastPositionTime != null) {
        final now = DateTime.now();
        final timeDiffSec = now.difference(_lastPositionTime!).inMilliseconds / 1000.0;
        if (timeDiffSec > 0.3) {
          final distance = geo.Geolocator.distanceBetween(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            pos.latitude,
            pos.longitude,
          );
          final calcSpeed = distance / timeDiffSec;
          if (calcSpeed >= 0.0 && calcSpeed < 50.0) {
            speedMps = calcSpeed;
          }
        }
      }
      if (speedMps < 0.0) speedMps = 0.0;

      _lastPosition = pos;
      _lastPositionTime = DateTime.now();

      final loc = DriverLocation(
        lat: pos.latitude,
        lng: pos.longitude,
        rotation: pos.heading.toInt(),
      );
      DriverSpeed.updateFromMps(speedMps);
      _bufferLocation(loc); // 🔒 Capa o tamanho do buffer local em 600 itens
      addLocation(loc);
    });
  }

  @override
  void stopGettingLocationUpdates() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _webLocationTimer?.cancel();
    _webLocationTimer = null;
    _coordinateBuffer.clear();
  }
}