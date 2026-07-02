import 'package:flutter/material.dart';
import 'package:generic_map/generic_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_common/core/presentation/markers/app_marker.dart';

class AppMarkerStop extends StatelessWidget {
  final String address;
  final int stopIndex; // número da parada (1, 2, 3...)
  final VoidCallback? onTap;

  const AppMarkerStop({
    super.key,
    required this.address,
    required this.stopIndex,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppMarker(
      color: MarkerColor.green,
      icon: MarkerIcon.location,
      onTap: onTap,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Stop $stopIndex",
            style: Theme.of(context).textTheme.labelMedium,
          ),
          Text(
            address,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  CustomMarker genericMarker(LatLng position) => CustomMarker(
        position: position,
        width: AppMarker.width,
        height: AppMarker.height,
        alignment: AppMarker.alignment,
        widget: this,
        onTap: onTap,
      );

  CenterMarker get centerMarker => CenterMarker(
        widget: this,
        size: const Size(AppMarker.width, AppMarker.height),
        alignment: AppMarker.alignment,
      );
}
