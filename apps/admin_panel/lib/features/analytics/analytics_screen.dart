import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────
//  Color constants (matches app theme)
// ─────────────────────────────────────────────
const _kPrimary = Color(0xFF096EFF);
const _kSurface = Color(0xFF1E293B);
const _kBackground = Color(0xFF0F172A);
const _kSubtext = Color(0xFF94A3B8);
const _kBorder = Color(0xFF2D3F58);

// ─────────────────────────────────────────────
//  AnalyticsScreen
// ─────────────────────────────────────────────
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _isLoading = true;
  String? _error;

  // ── Funnel ────────────────────────────────
  int _funnelTotal = 0;
  int _funnelAccepted = 0;
  int _funnelCompleted = 0;
  int _funnelRated = 0;

  // ── Heatmap ──────────────────────────────
  // [weekday 0=Dom..6=Sáb][hour 0-23]
  List<List<int>> _heatmap = List.generate(7, (_) => List.filled(24, 0));
  int _heatmapMax = 1;

  // ── Health ────────────────────────────────
  double _churnRate = 0.0;
  double _nps = 0.0;
  String _avgWaitTime = 'Dado não disponível';

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await Future.wait([
        _loadFunnelAndHeatmap(),
        _loadHealthMetrics(),
      ]);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ──────────────────────────────────────────
  //  Funnel + Heatmap (share same rides query)
  // ──────────────────────────────────────────
  Future<void> _loadFunnelAndHeatmap() async {
    final client = Supabase.instance.client;
    final since = DateTime.now()
        .subtract(const Duration(days: 30))
        .toUtc()
        .toIso8601String();

    final ridesRaw = await client
        .from('rides')
        .select('id, driver_id, status, driver_rating, created_at, accepted_at')
        .gte('created_at', since);

    // Funnel counts
    int total = ridesRaw.length;
    int accepted = 0;
    int completed = 0;
    int rated = 0;

    // Heatmap grid
    final grid = List.generate(7, (_) => List.filled(24, 0));
    int maxVal = 1;

    // Wait time
    double totalWaitSec = 0;
    int waitCount = 0;

    for (var r in ridesRaw) {
      if (r['driver_id'] != null) accepted++;
      if (r['status'] == 'completed') completed++;
      if (r['driver_rating'] != null) rated++;

      // Heatmap
      if (r['created_at'] != null) {
        final dt = DateTime.parse(r['created_at']).toLocal();
        // weekday: Mon=1..Sun=7 → map to Sun=0, Mon=1..Sat=6
        final dow = dt.weekday % 7;
        final hour = dt.hour;
        grid[dow][hour]++;
        if (grid[dow][hour] > maxVal) maxVal = grid[dow][hour];
      }

      // Wait time
      if (r['created_at'] != null && r['accepted_at'] != null) {
        try {
          final created = DateTime.parse(r['created_at']);
          final acceptedAt = DateTime.parse(r['accepted_at']);
          final diff = acceptedAt.difference(created).inSeconds;
          if (diff > 0 && diff < 3600) {
            totalWaitSec += diff;
            waitCount++;
          }
        } catch (_) {}
      }
    }

    String waitTimeDisplay = 'Dado não disponível';
    if (waitCount > 0) {
      final avgSec = (totalWaitSec / waitCount).round();
      final mins = avgSec ~/ 60;
      final secs = avgSec % 60;
      waitTimeDisplay = '${mins}min ${secs}s';
    }

    if (mounted) {
      setState(() {
        _funnelTotal = total;
        _funnelAccepted = accepted;
        _funnelCompleted = completed;
        _funnelRated = rated;
        _heatmap = grid;
        _heatmapMax = maxVal;
        _avgWaitTime = waitTimeDisplay;
      });
    }
  }

  // ──────────────────────────────────────────
  //  Health metrics (Churn + NPS)
  // ──────────────────────────────────────────
  Future<void> _loadHealthMetrics() async {
    final client = Supabase.instance.client;
    final now = DateTime.now();

    final currentMonthStart =
        DateTime(now.year, now.month, 1).toUtc().toIso8601String();
    final prevMonthStart =
        DateTime(now.year, now.month - 1, 1).toUtc().toIso8601String();
    final prevMonthEnd =
        DateTime(now.year, now.month, 0, 23, 59, 59).toUtc().toIso8601String();

    // Drivers active last month
    final prevRides = await client
        .from('rides')
        .select('driver_id')
        .eq('status', 'completed')
        .gte('created_at', prevMonthStart)
        .lte('created_at', prevMonthEnd)
        .not('driver_id', 'is', null);

    final Set<String> prevActive =
        prevRides.map<String>((r) => r['driver_id'].toString()).toSet();

    // Drivers active this month
    final currRides = await client
        .from('rides')
        .select('driver_id')
        .eq('status', 'completed')
        .gte('created_at', currentMonthStart)
        .not('driver_id', 'is', null);

    final Set<String> currActive =
        currRides.map<String>((r) => r['driver_id'].toString()).toSet();

    int churned = 0;
    for (final d in prevActive) {
      if (!currActive.contains(d)) churned++;
    }
    final churn = prevActive.isEmpty
        ? 0.0
        : (churned / prevActive.length) * 100;

    // NPS – last 30 days ratings
    final since = DateTime.now()
        .subtract(const Duration(days: 30))
        .toUtc()
        .toIso8601String();
    final ratings = await client
        .from('rides')
        .select('driver_rating')
        .gte('created_at', since)
        .not('driver_rating', 'is', null);

    int promoters = 0;
    int detractors = 0;
    final totalRatings = ratings.length;

    for (var r in ratings) {
      final rt = (r['driver_rating'] as num).toDouble();
      if (rt == 5) promoters++;
      if (rt <= 2) detractors++;
    }

    final nps = totalRatings == 0
        ? 0.0
        : ((promoters - detractors) / totalRatings) * 100;

    if (mounted) {
      setState(() {
        _churnRate = churn;
        _nps = nps.clamp(-100.0, 100.0);
      });
    }
  }

  // ──────────────────────────────────────────
  //  Build
  // ──────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header ─────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kPrimary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.analytics_rounded,
                    color: _kPrimary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Analytics Avançado',
                      style: GoogleFonts.outfit(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    Text(
                      'Funil de conversão, mapa de calor e saúde da plataforma (últimos 30 dias).',
                      style: GoogleFonts.outfit(
                          fontSize: 13, color: _kSubtext),
                    ),
                  ],
                ),
              ),
              IconButton.outlined(
                onPressed: _loadAnalytics,
                icon: const Icon(Icons.refresh_rounded, color: _kPrimary),
                tooltip: 'Atualizar dados',
              ),
            ],
          ),

          const SizedBox(height: 32),

          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(80),
                child: CircularProgressIndicator(color: _kPrimary),
              ),
            )
          else if (_error != null)
            _ErrorCard(message: _error!)
          else ...[
            // ─── Saúde da Plataforma ─────────
            _buildHealthRow(),

            const SizedBox(height: 24),

            // ─── Funil + Heatmap ─────────────
            LayoutBuilder(builder: (ctx, constraints) {
              if (constraints.maxWidth > 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: _buildFunnelCard()),
                    const SizedBox(width: 24),
                    Expanded(flex: 6, child: _buildHeatmapCard()),
                  ],
                );
              }
              return Column(children: [
                _buildFunnelCard(),
                const SizedBox(height: 24),
                _buildHeatmapCard(),
              ]);
            }),
          ],
        ],
      ),
    );
  }

  // ──────────────────────────────────────────
  //  Health Row
  // ──────────────────────────────────────────
  Widget _buildHealthRow() {
    final churnColor = _churnRate > 20
        ? Colors.redAccent
        : _churnRate > 10
            ? Colors.orangeAccent
            : Colors.greenAccent;

    final npsColor = _nps >= 50
        ? Colors.greenAccent
        : _nps >= 0
            ? Colors.orangeAccent
            : Colors.redAccent;

    return Row(
      children: [
        Expanded(
          child: _HealthCard(
            label: 'NPS Aproximado',
            value: _nps.toStringAsFixed(0),
            subtitle: '% promotores (5★) − % detratores (1-2★)',
            icon: Icons.thumb_up_rounded,
            color: npsColor,
            gauge: ((_nps + 100) / 200).clamp(0.0, 1.0),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _HealthCard(
            label: 'Churn Rate Motoristas',
            value: '${_churnRate.toStringAsFixed(1)}%',
            subtitle: 'Motoristas ativos no mês anterior que pararam',
            icon: Icons.person_remove_rounded,
            color: churnColor,
            gauge: (_churnRate / 100).clamp(0.0, 1.0),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _HealthCard(
            label: 'Tempo Médio de Espera',
            value: _avgWaitTime,
            subtitle: 'Da solicitação até aceite pelo motorista',
            icon: Icons.timer_rounded,
            color: _kPrimary,
            gauge: null,
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────
  //  Funnel Card
  // ──────────────────────────────────────────
  Widget _buildFunnelCard() {
    final steps = [
      _FunnelStep(
          label: 'Solicitadas',
          count: _funnelTotal,
          icon: Icons.flag_rounded,
          color: const Color(0xFF096EFF)),
      _FunnelStep(
          label: 'Aceitas',
          count: _funnelAccepted,
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF0EA5E9)),
      _FunnelStep(
          label: 'Completadas',
          count: _funnelCompleted,
          icon: Icons.done_all_rounded,
          color: const Color(0xFF10B981)),
      _FunnelStep(
          label: 'Avaliadas',
          count: _funnelRated,
          icon: Icons.star_rounded,
          color: const Color(0xFFF59E0B)),
    ];

    return _SectionCard(
      title: 'Funil de Corridas',
      subtitle: 'Conversão etapa a etapa',
      icon: Icons.filter_alt_rounded,
      child: Column(
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            _buildFunnelStep(steps[i], i),
            if (i < steps.length - 1)
              _buildConversionArrow(steps[i], steps[i + 1]),
          ],
        ],
      ),
    );
  }

  Widget _buildFunnelStep(_FunnelStep step, int index) {
    final pct =
        _funnelTotal == 0 ? 0.0 : step.count / _funnelTotal;
    // Each step visually narrower
    final widthFactor = math.max(0.3, 1.0 - index * 0.14);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(step.icon, color: step.color, size: 16),
              const SizedBox(width: 8),
              Text(step.label,
                  style: GoogleFonts.outfit(
                      color: Colors.white70, fontSize: 13)),
              const Spacer(),
              Text('${step.count}',
                  style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              const SizedBox(width: 6),
              Text('(${(pct * 100).toStringAsFixed(1)}%)',
                  style: GoogleFonts.outfit(
                      color: step.color, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(builder: (ctx, constraints) {
            return Stack(
              children: [
                Container(
                  height: 26,
                  width: constraints.maxWidth,
                  decoration: BoxDecoration(
                    color: _kBackground,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                  height: 26,
                  width: constraints.maxWidth *
                      widthFactor *
                      pct.clamp(0.03, 1.0),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [step.color, step.color.withOpacity(0.55)],
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildConversionArrow(_FunnelStep from, _FunnelStep to) {
    final conv =
        from.count == 0 ? 0.0 : to.count / from.count * 100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        children: [
          const Icon(Icons.arrow_downward_rounded,
              size: 13, color: _kSubtext),
          const SizedBox(width: 4),
          Text('conversão: ${conv.toStringAsFixed(1)}%',
              style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: _kSubtext,
                  fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────
  //  Heatmap Card
  // ──────────────────────────────────────────
  Widget _buildHeatmapCard() {
    const days = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

    return _SectionCard(
      title: 'Heatmap de Horário',
      subtitle: 'Corridas por hora × dia da semana (últimos 30 dias)',
      icon: Icons.grid_view_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Legenda
          Row(
            children: [
              Text('Baixo',
                  style: GoogleFonts.outfit(
                      fontSize: 11, color: _kSubtext)),
              const SizedBox(width: 8),
              ...List.generate(10, (i) {
                final t = i / 9.0;
                return Container(
                    width: 20, height: 14, color: _heatColor(t));
              }),
              const SizedBox(width: 8),
              Text('Alto ($_heatmapMax)',
                  style: GoogleFonts.outfit(
                      fontSize: 11, color: _kSubtext)),
            ],
          ),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hour labels
                Row(
                  children: [
                    const SizedBox(width: 44),
                    for (int h = 0; h < 24; h++)
                      SizedBox(
                        width: 26,
                        child: Text(
                          h.toString().padLeft(2, '0'),
                          style: GoogleFonts.outfit(
                              fontSize: 9, color: _kSubtext),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                // Day rows
                for (int d = 0; d < 7; d++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          child: Text(
                            days[d],
                            style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: _kSubtext,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 4),
                        for (int h = 0; h < 24; h++)
                          _HeatCell(
                            value: _heatmap[d][h],
                            maxValue: _heatmapMax,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _heatColor(double t) {
    if (t <= 0) return const Color(0xFF1E293B);
    final clampedT = t.clamp(0.0, 1.0);
    const stops = [
      Color(0xFF1E3A5F),
      Color(0xFF1A6BB5),
      Color(0xFF22D3EE),
      Color(0xFFFBBF24),
      Color(0xFFEA580C),
    ];
    final segment = clampedT * (stops.length - 1);
    final idx = segment.floor().clamp(0, stops.length - 2);
    final frac = segment - idx;
    return Color.lerp(stops[idx], stops[idx + 1], frac)!;
  }
}

// ─────────────────────────────────────────────
//  Helper widgets
// ─────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _kPrimary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    Text(subtitle,
                        style: GoogleFonts.outfit(
                            fontSize: 12, color: _kSubtext)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: _kBorder.withOpacity(0.5), height: 1),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final double? gauge;

  const _HealthCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.gauge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: GoogleFonts.outfit(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(value,
              style: GoogleFonts.outfit(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 26)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: GoogleFonts.outfit(
                  color: _kSubtext, fontSize: 11)),
          if (gauge != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: gauge,
              backgroundColor: _kBackground,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeatCell extends StatelessWidget {
  final int value;
  final int maxValue;

  const _HeatCell({required this.value, required this.maxValue});

  @override
  Widget build(BuildContext context) {
    final intensity = maxValue == 0 ? 0.0 : value / maxValue;
    final color = _AnalyticsScreenState._heatColor(intensity);

    return Tooltip(
      message: '$value corridas',
      child: Container(
        width: 22,
        height: 22,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Erro ao carregar dados: $message',
                style: GoogleFonts.outfit(
                    color: Colors.redAccent, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Data models
// ─────────────────────────────────────────────
class _FunnelStep {
  final String label;
  final int count;
  final IconData icon;
  final Color color;

  _FunnelStep({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });
}
