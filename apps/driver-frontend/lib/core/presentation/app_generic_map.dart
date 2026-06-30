import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:generic_map/generic_map.dart';
import 'package:flutter_common/core/blocs/settings.dart';
import 'package:flutter_common/core/presentation/app_generic_map.dart' as common;

class AppGenericMap extends StatelessWidget {
  final MapViewMode mode;
  final CenterMarker Function(
    BuildContext context,
    GlobalKey key,
    String? address,
  )?
  centerMarkerBuilder;
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

  const AppGenericMap({
    super.key,
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
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      buildWhen: (previous, current) =>
          previous.provider != current.provider ||
          previous.themeMode != current.themeMode,
      builder: (context, state) {
        final isDarkMode = state.themeMode == ThemeMode.dark ||
            (state.themeMode == ThemeMode.system &&
                MediaQuery.of(context).platformBrightness == Brightness.dark);
        return common.AppGenericMap(
          mapProvider: state.mapProviderEnum,
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
        );
      },
    );
  }
}
