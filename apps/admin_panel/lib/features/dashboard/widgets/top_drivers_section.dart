import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TopDriversSection extends StatelessWidget {
  final List<Map<String, dynamic>> topDrivers;
  final Function(String driverId) onDriverTap;

  const TopDriversSection({
    super.key,
    required this.topDrivers,
    required this.onDriverTap,
  });

  @override
  Widget build(BuildContext context) {
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
            'Top 5 Motoristas (Período)',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          if (topDrivers.isEmpty)
            const SizedBox(
              height: 180,
              child: Center(
                child: Text('Sem corridas finalizadas no período.', style: TextStyle(color: Colors.white30)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topDrivers.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 16),
              itemBuilder: (context, index) {
                final d = topDrivers[index];
                final rating = (d['rating_count'] as int) > 0 ? ((d['rating_sum'] as double) / (d['rating_count'] as int)) : 5.0;

                return InkWell(
                  onTap: () => onDriverTap(d['id'].toString()),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.white10,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d['name'],
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.star, color: Colors.amber, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    rating.toStringAsFixed(1),
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${d['count']} corridas',
                                    style: const TextStyle(color: Colors.white30, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'R\$ ${d['earnings'].toStringAsFixed(2)}',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            color: Colors.greenAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
