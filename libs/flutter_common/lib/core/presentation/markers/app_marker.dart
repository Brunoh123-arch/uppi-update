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
          // Marcador customizado no chão (ponto azul pulsante para origem, bandeira para destino)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: color == MarkerColor.green
                  ? _buildPickupDot()
                  : (color == MarkerColor.black ? _buildCheckeredFlag() : _buildStopDot()),
            ),
          ),
          // Card flutuante com endereço e lápis
          Positioned(
            bottom: 30, // Acima do marcador do chão
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
                      color: Colors.black.withOpacity(0.15),
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

  Widget _buildPickupDot() {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: const Color(0xFF2892FF).withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: const BoxDecoration(
            color: Color(0xFF2892FF),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFFFFD54F),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckeredFlag() {
    return const Text(
      "🏁",
      style: TextStyle(fontSize: 22),
    );
  }

  Widget _buildStopDot() {
    return Container(
      width: 16,
      height: 16,
      decoration: const BoxDecoration(
        color: Color(0xFF1976D2),
        shape: BoxShape.circle,
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

  static const double width = 250;
  static const double height = 100;
  static const double cardWidth = 230;
  static const Alignment alignment = Alignment.bottomCenter;
}

enum MarkerColor { blue, green, black }

enum MarkerIcon { location, locate }
