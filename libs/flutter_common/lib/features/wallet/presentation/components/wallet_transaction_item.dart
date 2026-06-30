import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';

class SharedWalletTransactionItem extends StatelessWidget {
  final IconData icon;
  final bool isDeduct;
  final String title;
  final String formattedDatetime;
  final String formattedPrice;

  const SharedWalletTransactionItem({
    super.key,
    required this.icon,
    required this.isDeduct,
    required this.title,
    required this.formattedDatetime,
    required this.formattedPrice,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ColorPalette.primary95),
        color: ColorPalette.neutral99,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: ColorPalette.neutralVariant99,
              border: Border.all(
                color: ColorPalette.neutral90,
              ),
            ),
            child: Icon(
              icon,
              color: isDeduct ? ColorPalette.tertiary60 : ColorPalette.primary30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  formattedDatetime,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formattedPrice,
            style: theme.textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}
