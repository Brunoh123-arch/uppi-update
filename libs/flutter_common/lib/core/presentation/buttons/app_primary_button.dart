import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/extensions/extensions.dart';

class AppPrimaryButton extends StatefulWidget {
  final Function()? onPressed;
  final Widget child;
  final bool isDisabled;
  final PrimaryButtonColor color;

  const AppPrimaryButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isDisabled = false,
    this.color = PrimaryButtonColor.primary,
  });

  @override
  State<AppPrimaryButton> createState() => _AppPrimaryButtonState();
}

class _AppPrimaryButtonState extends State<AppPrimaryButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.isDisabled ? null : widget.onPressed,
      onTapDown: widget.isDisabled
          ? null
          : (_) => setState(() => _isPressed = true),
      onTapUp: widget.isDisabled
          ? null
          : (_) => setState(() => _isPressed = false),
      onTapCancel: widget.isDisabled
          ? null
          : () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: IgnorePointer(
          child: ElevatedButton(
            onPressed: widget.isDisabled ? null : widget.onPressed,
            style: ButtonStyle(
              padding: WidgetStateProperty.all(const EdgeInsets.all(16)),
              backgroundColor: widget.color == PrimaryButtonColor.primary
                  ? primaryButtonBackground(context)
                  : errorButtonBackground(context),
              overlayColor: WidgetStateProperty.all(
                Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }

  WidgetStateProperty<Color> primaryButtonBackground(BuildContext context) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return context.theme.colorScheme.onSurface.withValues(alpha: 0.12);
        } else if (states.contains(WidgetState.hovered)) {
          return context.colorScheme.primary;
        } else if (states.contains(WidgetState.pressed)) {
          return ColorPalette.primary40;
        } else {
          return context.colorScheme.primary;
        }
      });

  WidgetStateProperty<Color> errorButtonBackground(BuildContext context) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return context.theme.colorScheme.onSurface.withValues(alpha: 0.12);
        } else if (states.contains(WidgetState.hovered)) {
          return ColorPalette.error50;
        } else if (states.contains(WidgetState.pressed)) {
          return ColorPalette.error30;
        } else {
          return ColorPalette.error40;
        }
      });
}

enum PrimaryButtonColor { primary, error }
