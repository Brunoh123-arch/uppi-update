import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'widgets/pulsing_indicator.dart';
import 'widgets/kpi_card.dart';
import 'widgets/live_status_card.dart';
import 'widgets/dashboard_chart_box.dart';
import 'widgets/top_drivers_section.dart';

class OverviewDashboardScreen extends StatefulWidget {
  const OverviewDashboardScreen({super.key});

  @override
  State<OverviewDashboardScreen> createState() =>
      _OverviewDashboardScreenState();
}

class _OverviewDashboardScreenState extends State<OverviewDashboardScreen> {
  String _selectedPeriod = '7D'; // 'Hoje', '7D', '30D', '90D'
  bool isLoading = true;

  // KPIs
  int totalOrders = 0;
  int ridesToday = 0;
  int activeDriversCount = 0;
  int totalDrivers = 0;
  int pendingDriversCount = 0;
  int pendingPayoutsCount = 0;
  int activeComplaintsCount = 0;
  int registeredRiders = 0;
  double platformRevenue = 0.0;
  double conversionRate = 0.0;
  double cancellationRate = 0.0;
  double averageRating = 0.0;

  // Deltas (% vs período anterior)
  double totalOrdersDelta = 0.0;
  double revenueDelta = 0.0;
  double conversionDelta = 0.0;
  double cancellationDelta = 0.0;

  // Status de Corridas ao Vivo
  int searchingRides = 0;
  int arrivingRides = 0;
  int inProgressRides = 0;
  int waitingReviewRides = 0;

  // Gráficos
  List<FlSpot> weeklyRidesSpots = [];
  List<FlSpot> weeklyRevenueSpots = [];
  List<String> chartLabels = [];

  // Top Motoristas
  List<Map<String, dynamic>> topDrivers = [];

  RealtimeChannel? _ridesChannel;
  RealtimeChannel? _profilesChannel;
  RealtimeChannel? _payoutsChannel;
  RealtimeChannel? _complaintsChannel;
  RealtimeChannel? _supportTicketsChannel;
  Timer? _debounceTimer;
  Timer? _periodicTimer;

