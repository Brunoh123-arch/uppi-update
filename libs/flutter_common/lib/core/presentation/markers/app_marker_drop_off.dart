import 'package:flutter/material.dart';
import 'package:generic_map/generic_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_common/core/presentation/markers/app_marker.dart';

class AppMarkerDropoff extends StatelessWidget {
  final String address;
  final VoidCallback? onTap;

  const AppMarkerDropoff({super.key, required this.address, this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppMarker(
      color: MarkerColor.green,       // ← verde/ciano
      icon: MarkerIcon.location,     // ícone de pin de localização
      onTap: onTap,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Destination",            // título do balão de destino
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
        id: 'dropoff_$address',
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
