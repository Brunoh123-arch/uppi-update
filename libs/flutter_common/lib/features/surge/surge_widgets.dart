import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/extensions/extensions.dart';

/// Badge compacto de preço dinâmico — padrão Uppi
/// Usado em cards de corrida e botão de aceitar pedido
class SurgeBadge extends StatelessWidget {
  final double multiplier;

  const SurgeBadge({super.key, required this.multiplier});

  @override
  Widget build(BuildContext context) {
    if (multiplier <= 1.0) return const SizedBox.shrink();

    final (Color bg, Color fg) = _colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Ionicons.flash, size: 12, color: fg),
          const SizedBox(width: 3),
          Text(
            '${multiplier.toStringAsFixed(1)}x',
            style: context.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) get _colors {
    if (multiplier >= 2.0)
      return (ColorPalette.error40, ColorPalette.neutral100);
    if (multiplier >= 1.5)
      return (ColorPalette.secondary40, ColorPalette.neutral100);
    return (ColorPalette.secondary95, ColorPalette.secondary30);
  }
}

/// Indicador de surge pricing no mapa — badge flutuante
class SurgeIndicator extends StatelessWidget {
  final double multiplier;

  const SurgeIndicator({super.key, required this.multiplier});

  @override
  Widget build(BuildContext context) {
    if (multiplier <= 1.0) return const SizedBox.shrink();

    final (Color bg, Color fg) = _colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3F0E275D),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Ionicons.flash, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            'Demanda alta • ${multiplier.toStringAsFixed(1)}x',
            style: context.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) get _colors {
    if (multiplier >= 2.0)
      return (ColorPalette.error40, ColorPalette.neutral100);
    if (multiplier >= 1.5)
      return (ColorPalette.secondary40, ColorPalette.neutral100);
    return (ColorPalette.secondary90, ColorPalette.secondary20);
  }
}

/// Banner de surge pricing para o passageiro — padrão Uppi AppCardSheet
class SurgeBanner extends StatelessWidget {
  final double multiplier;

  const SurgeBanner({super.key, required this.multiplier});

  @override
  Widget build(BuildContext context) {
    if (multiplier <= 1.0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // Degradê sutil do secondary para o primary
        gradient: LinearGradient(
          colors: multiplier >= 1.5
              ? [ColorPalette.error95, ColorPalette.secondary95]
              : [ColorPalette.secondary99, ColorPalette.secondary95],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: multiplier >= 1.5
              ? ColorPalette.error80
              : ColorPalette.secondary90,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: multiplier >= 1.5
                  ? ColorPalette.error50
                  : ColorPalette.secondary40,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Ionicons.flash,
              color: ColorPalette.neutral100,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  multiplier >= 1.5
                      ? '⚡ Alta demanda na região'
                      : '⚡ Demanda elevada',
                  style: context.labelLarge?.copyWith(
                    color: multiplier >= 1.5
                        ? ColorPalette.error40
                        : ColorPalette.secondary30,
                  ),
                ),
                Text(
                  'Tarifa com multiplicador ${multiplier.toStringAsFixed(1)}x — valores normais em breve',
                  style: context.bodySmall?.copyWith(
                    color: multiplier >= 1.5
                        ? ColorPalette.error50
                        : ColorPalette.secondary40,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${multiplier.toStringAsFixed(1)}x',
            style: context.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: multiplier >= 1.5
                  ? ColorPalette.error40
                  : ColorPalette.secondary30,
            ),
          ),
        ],
      ),
    );
  }
}
