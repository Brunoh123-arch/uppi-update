import 'package:flutter/material.dart';
export 'app_marker_address.dart';
export 'app_marker_address_null.dart';
export 'app_marker_drop_off.dart';
export 'app_marker_pickup.dart';
export 'app_marker_stop.dart';

class AppMarker extends StatelessWidget {
  final Widget title;
  final MarkerColor color;
  final MarkerIcon icon;
  final VoidCallback? onTap;

  const AppMarker({
    super.key,
    required this.title,
    this.color = MarkerColor.blue,
    this.icon = MarkerIcon.locate,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Haste do alfinete (agulha metálica cinza/preta fina conectada ao chão)
          Positioned(
            bottom: 0,
            left: (width - 2) / 2, // Centraliza a agulha de 2px de largura no bloco de width
            child: Container(
              width: 2,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF4A4A4A), // Cinza chumbo metálico
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          // Cabeça do alfinete (círculo com borda colorida e centro colorido)
          Positioned(
            bottom: 12, // 14 (haste) - 2 (sobreposição)
            left: (width - 22) / 2, // Centraliza a cabeça circular de 22px
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: foregroundColor,
                  width: 5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: foregroundColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
          // Card flutuante com endereço e lápis
          Positioned(
            bottom: 38, // Acima da cabeça do alfinete
            left: (width - cardWidth) / 2,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                width: cardWidth,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.grey.shade300,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: title,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget buildBubbleContent(BuildContext context, String addressText, {VoidCallback? onTap}) {
    final match = RegExp(
      r'^(\d+(?:[.,]\d+)?\s*(?:km|min|m|h)(?:\s+\/?\s*\d+(?:[.,]\d+)?\s*(?:km|min|m|h))*)\s+(.*)$',
      caseSensitive: false,
    ).firstMatch(addressText);

    final metrics = match?.group(1);
    final restAddress = match?.group(2) ?? addressText;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (metrics != null) ...[
          Text(
            metrics.replaceAll('\n', ' \n '),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.0,
              fontWeight: FontWeight.w900,
              color: Colors.black,
              height: 1.1,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 1,
            height: 24,
            color: Colors.grey.shade300,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            restAddress.split(',').first,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.0,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 6),
          const Icon(
            Icons.edit_outlined,
            color: Colors.black54,
            size: 14,
          ),
        ],
      ],
    );
  }

  Color get foregroundColor {
    switch (color) {
      case MarkerColor.green:
        return const Color(0xFF2E7D32); // Beautiful Green (Pickup)
      case MarkerColor.black:
        return const Color(0xFFD32F2F); // Beautiful Red (Destination/Dropoff)
      case MarkerColor.blue:
        return const Color(0xFF1976D2); // Beautiful Blue (Stop)
    }
  }

  Color get backgroundColor {
    switch (color) {
      case MarkerColor.green:
        return const Color(0xFFE2F9EB);
      case MarkerColor.black:
        return const Color(0xFFFFEBEE);
      case MarkerColor.blue:
        return const Color(0xFFE3F2FD);
    }
  }

  static const double width = 280;
  static const double height = 110;
  static const double cardWidth = 260;
  static const Alignment alignment = Alignment.bottomCenter;
}

enum MarkerColor { blue, green, black }

enum MarkerIcon { location, locate }
