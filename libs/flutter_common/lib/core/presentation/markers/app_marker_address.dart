import 'package:flutter/material.dart';
import 'package:generic_map/generic_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_common/core/presentation/markers/app_marker.dart';

class AppMarkerAddresss extends StatelessWidget {
  final String title;
  final String address;
  final VoidCallback? onTap;

  const AppMarkerAddresss({
    super.key,
    required this.title,
    required this.address,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppMarker(
      icon: MarkerIcon.location,
      onTap: onTap,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium,
              overflow: TextOverflow.ellipsis),
          Text(address,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
        ],
      ),
    );
  }

  CustomMarker genericMarker(LatLng position) => CustomMarker(
        position: position, width: AppMarker.width,
        height: AppMarker.height, alignment: AppMarker.alignment, widget: this,
        onTap: onTap,
      );

  CenterMarker get centerMarker => CenterMarker(
        widget: this, size: const Size(AppMarker.width, AppMarker.height),
        alignment: AppMarker.alignment,
      );
}
