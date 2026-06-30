import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';

class DashboardChartBox extends StatelessWidget {
  final String title;
  final List<FlSpot> spots;
  final Color color;
  final bool isCurrency;
  final List<String> chartLabels;
  final String selectedPeriod;

  const DashboardChartBox({
    super.key,
    required this.title,
    required this.spots,
    required this.color,
    required this.isCurrency,
    required this.chartLabels,
    required this.selectedPeriod,
  });

  @override
  Widget build(BuildContext context) {
    double maxVal = 5.0;
    for (var s in spots) {
      if (s.y > maxVal) maxVal = s.y;
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 5,
                  getDrawingHorizontalLine: _getDrawingHorizontalLine,
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: selectedPeriod == 'Hoje' ? 4 : 1,
                      getTitlesWidget: (value, meta) {
                        int index = value.toInt();
                        if (index < 0 || index >= chartLabels.length) return const SizedBox.shrink();
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            chartLabels[index],
                            style: const TextStyle(color: Colors.white30, fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          isCurrency
                              ? 'R\$${value.toInt()}'
                              : value.toInt().toString(),
                          style: const TextStyle(color: Colors.white30, fontSize: 10),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: spots.isNotEmpty ? (spots.length - 1).toDouble() : 5,
                minY: 0,
                maxY: maxVal * 1.2,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.5)]),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: 0.2),
                          color.withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static FlLine _getDrawingHorizontalLine(double value) {
    return const FlLine(
      color: Colors.white10,
      strokeWidth: 1,
    );
  }
}
