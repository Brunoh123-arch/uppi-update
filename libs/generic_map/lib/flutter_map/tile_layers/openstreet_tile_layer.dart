import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:generic_map/flutter_map/widget.dart';

TileLayer openStreetTileLayer({required bool useCachedTiles}) => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentTemplate: 'online.uppi.rider/3.3.0',
  maxNativeZoom: 19,
  maxZoom: 20,
  keepBuffer: 2,
  panBuffer: 1,
  tileDisplay: const TileDisplay.instantaneous(),
  tileProvider: useCachedTiles
      ? const FMTCStore('mapStore').getTileProvider()
      : CancellableNetworkTileProvider(silenceExceptions: true),
  tileUpdateTransformer: animatedMoveTileUpdateTransformer,
);

final animatedMoveTileUpdateTransformer = TileUpdateTransformer.fromHandlers(
  handleData: (updateEvent, sink) {
    final id = AnimationId.fromMapEvent(updateEvent.mapEvent);

    if (id == null) return sink.add(updateEvent);
    if (id.customId != FlutterMapViewState.useTransformerId) {
      if (id.moveId == AnimatedMoveId.started) {
        //debugPrint('TileUpdateTransformer disabled, using default behaviour.');
      }
      return sink.add(updateEvent);
    }

    switch (id.moveId) {
      case AnimatedMoveId.started:
        sink.add(
          updateEvent.loadOnly(
            loadCenterOverride: id.destLocation,
            loadZoomOverride: id.destZoom,
          ),
        );
        break;
      case AnimatedMoveId.inProgress:
        // Do not prune or load during movement.
        break;
      case AnimatedMoveId.finished:
        sink.add(updateEvent.pruneOnly());
        break;
    }
  },
);
