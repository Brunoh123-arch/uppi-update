import 'package:flutter/foundation.dart';
import 'package:flutter_common/features/lgpd/data/lgpd_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:injectable/injectable.dart';
import 'package:latlong2/latlong.dart';

import 'location_datasource.dart';

@prod
@LazySingleton(as: LocationDatasource)
class LocationDatasourceImpl implements LocationDatasource {
  @override
  Future<LatLng> getCurrentLocation() async {
    // 🛡️ LGPD Compliance check
    if (!LgpdPreferences.locationConsent) {
      throw Exception('LGPD_CONSENT_DENIED');
    }

    Position? pos;

    // 1. Tenta obter a última posição conhecida (instantâneo e muito estável)
    if (!kIsWeb) {
      try {
        pos = await Geolocator.getLastKnownPosition();
      } catch (_) {}
    }

    // 2. Se não houver posição no cache, solicita uma nova com precisão equilibrada (usa antenas e wifi)
    if (pos == null) {
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 20),
          ),
        );
      } catch (e) {
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('denied') || errorStr.contains('permission')) {
          debugPrint('[GPS-RDR] Permissão de GPS negada na primeira tentativa: $e');
          rethrow;
        }
        debugPrint('[GPS-RDR] Primeira busca de GPS falhou ou deu timeout: $e. Tentando precisão menor...');
        // 3. Se falhar por timeout/erro, tenta precisão menor (lowest) como última alternativa
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.lowest,
              timeLimit: Duration(seconds: 10),
            ),
          );
        } catch (e2) {
          debugPrint('[GPS-RDR] Segunda busca de GPS falhou: $e2');
        }
      }
    }

    if (pos == null) {
      throw Exception('Could not determine current location');
    }

    return LatLng(pos.latitude, pos.longitude);
  }

  @override
  Future<bool> isLocationPermissionGranted() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return false;
    }
    return true;
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    if (kIsWeb) return true;
    return Geolocator.isLocationServiceEnabled();
  }
}
