import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';

import 'vehicle_plate_view.dart';

class VehicleInfoCompact extends StatelessWidget {
  final String? imageUrl;
  final String? serviceName;
  final String? vehicleModel;
  final String? vehicleColor;
  final String? vehiclePlateNumber;

  const VehicleInfoCompact({
    super.key,
    required this.imageUrl,
    this.serviceName,
    this.vehicleModel,
    this.vehicleColor,
    this.vehiclePlateNumber,
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
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [vehicleModel, vehicleColor].nonNulls.join(' - '),
                style: context.titleSmall,
              ),
              const SizedBox(height: 2),
              Row(
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
          ),
        ),
        Builder(builder: (context) {
          final hasCustomImage = imageUrl != null &&
              imageUrl!.isNotEmpty &&
              (imageUrl!.startsWith('http://') || imageUrl!.startsWith('https://')) &&
              !imageUrl!.contains('flaticon.com') &&
              !imageUrl!.contains('3097180.png');
          if (hasCustomImage) {
            return CachedNetworkImage(
              imageUrl: imageUrl!,
              width: 80,
              height: 80,
              fit: BoxFit.contain,
              placeholder: (context, url) => const SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (context, url, error) => Image.asset(
                fallbackAsset,
                width: 80,
                height: 80,
                fit: BoxFit.contain,
              ),
            );
          }
          return Image.asset(
            fallbackAsset,
            width: 80,
            height: 80,
            fit: BoxFit.contain,
          );
        }),
      ],
    );
  }
}
