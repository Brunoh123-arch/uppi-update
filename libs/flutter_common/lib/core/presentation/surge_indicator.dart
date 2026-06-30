import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';

/// Widget que exibe o indicador de preço dinâmico (Surge Pricing)
/// Mostra o multiplicador como badge pulsante quando > 1.0x
/// Segue o design system do Uppi (ColorPalette)
class SurgeIndicator extends StatefulWidget {
  final double multiplier;

  const SurgeIndicator({super.key, required this.multiplier});

  @override
  State<SurgeIndicator> createState() => _SurgeIndicatorState();
}

class _SurgeIndicatorState extends State<SurgeIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.multiplier <= 1.0) return const SizedBox.shrink();

    // Cores usando o design system do Uppi
    final Color bgColor;
    final Color textColor;
    final IconData icon;

    if (widget.multiplier < 1.5) {
      bgColor = ColorPalette.secondary95; // Laranja claro Uppi
      textColor = ColorPalette.secondary40;
      icon = Icons.bolt;
    } else if (widget.multiplier < 2.0) {
      bgColor = ColorPalette.error95; // Vermelho claro Uppi
      textColor = ColorPalette.error40;
      icon = Icons.local_fire_department;
    } else {
      bgColor = ColorPalette.error30; // Vermelho intenso Uppi
      textColor = ColorPalette.neutral100;
      icon = Icons.whatshot;
    }

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: textColor.withValues(alpha: 0.3),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 4),
            Text(
              '${widget.multiplier.toStringAsFixed(1)}x',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget compacto de surge para lista de serviços
class SurgeBadge extends StatelessWidget {
  final double multiplier;

  const SurgeBadge({super.key, required this.multiplier});

  @override
  Widget build(BuildContext context) {
    if (multiplier <= 1.0) return const SizedBox.shrink();

    final textColor = multiplier < 1.5
        ? ColorPalette.secondary40
        : ColorPalette.error40;
    final bgColor = multiplier < 1.5
        ? ColorPalette.secondary95
        : ColorPalette.error95;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, size: 12, color: textColor),
          const SizedBox(width: 2),
          Text(
            '${multiplier.toStringAsFixed(1)}x',
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner informativo de surge no topo da seleção de serviços
class SurgeBanner extends StatelessWidget {
  final double multiplier;

  const SurgeBanner({super.key, required this.multiplier});

  @override
  Widget build(BuildContext context) {
    if (multiplier <= 1.0) return const SizedBox.shrink();

    final isHigh = multiplier >= 1.5;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isHigh ? ColorPalette.error95 : ColorPalette.secondary95,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHigh ? ColorPalette.error80 : ColorPalette.secondary80,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.trending_up,
            size: 20,
            color: isHigh ? ColorPalette.error40 : ColorPalette.secondary40,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              multiplier < 1.5
                  ? 'Demanda levemente alta na sua região'
                  : multiplier < 2.0
                  ? 'Alta demanda • Preços com ajuste temporário'
                  : 'Demanda muito alta • Preços majorados',
              style: TextStyle(
                color: isHigh ? ColorPalette.error40 : ColorPalette.secondary40,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SurgeBadge(multiplier: multiplier),
        ],
      ),
    );
  }
}
