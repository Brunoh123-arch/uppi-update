import 'package:flutter/cupertino.dart';
import 'package:flutter_common/config/constants.dart';
import 'package:flutter_common/core/enums/measurement_system.dart';
import 'package:flutter_common/core/extensions/extensions.dart';
import 'package:latlong2/latlong.dart';

extension LatLngDistanceX on LatLng {
  static final Map<String, String> _distanceCache = {};

  String distanceTo(LatLng other, BuildContext context) {
    final cacheKey = '${latitude},${longitude}_${other.latitude},${other.longitude}_${Localizations.localeOf(context).languageCode}';
    if (_distanceCache.containsKey(cacheKey)) {
      return _distanceCache[cacheKey]!;
    }
    final Distance distance = Distance();
    String formattedDistance;
    if (Constants.defaultMeasurementSystem == MeasurementSystem.metric) {
      final distanceInMeters = distance.as(LengthUnit.Meter, this, other);
      if (distanceInMeters < 1000) {
        formattedDistance = context.t.distanceInMeters(distanceInMeters);
      } else {
        formattedDistance = context.t.distanceInKilometers(distanceInMeters / 1000);
      }
    } else {
      final distanceInMiles = distance.as(LengthUnit.Mile, this, other);
      formattedDistance = context.t.distanceInMiles(distanceInMiles);
    }
    _distanceCache[cacheKey] = formattedDistance;
    return formattedDistance;
  }
}

extension IntDistanceX on int {
  String toFormattedDistance(BuildContext context) {
    if (Constants.defaultMeasurementSystem == MeasurementSystem.metric) {
      if (this < 1000) {
        return context.t.distanceInMeters(this);
      } else {
        return context.t.distanceInKilometers(this / 1000);
      }
    } else {
      if (this < 1609) {
        return context.t.distanceInFeets(this);
      } else {
        return context.t.distanceInMiles(this / 1609);
      }
    }
  }
}
