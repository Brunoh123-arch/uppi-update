import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'openstreet_tile_layer.dart';

TileLayer mapBoxTileLayer({
  required String accessToken,
  required String tileSetId,
  required String userId,
  required bool useCachedTiles,
}) {
  return TileLayer(
    urlTemplate:
        "https://api.mapbox.com/styles/v1/$userId/$tileSetId/tiles/256/{z}/{x}/{y}@2x?access_token=$accessToken",
    additionalOptions: {"access_token": accessToken},
    maxNativeZoom: 18,
    maxZoom: 20,
    tileProvider: useCachedTiles
        ? const FMTCStore('mapStore').getTileProvider()
        : CancellableNetworkTileProvider(silenceExceptions: true),
    tileUpdateTransformer: animatedMoveTileUpdateTransformer,
  );
}
