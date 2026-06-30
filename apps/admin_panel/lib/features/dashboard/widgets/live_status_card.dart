import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'pulsing_indicator.dart';

class LiveStatusCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const LiveStatusCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (value > 0)
                PulsingIndicator(color: color)
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value.toString(),
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
