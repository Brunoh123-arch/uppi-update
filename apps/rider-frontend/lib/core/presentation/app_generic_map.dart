import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:generic_map/generic_map.dart';
import 'package:flutter_common/core/presentation/app_generic_map.dart' as common;
import 'package:flutter_common/core/blocs/settings.dart';

class AppGenericMap extends StatelessWidget {
  final MapProviderEnum? mapProvider;
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
  final bool isDarkMode;
  final bool forceLightMode;

  const AppGenericMap({
    super.key,
    this.mapProvider,
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
    this.isDarkMode = false,
    this.forceLightMode = false,
  });

  @override
  Widget build(BuildContext context) {
    if (mapProvider != null) {
      return common.AppGenericMap(
        mapProvider: mapProvider!,
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
        isDarkMode: isDarkMode,
        forceLightMode: forceLightMode,
      );
    }
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
          isDarkMode: isDarkMode,
          forceLightMode: forceLightMode,
        );
      },
    );
  }
}
