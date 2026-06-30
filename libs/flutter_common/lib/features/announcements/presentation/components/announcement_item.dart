import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';

class SharedAnnouncementItem extends StatelessWidget {
  final String title;
  final String description;
  final String? url;
  final VoidCallback? onPressed;

  const SharedAnnouncementItem({
    super.key,
    required this.title,
    required this.description,
    this.url,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      minimumSize: const Size(0, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: ShapeDecoration(
          color: ColorPalette.neutralVariant99,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: ColorPalette.primary95),
            borderRadius: BorderRadius.circular(12),
          ),
          shadows: const [
            BoxShadow(
              color: Color(0x1464748B),
              blurRadius: 8,
              offset: Offset(2, 4),
            )
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: ColorPalette.primary95,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Ionicons.notifications,
                    color: ColorPalette.primary30,
                  ),
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelLarge,
                  ),
                )
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