  // Cache de perfis para exibição de nomes em tempo real sem sobrecarga
  final Map<String, String> _profileNamesCache = {};
  final Set<String> _pendingProfileFetches = {};
  String _lastUpdateString = '';

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _startRealtimeChannels();
    _startPeriodicTimer();
  }

  void _startPeriodicTimer() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _loadDashboardData(silent: true);
      }
    });
  }

  Future<void> _fetchProfileName(String id) async {
    if (id.isEmpty) return;
    if (_profileNamesCache.containsKey(id) || _pendingProfileFetches.contains(id)) return;
    _pendingProfileFetches.add(id);

    try {
      final client = Supabase.instance.client;
      final res = await client
          .from('profiles')
          .select('full_name')
          .eq('id', id)
          .maybeSingle();
      if (res != null && res['full_name'] != null) {
        if (mounted) {
          setState(() {
            _profileNamesCache[id] = res['full_name'] as String;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _profileNamesCache[id] = 'Usuário #${id.substring(0, 5)}';
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching profile name: $e');
    } finally {
      _pendingProfileFetches.remove(id);
    }
  }

  void _startRealtimeChannels() {
    final client = Supabase.instance.client;

    _ridesChannel = client.channel('dashboard_realtime_rides')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'rides',
        callback: (payload) => _onRealtimeChange(),
      )
      .subscribe();

    _profilesChannel = client.channel('dashboard_realtime_profiles')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'profiles',
        callback: (payload) => _onRealtimeChange(),
      )
      .subscribe();

    _payoutsChannel = client.channel('dashboard_realtime_payouts')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'payout_requests',
        callback: (payload) => _onRealtimeChange(),
      )
      .subscribe();

    _complaintsChannel = client.channel('dashboard_realtime_complaints')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'complaints',
        callback: (payload) => _onRealtimeChange(),
      )
      .subscribe();

    _supportTicketsChannel = client.channel('dashboard_realtime_support_tickets')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'support_tickets',
        callback: (payload) => _onRealtimeChange(),
      )
      .subscribe();
  }

  void _onRealtimeChange() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        _loadDashboardData(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    _ridesChannel?.unsubscribe();
    _profilesChannel?.unsubscribe();
    _payoutsChannel?.unsubscribe();
    _complaintsChannel?.unsubscribe();
    _supportTicketsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadDashboardData({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => isLoading = true);

    try {
      final client = Supabase.instance.client;

      // 1. Data inicial e final do período selecionado
      final now = DateTime.now().toUtc();
      final localNow = DateTime.now();
      DateTime startDate;
      DateTime prevStartDate;
      DateTime prevEndDate;

      if (_selectedPeriod == 'Hoje') {
        startDate = DateTime(localNow.year, localNow.month, localNow.day).toUtc();
        prevStartDate = startDate.subtract(const Duration(days: 1));
        prevEndDate = startDate;
      } else if (_selectedPeriod == '7D') {
        startDate = now.subtract(const Duration(days: 7));
        prevStartDate = startDate.subtract(const Duration(days: 7));
        prevEndDate = startDate;
      } else if (_selectedPeriod == '30D') {
        startDate = now.subtract(const Duration(days: 30));
        prevStartDate = startDate.subtract(const Duration(days: 30));
        prevEndDate = startDate;
      } else {
        startDate = now.subtract(const Duration(days: 90));
        prevStartDate = startDate.subtract(const Duration(days: 90));
        prevEndDate = startDate;
      }

      final startIso = startDate.toIso8601String();
      final prevStartIso = prevStartDate.toIso8601String();
      final prevEndIso = prevEndDate.toIso8601String();

      // 2. Buscar contagem de usuários
      final ridersRes = await client.from('profiles').select('id').eq('role', 'rider');
      final totalRiders = ridersRes.length;

      final driversRes = await client.from('profiles').select('id, status, is_approved').eq('role', 'driver');
      final onlineDrivers = driversRes.where((d) => d['status'] == 'online' || d['status'] == 'in_progress').length;
      final driversTotal = driversRes.length;
      final pendingDrivers = driversRes.where((d) => d['is_approved'] != true).length;

      int pendingPayouts = 0;
      try {
        final payoutsRes = await client.from('payout_requests').select('id').eq('status', 'pending');
        pendingPayouts = payoutsRes.length;
      } catch (e) {
        debugPrint('Erro ao buscar payout_requests no dashboard: $e');
      }

      int activeComplaints = 0;
      try {
        final complaintsRes = await client.from('complaints').select('id').eq('status', 'pending');
        activeComplaints = complaintsRes.length;
      } catch (e) {
        debugPrint('Erro ao buscar complaints no dashboard: $e');
      }
      try {
        final ticketsRes = await client.from('support_tickets').select('id').eq('status', 'open');
        activeComplaints += ticketsRes.length;
      } catch (e) {
        debugPrint('Erro ao buscar support_tickets no dashboard: $e');
      }

      // 3. Buscar corridas do período atual
      final ridesRes = await client
          .from('rides')
          .select('id, status, fare, platform_fee, created_at, driver_rating, driver_id, rider_id')
          .gte('created_at', startIso);

      final totalRides = ridesRes.length;

      // 4. Buscar corridas do período anterior para deltas
      final prevRidesRes = await client
          .from('rides')
          .select('id, status, fare, platform_fee')
          .gte('created_at', prevStartIso)
          .lt('created_at', prevEndIso);

      final prevTotalRides = prevRidesRes.length;

      // 5. Corridas Hoje (Midnight local to UTC)
      final todayStart = DateTime(localNow.year, localNow.month, localNow.day).toUtc().toIso8601String();
      final todayRidesRes = await client
          .from('rides')
          .select('id')
          .gte('created_at', todayStart);
      final countRidesToday = todayRidesRes.length;

      // 6. Corridas Ativas ao Vivo (Status Realtime)
      final liveRidesRes = await client
          .from('rides')
          .select('status')
          .inFilter('status', ['requested', 'searching', 'accepted', 'driver_accepted', 'arrived', 'in_progress', 'waiting_for_review']);

      int searching = 0;
      int arriving = 0;
      int inProgress = 0;
      int waitingReview = 0;

      for (var r in liveRidesRes) {
        final st = r['status'];
        if (st == 'requested' || st == 'searching') {
          searching++;
        } else if (st == 'accepted' || st == 'driver_accepted' || st == 'arrived') {
          arriving++;
        } else if (st == 'in_progress') {
          inProgress++;
        } else if (st == 'waiting_for_review') {
          waitingReview++;
        }
      }

      // 7. Estatísticas do período atual
      final completedRides = ridesRes.where((r) => r['status'] == 'completed').toList();
      final canceledRides = ridesRes.where((r) => r['status'] == 'rider_canceled' || r['status'] == 'driver_canceled' || r['status'] == 'canceled').length;

      double revenue = 0.0;
      double ratingSum = 0.0;
      int ratedCount = 0;

      for (var r in completedRides) {
        if (r['platform_fee'] != null) {
          revenue += (r['platform_fee'] as num).toDouble();
        }
        if (r['driver_rating'] != null) {
          ratingSum += (r['driver_rating'] as num).toDouble();
          ratedCount++;
        }
      }

      double avgRating = ratedCount > 0 ? ratingSum / ratedCount : 4.8;

      double convRate = totalRides > 0
          ? (completedRides.length / totalRides) * 100
          : 0.0;
      double cancelRate = totalRides > 0
          ? (canceledRides / totalRides) * 100
          : 0.0;

      // 8. Estatísticas do período anterior (Deltas)
      final prevCompletedRides = prevRidesRes.where((r) => r['status'] == 'completed').toList();
      final prevCanceledRides = prevRidesRes.where((r) => r['status'] == 'rider_canceled' || r['status'] == 'driver_canceled' || r['status'] == 'canceled').length;

      double prevRevenue = 0.0;
      for (var r in prevCompletedRides) {
        if (r['platform_fee'] != null) {
          prevRevenue += (r['platform_fee'] as num).toDouble();
        }
      }

      double prevConvRate = prevTotalRides > 0
          ? (prevCompletedRides.length / prevTotalRides) * 100
          : 0.0;
      double prevCancelRate = prevTotalRides > 0
          ? (prevCanceledRides / prevTotalRides) * 100
          : 0.0;

      // Calcular variações percentuais
      double ordersDelta = prevTotalRides > 0
          ? ((totalRides - prevTotalRides) / prevTotalRides) * 100
          : 0.0;
      double revDelta = prevRevenue > 0
          ? ((revenue - prevRevenue) / prevRevenue) * 100
          : 0.0;
      double convDelta = convRate - prevConvRate;
      double cancelDelta = cancelRate - prevCancelRate;

      // 9. Agrupamento de Gráficos (por dia)
      int daysToChart = _selectedPeriod == 'Hoje' ? 24 : (_selectedPeriod == '7D' ? 7 : (_selectedPeriod == '30D' ? 30 : 12));
      List<double> ridesByInterval = List.filled(daysToChart, 0.0);
      List<double> revenueByInterval = List.filled(daysToChart, 0.0);
      List<String> labels = [];

      if (_selectedPeriod == 'Hoje') {
        // Por Hora
        for (int i = 0; i < 24; i++) {
          labels.add('${i}h');
        }
        for (var r in ridesRes) {
          if (r['created_at'] != null) {
            final dt = DateTime.parse(r['created_at']).toLocal();
            if (dt.year == localNow.year && dt.month == localNow.month && dt.day == localNow.day) {
              ridesByInterval[dt.hour] += 1.0;
              if (r['status'] == 'completed' && r['platform_fee'] != null) {
                revenueByInterval[dt.hour] += (r['platform_fee'] as num).toDouble();
              }
            }
          }
        }
      } else if (_selectedPeriod == '7D' || _selectedPeriod == '30D') {
        // Por Dia
        for (int i = daysToChart - 1; i >= 0; i--) {
          final targetDate = localNow.subtract(Duration(days: i));
          labels.add('${targetDate.day}/${targetDate.month}');
        }

        final date1 = DateTime(localNow.year, localNow.month, localNow.day);
        for (var r in ridesRes) {
          if (r['created_at'] != null) {
            final dt = DateTime.parse(r['created_at']).toLocal();
            final date2 = DateTime(dt.year, dt.month, dt.day);
            final difference = date1.difference(date2).inDays;
            if (difference >= 0 && difference < daysToChart) {
              int index = (daysToChart - 1) - difference;
              if (index >= 0 && index < daysToChart) {
                ridesByInterval[index] += 1.0;
                if (r['status'] == 'completed' && r['platform_fee'] != null) {
                  revenueByInterval[index] += (r['platform_fee'] as num).toDouble();
                }
              }
            }
          }
        }
      } else {
        // 90D -> Agrupado por Semana (12 semanas)
        for (int i = 11; i >= 0; i--) {
          labels.add('S${12 - i}');
        }

        final date1 = DateTime(localNow.year, localNow.month, localNow.day);
        for (var r in ridesRes) {
          if (r['created_at'] != null) {
            final dt = DateTime.parse(r['created_at']).toLocal();
            final date2 = DateTime(dt.year, dt.month, dt.day);
            final difference = date1.difference(date2).inDays;
            int weekDiff = difference ~/ 7;
            if (weekDiff >= 0 && weekDiff < 12) {
              int index = 11 - weekDiff;
              if (index >= 0 && index < 12) {
                ridesByInterval[index] += 1.0;
                if (r['status'] == 'completed' && r['platform_fee'] != null) {
                  revenueByInterval[index] += (r['platform_fee'] as num).toDouble();
                }
              }
            }
          }
        }
      }

      List<FlSpot> ridesSpots = [];
      List<FlSpot> revSpots = [];
      for (int i = 0; i < daysToChart; i++) {
        ridesSpots.add(FlSpot(i.toDouble(), ridesByInterval[i]));
        revSpots.add(FlSpot(i.toDouble(), double.parse(revenueByInterval[i].toStringAsFixed(2))));
      }

      // 10. Agrupar Top Motoristas
      final Map<String, Map<String, dynamic>> driverStats = {};
      for (var r in ridesRes) {
        final driverId = r['driver_id'];
        if (driverId != null && r['status'] == 'completed') {
          final fare = (r['fare'] as num?)?.toDouble() ?? 0.0;
          final platformFee = (r['platform_fee'] as num?)?.toDouble() ?? 0.0;
          final driverEarning = fare - platformFee;

          if (driverStats.containsKey(driverId)) {
            driverStats[driverId]!['count'] = (driverStats[driverId]!['count'] as int) + 1;
            driverStats[driverId]!['earnings'] = (driverStats[driverId]!['earnings'] as double) + driverEarning;
            if (r['driver_rating'] != null) {
              driverStats[driverId]!['rating_sum'] = (driverStats[driverId]!['rating_sum'] as double) + (r['driver_rating'] as num).toDouble();
              driverStats[driverId]!['rating_count'] = (driverStats[driverId]!['rating_count'] as int) + 1;
            }
          } else {
            driverStats[driverId] = {
              'id': driverId,
              'name': 'Buscando...',
              'count': 1,
              'earnings': driverEarning,
              'rating_sum': r['driver_rating'] != null ? (r['driver_rating'] as num).toDouble() : 0.0,
              'rating_count': r['driver_rating'] != null ? 1 : 0,
            };
          }
        }
      }

      var sortedDrivers = driverStats.values.toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      final top5 = sortedDrivers.take(5).toList();

      // Buscar nomes dos top 5 motoristas usando o cache de perfis
      for (var dr in top5) {
        final dId = dr['id'];
        if (_profileNamesCache.containsKey(dId)) {
          dr['name'] = _profileNamesCache[dId];
        } else {
          final prof = await client.from('profiles').select('full_name').eq('id', dId).maybeSingle();
          if (prof != null && prof['full_name'] != null) {
            _profileNamesCache[dId] = prof['full_name'] as String;
            dr['name'] = prof['full_name'];
          } else {
            dr['name'] = 'Motorista #${dId.toString().substring(0, 5)}';
          }
        }
      }

      if (mounted) {
        setState(() {
          totalOrders = totalRides;
          ridesToday = countRidesToday;
          activeDriversCount = onlineDrivers;
          totalDrivers = driversTotal;
          pendingDriversCount = pendingDrivers;
          pendingPayoutsCount = pendingPayouts;
          activeComplaintsCount = activeComplaints;
          registeredRiders = totalRiders;
          platformRevenue = revenue;
          conversionRate = convRate;
          cancellationRate = cancelRate;
          averageRating = avgRating;

          totalOrdersDelta = ordersDelta;
          revenueDelta = revDelta;
          conversionDelta = convDelta;
          cancellationDelta = cancelDelta;

          searchingRides = searching;
          arrivingRides = arriving;
          inProgressRides = inProgress;
          waitingReviewRides = waitingReview;

          weeklyRidesSpots = ridesSpots;
          weeklyRevenueSpots = revSpots;
          chartLabels = labels;
          topDrivers = top5;

          final nowLocal = DateTime.now();
          _lastUpdateString = '${nowLocal.hour.toString().padLeft(2, '0')}:${nowLocal.minute.toString().padLeft(2, '0')}:${nowLocal.second.toString().padLeft(2, '0')}';

          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading dashboard stats: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF096EFF)),
            SizedBox(height: 16),
            Text('Carregando métricas executivas...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }



    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 768;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER COM SELETOR DE PERÍODO RESPONSIVO
          isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dashboard Executivo',
                      style: GoogleFonts.outfit(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Visão operacional completa em tempo real.',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const PulsingIndicator(color: Colors.greenAccent),
                        const SizedBox(width: 8),
                        Text(
                          _lastUpdateString.isEmpty
                              ? 'Conectando...'
                              : 'Conectado • $_lastUpdateString',
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Seletor de período no mobile
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: ['Hoje', '7D', '30D', '90D'].map((period) {
                            final isSelected = _selectedPeriod == period;
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedPeriod = period;
                                });
                                _loadDashboardData();
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF096EFF) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  period == 'Hoje' ? 'Hoje' : (period == '7D' ? '7 Dias' : (period == '30D' ? '30 Dias' : '90 Dias')),
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.white : Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dashboard Executivo',
                          style: GoogleFonts.outfit(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Visão operacional completa da plataforma em tempo real.',
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const PulsingIndicator(color: Colors.greenAccent),
                            const SizedBox(width: 8),
                            Text(
                              _lastUpdateString.isEmpty
                                  ? 'Conectando...'
                                  : 'Conectado • Última atualização: $_lastUpdateString',
                              style: const TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // Seletor de período premium
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: ['Hoje', '7D', '30D', '90D'].map((period) {
                          final isSelected = _selectedPeriod == period;
                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedPeriod = period;
                              });
                              _loadDashboardData();
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF096EFF) : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                period == 'Hoje' ? 'Hoje' : (period == '7D' ? '7 Dias' : (period == '30D' ? '30 Dias' : '90 Dias')),
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.white : Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
          const SizedBox(height: 32),

          // 8 KPI CARDS - GRID RESPONSIVO
          LayoutBuilder(builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - (3 * 24)) / 4;
            return Wrap(
              spacing: 24,
              runSpacing: 24,
              children: [
                SizedBox(
                  width: cardWidth >= 220 ? cardWidth : constraints.maxWidth,
                  child: KpiCard(
                    title: 'Corridas no Período',
                    value: totalOrders.toString(),
                    subtitle: 'Rides totais solicitadas',
                    icon: Icons.route,
                    color: const Color(0xFF096EFF),
                    delta: totalOrdersDelta,
                    isPercentage: false,
                  ),
                ),
                SizedBox(
                  width: cardWidth >= 220 ? cardWidth : constraints.maxWidth,
                  child: KpiCard(
                    title: 'Faturamento Plataforma',
                    value: 'R\$ ${platformRevenue.toStringAsFixed(2)}',
                    subtitle: 'Total em taxas recebidas',
                    icon: Icons.attach_money_rounded,
                    color: Colors.greenAccent,
                    delta: revenueDelta,
                    isPercentage: false,
                  ),
                ),
                SizedBox(
                  width: cardWidth >= 220 ? cardWidth : constraints.maxWidth,
                  child: KpiCard(
                    title: 'Taxa de Conversão',
                    value: '${conversionRate.toStringAsFixed(1)}%',
                    subtitle: 'Corridas finalizadas / totais',
                    icon: Icons.check_circle_outline,
                    color: Colors.tealAccent,
                    delta: conversionDelta,
                    isPercentage: true,
                  ),
                ),
                SizedBox(
                  width: cardWidth >= 220 ? cardWidth : constraints.maxWidth,
                  child: KpiCard(
                    title: 'Taxa de Cancelamento',
                    value: '${cancellationRate.toStringAsFixed(1)}%',
                    subtitle: 'Viagens canceladas no período',
                    icon: Icons.cancel_outlined,
                    color: Colors.redAccent,
                    delta: cancellationDelta,
                    isPercentage: true,
                    invertDeltaColor: true,
                  ),
                ),
                SizedBox(
                  width: cardWidth >= 220 ? cardWidth : constraints.maxWidth,
                  child: KpiCard(
                    title: 'Corridas Hoje',
                    value: ridesToday.toString(),
                    subtitle: 'Total desde a meia-noite',
                    icon: Icons.today_rounded,
                    color: Colors.orangeAccent,
                    delta: 0.0,
                    isPercentage: false,
                  ),
                ),
                SizedBox(
                  width: cardWidth >= 220 ? cardWidth : constraints.maxWidth,
                  child: KpiCard(
                    title: 'Motoristas Online',
                    value: '$activeDriversCount / $totalDrivers',
                    subtitle: 'Online / Cadastrados',
                    icon: Icons.drive_eta_rounded,
                    color: Colors.blueAccent,
                    delta: 0.0,
                    isPercentage: false,
                  ),
                ),
                SizedBox(
                  width: cardWidth >= 220 ? cardWidth : constraints.maxWidth,
                  child: KpiCard(
                    title: 'Passageiros Cadastrados',
                    value: registeredRiders.toString(),
                    subtitle: 'Total na base do Uppi',
                    icon: Icons.people_alt_rounded,
                    color: Colors.purpleAccent,
                    delta: 0.0,
                    isPercentage: false,
                  ),
                ),
                SizedBox(
                  width: cardWidth >= 220 ? cardWidth : constraints.maxWidth,
                  child: KpiCard(
                    title: 'Avaliação Média',
                    value: averageRating.toStringAsFixed(2),
                    subtitle: 'Média das avaliações do período',
                    icon: Icons.star_rounded,
                    color: Colors.amberAccent,
                    delta: 0.0,
                    isPercentage: false,
                  ),
                ),
                SizedBox(
                  width: cardWidth >= 220 ? cardWidth : constraints.maxWidth,
                  child: KpiCard(
                    title: 'Cadastros Pendentes',
                    value: pendingDriversCount.toString(),
                    subtitle: 'Aguardando aprovação',
                    icon: Icons.pending_actions_rounded,
                    color: Colors.orangeAccent,
                    delta: 0.0,
                    isPercentage: false,
                  ),
                ),
                SizedBox(
                  width: cardWidth >= 220 ? cardWidth : constraints.maxWidth,
                  child: KpiCard(
                    title: 'Saques Pendentes',
                    value: pendingPayoutsCount.toString(),
                    subtitle: 'Aguardando Pix',
                    icon: Icons.account_balance_wallet_rounded,
                    color: Colors.redAccent,
                    delta: 0.0,
                    isPercentage: false,
                  ),
                ),
                SizedBox(
                  width: cardWidth >= 220 ? cardWidth : constraints.maxWidth,
                  child: KpiCard(
                    title: 'Reclamações Ativas',
                    value: activeComplaintsCount.toString(),
                    subtitle: 'Abertas aguardando retorno',
                    icon: Icons.announcement_rounded,
                    color: Colors.purpleAccent,
                    delta: 0.0,
                    isPercentage: false,
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 32),

          // ATALHOS RÁPIDOS
          _buildQuickActionsPanel(context),
          const SizedBox(height: 32),

          // OPERAÇÕES EM TEMPO REAL - STATUS PULSANTE
          Text(
            'Monitor de Operações em Tempo Real',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final double widthFactor = constraints.maxWidth < 600 ? 2.0 : 4.0;
            final double cardWidth = (constraints.maxWidth - ((widthFactor - 1) * 16)) / widthFactor;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: LiveStatusCard(label: 'Procurando Motorista', value: searchingRides, color: Colors.orangeAccent),
                ),
                SizedBox(
                  width: cardWidth,
                  child: LiveStatusCard(label: 'Motorista a Caminho', value: arrivingRides, color: Colors.blueAccent),
                ),
                SizedBox(
                  width: cardWidth,
                  child: LiveStatusCard(label: 'Em Viagem', value: inProgressRides, color: Colors.greenAccent),
                ),
                SizedBox(
                  width: cardWidth,
                  child: LiveStatusCard(label: 'Aguardando Avaliação', value: waitingReviewRides, color: Colors.purpleAccent),
                ),
              ],
            );
          }),
          const SizedBox(height: 32),

          // GRÁFICOS LADO A LADO
          LayoutBuilder(builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 950;
            return isDesktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DashboardChartBox(
                          title: 'Volume de Corridas',
                          spots: weeklyRidesSpots,
                          color: Colors.blueAccent,
                          isCurrency: false,
                          chartLabels: chartLabels,
                          selectedPeriod: _selectedPeriod,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: DashboardChartBox(
                          title: 'Receita da Plataforma (R\$)',
                          spots: weeklyRevenueSpots,
                          color: Colors.greenAccent,
                          isCurrency: true,
                          chartLabels: chartLabels,
                          selectedPeriod: _selectedPeriod,
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      DashboardChartBox(
                        title: 'Volume de Corridas',
                        spots: weeklyRidesSpots,
                        color: Colors.blueAccent,
                        isCurrency: false,
                        chartLabels: chartLabels,
                        selectedPeriod: _selectedPeriod,
                      ),
                      const SizedBox(height: 24),
                      DashboardChartBox(
                        title: 'Receita da Plataforma (R\$)',
                        spots: weeklyRevenueSpots,
                        color: Colors.greenAccent,
                        isCurrency: true,
                        chartLabels: chartLabels,
                        selectedPeriod: _selectedPeriod,
                      ),
                    ],
                  );
          }),
          const SizedBox(height: 32),

          // TOP MOTORISTAS & ÚLTIMAS CORRIDAS & TEMPO REAL
          LayoutBuilder(builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 950;
            return isDesktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          children: [
                            TopDriversSection(
                              topDrivers: topDrivers,
                              onDriverTap: (dId) => _showDriverQuickDialog(context, dId),
                            ),
                            const SizedBox(height: 24),
                            _buildLiveReviewsSection(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            _buildLiveFeedSection(),
                            const SizedBox(height: 24),
                            _buildOnlineDriversSection(),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      TopDriversSection(
                        topDrivers: topDrivers,
                        onDriverTap: (dId) => _showDriverQuickDialog(context, dId),
                      ),
                      const SizedBox(height: 24),
                      _buildLiveFeedSection(),
                      const SizedBox(height: 24),
                      _buildLiveReviewsSection(),
                      const SizedBox(height: 24),
                      _buildOnlineDriversSection(),
                    ],
                  );
          }),
        ],
      ),
    );
  }

  // WIDGET FEED AO VIVO DE CORRIDAS
  Widget _buildLiveFeedSection() {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Últimas Corridas (Tempo Real)',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    PulsingIndicator(color: Colors.greenAccent),
                    SizedBox(width: 6),
                    Text('AO VIVO', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('rides')
                .stream(primaryKey: ['id'])
                .order('created_at', ascending: false)
                .limit(5),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SizedBox(height: 180, child: Center(child: Text('Erro ao carregar corridas: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent, fontSize: 12))));
              }
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final orders = snapshot.data ?? [];
              if (orders.isEmpty) {
                return const SizedBox(
                  height: 180,
                  child: Center(child: Text('Nenhuma corrida no momento.', style: TextStyle(color: Colors.white30))),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 16),
                itemBuilder: (context, index) {
                  final order = orders[index];
                  final fare = (order['fare'] as num?)?.toDouble() ?? 0.0;
                  final status = order['status'] as String? ?? 'searching';
                  final riderId = order['rider_id'] as String?;
                  final driverId = order['driver_id'] as String?;

                  // Disparar a busca de perfis de forma assíncrona se não estiver no cache
                  if (riderId != null && riderId.isNotEmpty) {
                    _fetchProfileName(riderId);
                  }
                  if (driverId != null && driverId.isNotEmpty) {
                    _fetchProfileName(driverId);
                  }

                  final riderName = riderId != null ? (_profileNamesCache[riderId] ?? 'Carregando...') : 'N/A';
                  final driverName = driverId != null ? (_profileNamesCache[driverId] ?? 'Carregando...') : 'Sem motorista';

                  final origin = order['origin'] as Map?;
                  final dest = order['destination'] as Map?;
                  final originAddress = origin != null ? (origin['address'] ?? 'Origem desconhecida') : 'Origem desconhecida';
                  final destAddress = dest != null ? (dest['address'] ?? 'Destino desconhecido') : 'Destino desconhecido';

                  Color statusColor = Colors.grey;
                  String statusText = 'Desconhecido';

                  switch (status) {
                    case 'requested':
                    case 'searching':
                      statusColor = Colors.orangeAccent;
                      statusText = 'Buscando';
                      break;
                    case 'accepted':
                    case 'driver_accepted':
                    case 'arrived':
                      statusColor = Colors.blueAccent;
                      statusText = 'A Caminho';
                      break;
                    case 'in_progress':
                      statusColor = Colors.greenAccent;
                      statusText = 'Em Viagem';
                      break;
                    case 'completed':
                      statusColor = Colors.tealAccent;
                      statusText = 'Finalizada';
                      break;
                    case 'rider_canceled':
                    case 'driver_canceled':
                    case 'canceled':
                      statusColor = Colors.redAccent;
                      statusText = 'Cancelada';
                      break;
                  }

                  return InkWell(
                    onTap: () => _showRideDetailsDialog(context, order),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            child: CircleAvatar(
                              backgroundColor: statusColor.withValues(alpha: 0.1),
                              radius: 18,
                              child: Icon(Icons.location_on, color: statusColor, size: 16),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Corrida #${order['id'].toString().substring(0, 8)}',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        statusText.toUpperCase(),
                                        style: TextStyle(
                                          color: statusColor,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                RichText(
                                  text: TextSpan(
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    children: [
                                      const TextSpan(text: 'Passageiro: ', style: TextStyle(color: Colors.white38)),
                                      TextSpan(text: riderName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      const TextSpan(text: '  |  ', style: TextStyle(color: Colors.white24)),
                                      const TextSpan(text: 'Motorista: ', style: TextStyle(color: Colors.white38)),
                                      TextSpan(text: driverName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.near_me_outlined, size: 12, color: Colors.white38),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        '$originAddress → $destAddress',
                                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'R\$ ${fare.toStringAsFixed(2)}',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              color: Colors.greenAccent,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // WIDGET AVALIAÇÕES EM TEMPO REAL
  Widget _buildLiveReviewsSection() {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Últimas Avaliações (Tempo Real)',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    PulsingIndicator(color: Colors.amberAccent),
                    SizedBox(width: 6),
                    Text('ATIVO', style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('reviews')
                .stream(primaryKey: ['id'])
                .order('created_at', ascending: false)
                .limit(5),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SizedBox(height: 150, child: Center(child: Text('Erro ao carregar avaliações: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent, fontSize: 12))));
              }
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const SizedBox(
                  height: 150,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final reviews = snapshot.data ?? [];
              if (reviews.isEmpty) {
                return const SizedBox(
                  height: 150,
                  child: Center(
                    child: Text('Nenhuma avaliação recente.', style: TextStyle(color: Colors.white38)),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: reviews.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 16),
                itemBuilder: (context, index) {
                  final review = reviews[index];
                  final rating = (review['rating'] as num?)?.toDouble() ?? 0.0;
                  final comment = review['comment'] ?? 'Sem comentário';
                  final reviewerId = review['reviewer_id'] as String?;
                  final reviewedId = review['reviewed_id'] as String?;

                  if (reviewerId != null && reviewerId.isNotEmpty) {
                    _fetchProfileName(reviewerId);
                  }
                  if (reviewedId != null && reviewedId.isNotEmpty) {
                    _fetchProfileName(reviewedId);
                  }

                  final reviewerName = reviewerId != null ? (_profileNamesCache[reviewerId] ?? 'Carregando...') : 'N/A';
                  final reviewedName = reviewedId != null ? (_profileNamesCache[reviewedId] ?? 'Carregando...') : 'N/A';

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: rating >= 4
                              ? Colors.greenAccent.withOpacity(0.1)
                              : rating == 3
                                  ? Colors.orangeAccent.withOpacity(0.1)
                                  : Colors.redAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, color: Colors.amberAccent, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              rating.toStringAsFixed(1),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: rating >= 4
                                    ? Colors.greenAccent
                                    : rating == 3
                                        ? Colors.orangeAccent
                                        : Colors.redAccent,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              comment,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontStyle: FontStyle.italic),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$reviewerName avaliou $reviewedName',
                              style: const TextStyle(color: Colors.white30, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // WIDGET MOTORISTAS ONLINE AGORA
  Widget _buildOnlineDriversSection() {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Motoristas Online Agora',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    PulsingIndicator(color: Colors.greenAccent),
                    SizedBox(width: 6),
                    Text('MONITORANDO', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('profiles')
                .stream(primaryKey: ['id'])
                .eq('role', 'driver'),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SizedBox(height: 150, child: Center(child: Text('Erro ao carregar motoristas: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent, fontSize: 12))));
              }
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const SizedBox(
                  height: 150,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final allDrivers = snapshot.data ?? [];
              final onlineDrivers = allDrivers
                  .where((d) => d['status'] == 'online' || d['status'] == 'in_progress')
                  .toList();

              if (onlineDrivers.isEmpty) {
                return const SizedBox(
                  height: 150,
                  child: Center(
                    child: Text('Nenhum motorista online no momento.', style: TextStyle(color: Colors.white38)),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: onlineDrivers.length > 5 ? 5 : onlineDrivers.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 16),
                itemBuilder: (context, index) {
                  final driver = onlineDrivers[index];
                  final name = driver['full_name'] ?? driver['name'] ?? 'Motorista sem nome';
                  final phone = driver['phone_number'] ?? 'Sem telefone';
                  final status = driver['status'] as String? ?? 'online';
                  final isBusy = status == 'in_progress';

                  return InkWell(
                    onTap: () => _showDriverQuickDialog(context, driver['id'].toString()),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.white10,
                                child: Icon(Icons.person, color: isBusy ? Colors.orangeAccent : Colors.greenAccent),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: isBusy ? Colors.orange : Colors.green,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFF1E293B), width: 2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  phone,
                                  style: const TextStyle(color: Colors.white30, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (isBusy ? Colors.orangeAccent : Colors.greenAccent).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isBusy ? 'EM CORRIDA' : 'DISPONÍVEL',
                              style: TextStyle(
                                color: isBusy ? Colors.orangeAccent : Colors.greenAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // WIDGET ATALHOS RÁPIDOS
  Widget _buildQuickActionsPanel(BuildContext context) {
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
          Row(
            children: [
              const Icon(Icons.flash_on, color: Colors.orangeAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Ações e Atalhos Rápidos',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final bool isNarrow = constraints.maxWidth < 600;
            if (isNarrow) {
              return Column(
                children: [
                  _buildQuickActionButton(
                    context,
                    icon: Icons.verified_user_rounded,
                    label: 'Aprovar Próximo KYC',
                    subtitle: 'Aprova o primeiro motorista pendente',
                    color: Colors.blueAccent,
                    onTap: () => _approveNextKyc(context),
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    context,
                    icon: Icons.local_activity_rounded,
                    label: 'Criar Cupom Relâmpago',
                    subtitle: 'Gera cupom de desconto de 15%',
                    color: Colors.purpleAccent,
                    onTap: () => _showQuickCouponDialog(context),
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    context,
                    icon: Icons.campaign_rounded,
                    label: 'Comunicado Global',
                    subtitle: 'Envia mensagem para todos os apps',
                    color: Colors.orangeAccent,
                    onTap: () => _showQuickAnnouncementDialog(context),
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  child: _buildQuickActionButton(
                    context,
                    icon: Icons.verified_user_rounded,
                    label: 'Aprovar Próximo KYC',
                    subtitle: 'Aprova o primeiro motorista pendente',
                    color: Colors.blueAccent,
                    onTap: () => _approveNextKyc(context),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildQuickActionButton(
                    context,
                    icon: Icons.local_activity_rounded,
                    label: 'Criar Cupom Relâmpago',
                    subtitle: 'Gera cupom de desconto de 15%',
                    color: Colors.purpleAccent,
                    onTap: () => _showQuickCouponDialog(context),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildQuickActionButton(
                    context,
                    icon: Icons.campaign_rounded,
                    label: 'Comunicado Global',
                    subtitle: 'Envia mensagem para todos os apps',
                    color: Colors.orangeAccent,
                    onTap: () => _showQuickAnnouncementDialog(context),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approveNextKyc(BuildContext context) async {
    try {
      final client = Supabase.instance.client;
      final nextPending = await client
          .from('profiles')
          .select('id, full_name')
          .eq('role', 'driver')
          .eq('is_approved', false)
          .neq('status', 'blocked')
          .order('created_at', ascending: true)
          .limit(1)
          .maybeSingle();

      if (nextPending == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nenhum motorista pendente de aprovação no momento.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      await client.from('profiles').update({
        'is_approved': true,
        'status': 'offline',
      }).eq('id', nextPending['id']);

      final adminId = client.auth.currentUser?.id ?? 'UNKNOWN';
      await client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'driver_approved_dashboard',
        'target_user_id': nextPending['id'],
        'details': {'driver_name': nextPending['full_name']},
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Motorista ${nextPending['full_name']} aprovado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao aprovar motorista: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showQuickCouponDialog(BuildContext context) async {
    final codeCtrl = TextEditingController();
    final discountCtrl = TextEditingController(text: '15');
    
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Row(
            children: [
              Icon(Icons.local_activity, color: Colors.purpleAccent),
              SizedBox(width: 8),
              Text('Criar Cupom Relâmpago', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Código do Cupom (ex: RELAMPAGO15)',
                  labelStyle: TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: discountCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Desconto (%)',
                  labelStyle: TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent),
              onPressed: () async {
                final code = codeCtrl.text.trim().toUpperCase();
                final discount = double.tryParse(discountCtrl.text) ?? 15.0;
                if (code.isEmpty) return;

                try {
                  final client = Supabase.instance.client;
                  final data = {
                    'code': code,
                    'discount': discount,
                    'discount_type': 'percent',
                    'minimum_order': 0.0,
                    'is_active': true,
                    'expire_at': DateTime.now().add(const Duration(days: 7)).toIso8601String(),
                  };
                  await client.from('coupons').insert(data);

                  final adminId = client.auth.currentUser?.id ?? 'UNKNOWN';
                  await client.from('admin_audit_log').insert({
                    'admin_id': adminId,
                    'action_type': 'coupon_created_dashboard',
                    'details': data,
                  });

                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Cupom $code de $discount% criado com sucesso!'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao criar cupom: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Criar Cupom', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showQuickAnnouncementDialog(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Row(
            children: [
              Icon(Icons.campaign, color: Colors.orangeAccent),
              SizedBox(width: 8),
              Text('Enviar Comunicado Global', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Título do Comunicado',
                  labelStyle: TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionCtrl,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Descrição/Mensagem',
                  labelStyle: TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
              onPressed: () async {
                final title = titleCtrl.text.trim();
                final desc = descriptionCtrl.text.trim();
                if (title.isEmpty || desc.isEmpty) return;

                try {
                  final client = Supabase.instance.client;
                  final data = {
                    'title': title,
                    'description': desc,
                    'start_at': DateTime.now().toIso8601String(),
                  };
                  await client.from('announcements').insert(data);

                  final adminId = client.auth.currentUser?.id ?? 'UNKNOWN';
                  await client.from('admin_audit_log').insert({
                    'admin_id': adminId,
                    'action_type': 'announcement_created_dashboard',
                    'details': data,
                  });

                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Comunicado Global enviado com sucesso!'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao enviar comunicado: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Enviar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDriverQuickDialog(BuildContext context, String driverId) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            width: 550,
            padding: const EdgeInsets.all(32),
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('profiles')
                  .stream(primaryKey: ['id'])
                  .eq('id', driverId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SizedBox(height: 250, child: Center(child: Text('Erro: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent, fontSize: 12))));
                }
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const SizedBox(
                    height: 250,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final list = snapshot.data ?? [];
                if (list.isEmpty) {
                  return const SizedBox(
                    height: 100,
                    child: Center(
                      child: Text('Motorista não encontrado.', style: TextStyle(color: Colors.white70)),
                    ),
                  );
                }
                final driver = list.first;
                final name = driver['full_name'] ?? driver['name'] ?? 'Motorista';
                final phone = driver['phone_number'] ?? 'Sem telefone';
                final email = driver['email'] ?? 'Sem email';
                final rating = (driver['average_rating'] as num?)?.toDouble() ?? 5.0;
                final status = driver['status'] as String? ?? 'offline';
                final isBlocked = status == 'blocked';

                final exemptRaw = driver['commission_exempt_until'];
                final commissionExemptUntil = exemptRaw != null ? DateTime.tryParse(exemptRaw.toString()) : null;
                final isExempt = commissionExemptUntil != null && commissionExemptUntil.isAfter(DateTime.now());

                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.white10,
                            radius: 24,
                            child: Icon(Icons.person, color: isBlocked ? Colors.redAccent : Colors.greenAccent, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  phone,
                                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Divider(color: Colors.white10),
                      const SizedBox(height: 16),

                      // Detalhes & Contato
                      const Text('DADOS DO MOTORISTA', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 12),
                      _buildDriverInfoRow('Email', email),
                      _buildDriverInfoRow('Status Atual', isBlocked ? 'BLOQUEADO' : (status == 'in_progress' ? 'EM CORRIDA' : status.toUpperCase())),
                      _buildDriverInfoRow('Avaliação Média', '${rating.toStringAsFixed(2)} ⭐'),
                      const SizedBox(height: 24),

                      // Corridas por período
                      const Text('DESEMPENHO POR PERÍODO (COMPLETADAS)', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 12),
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: Supabase.instance.client
                            .from('rides')
                            .stream(primaryKey: ['id'])
                            .eq('driver_id', driverId),
                        builder: (context, ridesSnap) {
                          if (!ridesSnap.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final rides = ridesSnap.data ?? [];
                          
                          final now = DateTime.now();
                          final todayStart = DateTime(now.year, now.month, now.day);
                          final weekStart = now.subtract(const Duration(days: 7));
                          final monthStart = DateTime(now.year, now.month, 1);

                          int today = 0;
                          int week = 0;
                          int month = 0;

                          for (var r in rides) {
                            final rStatus = r['status'] as String?;
                            if (rStatus == 'completed' || rStatus == 'finished') {
                              final createdAt = r['created_at'];
                              if (createdAt != null) {
                                final date = DateTime.tryParse(createdAt.toString());
                                if (date != null) {
                                  if (date.isAfter(todayStart)) today++;
                                  if (date.isAfter(weekStart)) week++;
                                  if (date.isAfter(monthStart)) month++;
                                }
                              }
                            }
                          }

                          return Row(
                            children: [
                              Expanded(child: _DashboardStatChip('Hoje', '$today', Colors.tealAccent)),
                              const SizedBox(width: 12),
                              Expanded(child: _DashboardStatChip('Semana', '$week', Colors.tealAccent)),
                              const SizedBox(width: 12),
                              Expanded(child: _DashboardStatChip('Mês', '$month', Colors.tealAccent)),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      const Divider(color: Colors.white10),
                      const SizedBox(height: 16),

                      // Ações rápidas
                      const Text('AÇÕES DE GERENCIAMENTO', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isBlocked ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                                foregroundColor: isBlocked ? Colors.greenAccent : Colors.redAccent,
                                side: BorderSide(color: isBlocked ? Colors.green : Colors.red),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              onPressed: () async {
                                final nextStatus = isBlocked ? 'offline' : 'blocked';
                                await Supabase.instance.client
                                    .from('profiles')
                                    .update({'status': nextStatus})
                                    .eq('id', driverId);

                                final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
                                await Supabase.instance.client.from('admin_audit_log').insert({
                                  'admin_id': adminId,
                                  'action_type': 'driver_status_change_dashboard',
                                  'target_user_id': driverId,
                                  'details': {'new_status': nextStatus},
                                });
                              },
                              icon: Icon(isBlocked ? Icons.check_circle : Icons.block),
                              label: Text(isBlocked ? 'Desbloquear' : 'Bloquear'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isExempt ? Colors.grey.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2),
                                foregroundColor: isExempt ? Colors.white70 : Colors.greenAccent,
                                side: BorderSide(color: isExempt ? Colors.white24 : Colors.green),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              onPressed: () async {
                                final date = isExempt ? null : DateTime.now().add(const Duration(days: 30));
                                await Supabase.instance.client
                                    .from('profiles')
                                    .update({'commission_exempt_until': date?.toIso8601String()})
                                    .eq('id', driverId);

                                final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
                                await Supabase.instance.client.from('admin_audit_log').insert({
                                  'admin_id': adminId,
                                  'action_type': 'driver_commission_exempt_dashboard',
                                  'target_user_id': driverId,
                                  'details': {'exempt_until': date?.toIso8601String()},
                                });
                              },
                              icon: Icon(isExempt ? Icons.money_off : Icons.monetization_on),
                              label: Text(isExempt ? 'Taxar Novamente' : 'Zero Taxa 30d'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildDriverInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _showRideDetailsDialog(BuildContext context, Map<String, dynamic> ride) async {
    final fare = (ride['fare'] as num?)?.toDouble() ?? 0.0;
    final platformFee = (ride['platform_fee'] as num?)?.toDouble() ?? 0.0;
    final driverPayout = fare - platformFee;
    final status = ride['status'] as String? ?? 'requested';
    final riderId = ride['rider_id'] as String?;
    final driverId = ride['driver_id'] as String?;

    final riderName = riderId != null ? (_profileNamesCache[riderId] ?? 'Carregando...') : 'N/A';
    final driverName = driverId != null ? (_profileNamesCache[driverId] ?? 'Carregando...') : 'Sem motorista';

    final origin = ride['origin'] as Map?;
    final dest = ride['destination'] as Map?;
    final originAddress = origin != null ? (origin['address'] ?? 'Origem desconhecida') : 'Origem desconhecida';
    final destAddress = dest != null ? (dest['address'] ?? 'Destino desconhecido') : 'Destino desconhecido';

    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            width: 600,
            padding: const EdgeInsets.all(32),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Corrida #${ride['id'].toString().substring(0, 8)}',
                        style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 16),

                  // Linha do tempo de status
                  const Text('LINHA DO TEMPO DO STATUS', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildTimelineStep('Solicitada', _isPastOrEqual(status, 'requested')),
                      _buildTimelineLine(_isPastOrEqual(status, 'accepted')),
                      _buildTimelineStep('No Local', _isPastOrEqual(status, 'arrived')),
                      _buildTimelineLine(_isPastOrEqual(status, 'in_progress')),
                      _buildTimelineStep('Viagem', _isPastOrEqual(status, 'in_progress')),
                      _buildTimelineLine(_isPastOrEqual(status, 'completed')),
                      _buildTimelineStep(
                        status.contains('canceled') ? 'Cancelada' : 'Finalizada',
                        _isPastOrEqual(status, 'completed') || status.contains('canceled'),
                        color: status.contains('canceled') ? Colors.redAccent : Colors.tealAccent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 16),

                  // Info
                  const Text('DETALHES DA CORRIDA', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 12),
                  _buildDriverInfoRow('Passageiro', riderName),
                  _buildDriverInfoRow('Motorista', driverName),
                  _buildDriverInfoRow('Origem', originAddress),
                  _buildDriverInfoRow('Destino', destAddress),
                  const SizedBox(height: 24),

                  // Finanças
                  const Text('DETALHAMENTO FINANCEIRO', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 12),
                  _buildDriverInfoRow('Tarifa Total', 'R\$ ${fare.toStringAsFixed(2)}'),
                  _buildDriverInfoRow('Taxa Plataforma', 'R\$ ${platformFee.toStringAsFixed(2)}'),
                  _buildDriverInfoRow('Repasse Líquido', 'R\$ ${driverPayout.toStringAsFixed(2)}'),
                  const SizedBox(height: 24),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 16),

                  // Chat ao vivo
                  const Text('CHAT AO VIVO (COMUNICAÇÃO)', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 12),
                  Container(
                    height: 220,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: Supabase.instance.client
                          .from('ride_messages')
                          .stream(primaryKey: ['id'])
                          .eq('ride_id', ride['id']),
                      builder: (context, chatSnapshot) {
                        if (chatSnapshot.hasError) {
                          return Center(child: Text('Erro no chat: ${chatSnapshot.error}', style: const TextStyle(color: Colors.redAccent, fontSize: 12)));
                        }
                        if (!chatSnapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final msgs = chatSnapshot.data ?? [];
                        
                        // Sort by date client-side
                        msgs.sort((a, b) => (a['created_at'] ?? '').toString().compareTo((b['created_at'] ?? '').toString()));

                        if (msgs.isEmpty) {
                          return const Center(
                            child: Text('Nenhuma mensagem trocada no chat.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                          );
                        }

                        return ListView.builder(
                          itemCount: msgs.length,
                          itemBuilder: (context, idx) {
                            final m = msgs[idx];
                            final content = m['content'] ?? m['message'] ?? '';
                            final senderId = m['sender_id'] as String?;
                            final isDriver = senderId == driverId;

                            return Align(
                              alignment: isDriver ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDriver ? Colors.indigo.withValues(alpha: 0.2) : Colors.teal.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isDriver ? Colors.indigo : Colors.teal, width: 0.5),
                                ),
                                child: Column(
                                  crossAxisAlignment: isDriver ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isDriver ? 'Motorista' : 'Passageiro',
                                      style: TextStyle(fontSize: 10, color: isDriver ? Colors.indigoAccent : Colors.tealAccent, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      content.toString(),
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _isPastOrEqual(String current, String target) {
    final list = ['requested', 'searching', 'accepted', 'driver_accepted', 'arrived', 'in_progress', 'completed', 'finished'];
    final curIdx = list.indexOf(current);
    final tgtIdx = list.indexOf(target);
    if (curIdx == -1 || tgtIdx == -1) return false;
    return curIdx >= tgtIdx;
  }

  Widget _buildTimelineStep(String label, bool isDone, {Color color = Colors.blueAccent}) {
    return Column(
      children: [
        CircleAvatar(
          radius: 8,
          backgroundColor: isDone ? color : Colors.white10,
          child: isDone ? const Icon(Icons.check, size: 10, color: Colors.black) : null,
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: isDone ? color : Colors.white38,
            fontSize: 9,
            fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineLine(bool isDone) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 16),
        color: isDone ? Colors.blueAccent : Colors.white10,
      ),
    );
  }
}

class _DashboardStatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _DashboardStatChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

