import 'package:flutter/material.dart';
import 'package:flutter_common/core/enums/map_provider_enum.prod.dart';
import 'package:generic_map/generic_map.dart';

class AppGenericMap extends StatelessWidget {
  final MapProviderEnum mapProvider;
  final MapViewMode mode;
  final CenterMarker Function(
    BuildContext context,
    GlobalKey key,
    String? address,
  )? centerMarkerBuilder;
  final AddressResolver? addressResolver;
  final bool interactive;
  final Function(MapViewController)? onControllerReady;
  final Function(Place?)? onMapMoved;
  final Place initialLocation;
  final List<PolyLineLayer> polylines;
  final List<CustomMarker> markers;
  final List<CircleMarker> circleMarkers;
  final EdgeInsets padding;
  final bool myLocationEnabled;
  final bool animateMarkers;
  final bool isDarkMode;
  final bool forceLightMode;

  const AppGenericMap({
    super.key,
    required this.mapProvider,
    required this.initialLocation,
    this.mode = MapViewMode.static,
    this.onControllerReady,
    this.polylines = const [],
    this.onMapMoved,
    this.interactive = false,
    this.padding = EdgeInsets.zero,
    this.markers = const <CustomMarker>[],
    this.centerMarkerBuilder,
    this.addressResolver,
    this.circleMarkers = const [],
    this.myLocationEnabled = true,
    this.animateMarkers = true,
    this.isDarkMode = false,
    this.forceLightMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return GenericMap(
      provider: mapProvider.providerObject,
      mode: mode,
      centerMarkerBuilder: centerMarkerBuilder,
      addressResolver: addressResolver,
      interactive: interactive,
      onControllerReady: onControllerReady,
      onMapMoved: onMapMoved,
      initialLocation: initialLocation,
      polylines: polylines,
      markers: markers,
      circleMarkers: circleMarkers,
      padding: padding,
      myLocationEnabled: myLocationEnabled,
      animateMarkers: animateMarkers,
      isDarkMode: isDarkMode,
      forceLightMode: forceLightMode,
    );
  }
}
