import 'package:flutter/material.dart';
import 'package:generic_map/generic_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_common/core/presentation/markers/app_marker.dart';

class AppMarkerAddressNull extends StatelessWidget {
  final VoidCallback? onTap;

  const AppMarkerAddressNull({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppMarker(
      onTap: onTap,
      title: Text(
        "Click to set location",   // texto padrão enquanto sem endereço
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF096EFF), // primary50 — azul
        ),
      ),
    );
  }

  CustomMarker genericMarker(LatLng position) => CustomMarker(
        position: position, width: AppMarker.width,
        height: AppMarker.height, alignment: AppMarker.alignment, widget: this,
        onTap: onTap,
      );
}
