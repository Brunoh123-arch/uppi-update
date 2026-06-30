import 'package:flutter/cupertino.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:rider_flutter/core/entities/favorite_location.dart';
import 'package:rider_flutter/core/enums/address_type.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';

class AppFavoriteLocationItem extends StatelessWidget {
  final AddressType type;
  final FavoriteLocationEntity? address;
  final VoidCallback? onPressed;
  final bool showArrow;

  const AppFavoriteLocationItem({
    super.key,
    required this.address,
    this.onPressed,
    required this.type,
    this.showArrow = false,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      onPressed: onPressed,
      padding: const EdgeInsets.all(0),
      minimumSize: Size(0, 0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              border: Border.all(color: ColorPalette.neutral90),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              address?.type.icon ?? type.icon,
              size: 22,
              color: ColorPalette.primary30,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  address?.type.title(context) ?? type.title(context),
                  style: context.labelLarge?.copyWith(
                    color: ColorPalette.neutral10,
                  ),
                ),
                if (address != null) ...[
                  Text(
                    address!.place.address,
                    style: context.bodyMedium?.copyWith(
                      color: ColorPalette.neutralVariant50,
                    ),
                  ),
                ],
                if (address == null) ...[
                  Text(
                    Localizations.localeOf(context).languageCode == 'pt'
                        ? "Definir local para ${type.title(context)}"
                        : "Set location for ${type.title(context)}",
                    style: context.bodyMedium?.copyWith(
                      color: ColorPalette.primary50,
                    ),
                  ),
                ]
              ],
            ),
          ),
          if (showArrow)
            const Icon(
              Ionicons.chevron_forward,
              size: 20,
              color: ColorPalette.neutral70,
            ),
        ],
      ),
    );
  }
}
