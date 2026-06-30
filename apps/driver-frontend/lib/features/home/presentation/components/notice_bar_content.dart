import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';

class NoticeBarContent extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? trailingText;
  /// Quando [true], o pill do trailing fica vermelho — usado para "Atrasado".
  final bool isLate;

  const NoticeBarContent({
    super.key,
    required this.icon,
    required this.text,
    this.trailingText,
    this.isLate = false,
  });

  @override
  Widget build(BuildContext context) {
    final pillBg = isLate
        ? const Color(0xFFD32F2F)   // Vermelho "Atrasado" (estilo 99)
        : ColorPalette.neutralVariant99;
    final pillTextColor = isLate ? Colors.white : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          Icon(icon, color: isLate ? const Color(0xFFD32F2F) : ColorPalette.neutral70),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: context.labelMedium?.copyWith(
                color: ColorPalette.neutral99,
              ),
            ),
          ),
          if (trailingText != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: pillBg,
              ),
              child: Text(
                trailingText!,
                style: context.labelSmall?.copyWith(color: pillTextColor),
              ),
            ),
        ],
      ),
    );
  }
}
