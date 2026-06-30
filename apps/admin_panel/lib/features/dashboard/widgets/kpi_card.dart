import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final double delta;
  final bool isPercentage;
  final bool invertDeltaColor;

  const KpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.delta,
    required this.isPercentage,
    this.invertDeltaColor = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasDelta = delta != 0.0;
    final isDeltaPositive = delta > 0.0;
    Color deltaColor = Colors.white30;
    if (hasDelta) {
      if (invertDeltaColor) {
        deltaColor = isDeltaPositive ? Colors.redAccent : Colors.greenAccent;
      } else {
        deltaColor = isDeltaPositive ? Colors.greenAccent : Colors.redAccent;
      }
    }

    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white10),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.1),
                  radius: 20,
                  child: Icon(icon, color: color, size: 20),
                ),
                if (hasDelta)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: deltaColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isDeltaPositive ? Icons.trending_up : Icons.trending_down,
                          size: 14,
                          color: deltaColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${isDeltaPositive ? '+' : ''}${delta.toStringAsFixed(1)}${isPercentage ? 'pp' : '%'}',
                          style: TextStyle(
                            color: deltaColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white30, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
