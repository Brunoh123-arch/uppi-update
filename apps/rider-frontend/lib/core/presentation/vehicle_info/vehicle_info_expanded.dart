import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';

import 'vehicle_plate_view.dart';

class VehicleInfoExpanded extends StatelessWidget {
  final String imageUrl;
  final String? serviceName;
  final String? vehicleModel;
  final String? vehicleColor;
  final String? vehiclePlateNumber;
  final bool extraLarge;

  const VehicleInfoExpanded({
    super.key,
    required this.imageUrl,
    this.serviceName,
    this.vehicleModel,
    this.vehicleColor,
    this.vehiclePlateNumber,
    required this.extraLarge,
  });

  String _getLocalImageForService(String? name) {
    if (name == null) return 'assets/images/white_car.png';
    final lowerName = name.toLowerCase();
    if (lowerName.contains('taxi') && lowerName.contains('moto')) {
      return 'assets/images/yellow_moto.png';
    } else if (lowerName.contains('taxi')) {
      return 'assets/images/yellow_taxi.png';
    } else if (lowerName.contains('moto')) {
      return 'assets/images/white_moto.png';
    } else {
      // Default (Regular, Uppi X, Uppi, etc.)
      return 'assets/images/white_car.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallbackAsset = _getLocalImageForService(serviceName);
    return Column(
      children: [
        Builder(builder: (context) {
          final hasCustomImage = imageUrl.isNotEmpty &&
              (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) &&
              !imageUrl.contains('flaticon.com') &&
              !imageUrl.contains('3097180.png');
          if (hasCustomImage) {
            return CachedNetworkImage(
              imageUrl: imageUrl,
              width: extraLarge ? 190 : 120,
              height: extraLarge ? 190 : 120,
              fit: BoxFit.contain,
              placeholder: (context, url) => const SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (context, url, error) => Image.asset(
                fallbackAsset,
                width: extraLarge ? 190 : 120,
                height: extraLarge ? 190 : 120,
                fit: BoxFit.contain,
              ),
            );
          }
          return Image.asset(
            fallbackAsset,
            width: extraLarge ? 190 : 120,
            height: extraLarge ? 190 : 120,
            fit: BoxFit.contain,
          );
        }),
        Text(
          [vehicleModel, vehicleColor].nonNulls.join(' - '),
          style: context.titleSmall,
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (vehiclePlateNumber != null) ...[
              VehiclePlateView(carPlate: vehiclePlateNumber!),
              const SizedBox(
                width: 4,
              )
            ],
          ],
        )
      ],
    );
  }
}
