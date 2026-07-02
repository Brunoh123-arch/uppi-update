import 'package:flutter/material.dart';
import 'package:generic_map/generic_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_common/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/markers/app_marker.dart';

class AppMarkerDropoff extends StatelessWidget {
  final String address;
  final VoidCallback? onTap;

  const AppMarkerDropoff({super.key, required this.address, this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppMarker(
      color: MarkerColor.black,
      icon: MarkerIcon.location,
      onTap: onTap,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Destino",
            style: TextStyle(
              fontSize: 13.0,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          _buildAddressText(context, address),
        ],
      ),
    );
  }

  Widget _buildAddressText(BuildContext context, String addressText) {
    final match = RegExp(
      r'^(\d+(?:[.,]\d+)?\s*(?:km|min|m|h)(?:\s+\d+(?:[.,]\d+)?\s*(?:km|min|m|h))*)\s+(.*)$',
      caseSensitive: false,
    ).firstMatch(addressText);

    if (match != null) {
      final metrics = match.group(1) ?? '';
      final rest = match.group(2) ?? '';
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$metrics ',
              style: const TextStyle(
                fontSize: 14.0,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
            TextSpan(
              text: rest,
              style: TextStyle(
                fontSize: 13.0,
                fontWeight: FontWeight.w500,
                color: context.theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Text(
      addressText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13.0,
        fontWeight: FontWeight.w500,
        color: context.theme.colorScheme.onSurfaceVariant,
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
