import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';

class DriverAvatarSecondary extends StatelessWidget {
  final String? imageUrl;

  const DriverAvatarSecondary({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final placeholderIcon = Icon(
      Ionicons.person_circle,
      color: ColorPalette.primary30.withAlpha(102),
    );

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ColorPalette.neutral90),
      ),
      child: imageUrl == null
          ? Center(child: placeholderIcon)
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                placeholder: (context, url) => Center(child: placeholderIcon),
                errorWidget: (context, url, error) => Center(child: placeholderIcon),
              ),
            ),
    );
  }
}
