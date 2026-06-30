import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:generic_map/flutter_map/widget.dart';

TileLayer openStreetTileLayer({required bool useCachedTiles}) => TileLayer(
  urlTemplate: 'https://mt0.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
  maxNativeZoom: 20,
  maxZoom: 22,
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
