import 'package:flutter/material.dart';
import 'package:generic_map/generic_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_common/core/presentation/markers/app_marker.dart';

class AppMarkerPickup extends StatelessWidget {
  final String address;
  final VoidCallback? onTap;

  const AppMarkerPickup({super.key, required this.address, this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppMarker(
      icon: MarkerIcon.locate,        // ícone de localização atual
      onTap: onTap,
      // color padrão = MarkerColor.blue (azul)
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Pick-up point",           // título do balão de partida
            style: Theme.of(context).textTheme.labelMedium,
          ),
          Text(
            address,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // Cria um CustomMarker posicionado no mapa
  CustomMarker genericMarker(LatLng position) => CustomMarker(
        id: 'pickup_$address',
        position: position,
        width: AppMarker.width,
        height: AppMarker.height,
        alignment: AppMarker.alignment,
        widget: this,
        onTap: onTap,
      );

  // Cria um CenterMarker (marcador central — arrastável)
  CenterMarker get centerMarker => CenterMarker(
        widget: this,
        size: const Size(AppMarker.width, AppMarker.height),
        alignment: AppMarker.alignment,
      );
}
