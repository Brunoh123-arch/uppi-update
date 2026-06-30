import 'package:flutter_common/config/constants.dart';
import 'package:generic_map/generic_map.dart';
export 'package:generic_map/interfaces/map_provider_enum.dart';

extension MapProviderEnumExtension on MapProviderEnum {
  MapProvider get providerObject {
    switch (this) {
      case (MapProviderEnum.googleMaps):
        return GoogleMapProvider();

      case (MapProviderEnum.openStreetMaps):
        return OpenStreetMapProvider();

      case (MapProviderEnum.mapBox):
        return Constants.mapBoxProvider;
    }
  }
}
