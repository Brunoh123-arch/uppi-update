import 'package:flutter/material.dart';
import 'package:flutter_common/core/extensions/extensions.dart';

class AppCardSheet extends StatelessWidget {
  final Widget child;
  final bool showHandle;
  final bool isFullScreen;

  const AppCardSheet({
    super.key,
    required this.child,
    this.showHandle = true,
    this.isFullScreen = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: context.responsive(
        BoxDecoration(
          borderRadius: isFullScreen
              ? null
              : const BorderRadius.vertical(top: Radius.circular(30)),
          color: Theme.of(context).colorScheme.surface,
          boxShadow: isFullScreen
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x3F0E275D),
                    blurRadius: 20,
                    offset: Offset(2, 4),
                    spreadRadius: 0,
                  ),
                ],
        ),
        xl: const BoxDecoration(),
      ),
      child: child,
    );
  }
}
