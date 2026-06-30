import 'package:flutter/material.dart';

enum ShimmerVariant { shimmer, pulse }
enum ShimmerDirection { leftToRight, rightToLeft, topToBottom, bottomToTop }
enum ShimmerPreset { dark, light, neutral, custom }

/// Componente de Shimmer de nível supremo e altamente customizável em Flutter.
/// Suporta variantes (shimmer e pulse), 4 direções de animação e presets de cores de temas.
class ShimmerPlaceholder extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final ShimmerVariant variant;
  final ShimmerDirection direction;
  final ShimmerPreset preset;
  final int durationMs;
  final List<Color>? customColors;
  final Color? customBackgroundColor;

  const ShimmerPlaceholder({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
    this.variant = ShimmerVariant.shimmer,
    this.direction = ShimmerDirection.leftToRight,
    this.preset = ShimmerPreset.light,
    this.durationMs = 800,
    this.customColors,
    this.customBackgroundColor,
  });

  @override
  State<ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.durationMs),
    );

    if (widget.variant == ShimmerVariant.shimmer) {
      // Começa da esquerda/cima até a direita/baixo
      final beginValue = (widget.direction == ShimmerDirection.rightToLeft ||
              widget.direction == ShimmerDirection.bottomToTop)
          ? 2.0
          : -2.0;
      final endValue = (widget.direction == ShimmerDirection.rightToLeft ||
              widget.direction == ShimmerDirection.bottomToTop)
          ? -2.0
          : 2.0;

      _animation = Tween<double>(begin: beginValue, end: endValue).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
      );
      _controller.repeat();
    } else {
      // Efeito de "respiração" (pulse) suave de opacidade
      _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      );
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Definição das cores de presets compatíveis com a amostra React Native
    List<Color> colors;
    Color backgroundColor;

    switch (widget.preset) {
      case ShimmerPreset.dark:
        backgroundColor = const Color(0xFF141414);
        colors = [
          const Color(0xFF1C1C1C),
          const Color(0xFF2D2D2D),
          const Color(0xFF1C1C1C),
        ];
        break;
      case ShimmerPreset.light:
        backgroundColor = const Color(0xFFEEEEEE);
        colors = const [
          Color(0xFFE0E0E0),
          Color(0xFFF5F5F5),
          Color(0xFFE0E0E0),
        ];
        break;
      case ShimmerPreset.neutral:
        backgroundColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);
        colors = isDark
            ? [const Color(0xFF2C2C2C), const Color(0xFF3C3C3C), const Color(0xFF2C2C2C)]
            : [const Color(0xFFE5E5E5), const Color(0xFFF5F5F5), const Color(0xFFE5E5E5)];
        break;
      case ShimmerPreset.custom:
        backgroundColor = widget.customBackgroundColor ?? (isDark ? Colors.grey[900]! : Colors.grey[100]!);
        colors = widget.customColors ?? [Colors.grey[300]!, Colors.grey[100]!, Colors.grey[300]!];
        break;
    }

    final border = widget.borderRadius ?? BorderRadius.circular(8);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        if (widget.variant == ShimmerVariant.pulse) {
          return Opacity(
            opacity: _animation.value,
            child: Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                borderRadius: border,
                color: colors[0],
              ),
            ),
          );
        }

        // Determina o alinhamento geométrico do degradê baseado na direção
        final isVertical = widget.direction == ShimmerDirection.topToBottom ||
            widget.direction == ShimmerDirection.bottomToTop;

        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: border,
            color: backgroundColor,
          ),
          child: ClipRRect(
            borderRadius: border,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: isVertical ? Alignment.topCenter : Alignment.centerLeft,
                  end: isVertical ? Alignment.bottomCenter : Alignment.centerRight,
                  colors: colors,
                  stops: const [0.0, 0.5, 1.0],
                  transform: _SlidingGradientTransform(
                    slidePercent: _animation.value,
                    isVertical: isVertical,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  final bool isVertical;

  const _SlidingGradientTransform({
    required this.slidePercent,
    required this.isVertical,
  });

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final xTranslation = isVertical ? 0.0 : bounds.width * slidePercent;
    final yTranslation = isVertical ? bounds.height * slidePercent : 0.0;
    return Matrix4.translationValues(xTranslation, yTranslation, 0.0);
  }
}
