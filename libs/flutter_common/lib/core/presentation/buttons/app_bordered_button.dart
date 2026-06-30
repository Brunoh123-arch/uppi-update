import 'package:flutter/cupertino.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/extensions/extensions.dart';

class AppBorderedButton extends StatefulWidget {
  final Function() onPressed;
  final String title;
  final Color textColor;
  final bool isPrimary;
  final bool isDisabled;
  final IconData? icon;

  const AppBorderedButton({
    super.key,
    required this.onPressed,
    required this.title,
    this.textColor = ColorPalette.primary30,
    this.isPrimary = false,
    this.isDisabled = false,
    this.icon,
  });

  @override
  State<AppBorderedButton> createState() => _AppBorderedButtonState();
}

class _AppBorderedButtonState extends State<AppBorderedButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ColorPalette.primary95),
          ),
          child: CupertinoButton(
            padding: const EdgeInsets.all(12),
            onPressed: widget.isDisabled ? null : widget.onPressed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(widget.icon, color: widget.textColor),
                  ),
                Text(
                  widget.title,
                  style: widget.isPrimary
                      ? context.titleSmall?.copyWith(color: widget.textColor)
                      : context.bodyMedium?.copyWith(color: widget.textColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
