import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:ionicons/ionicons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';

class UppiClubPanel extends StatefulWidget {
  const UppiClubPanel({super.key});

  @override
  State<UppiClubPanel> createState() => _UppiClubPanelState();
}

class _UppiClubPanelState extends State<UppiClubPanel> {
  int _completedRidesCount = 0;
  bool _isLoading = true;
  bool _isPremium = false;
  RealtimeChannel? _clubRidesChannel;

  @override
  void initState() {
    super.initState();
    _fetchCompletedRides();
    _startRidesListener();
  }

  Future<void> _loadPremiumStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _isPremium = prefs.getBool('uppi_club_premium') ?? false;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchCompletedRides() async {
    try {
      await _loadPremiumStatus();
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      final result = await Supabase.instance.client
          .from('rides')
          .select('id')
          .eq('rider_id', uid)
          .inFilter('status', ['completed', 'finished']);

      if (mounted) {
        setState(() {
          _completedRidesCount = result.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao buscar contagem do Uppi Club: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startRidesListener() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    _clubRidesChannel = Supabase.instance.client
        .channel('rider_club_rides_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rides',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'rider_id',
            value: uid,
          ),
          callback: (payload) {
            _fetchCompletedRides();
          },
        );

    try {
      _clubRidesChannel!.subscribe();
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_clubRidesChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_clubRidesChannel!);
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.0,
            color: ColorPalette.primary40,
          ),
        ),
      );
    }

    // Tiers de fidelidade
    String tierName = 'Bronze';
    String tierDescription = 'Viaje mais para desbloquear bônus!';
    int nextTierTarget = 5;
    double progress = 0.0;

    if (_isPremium) {
      tierName = 'Ouro Premium';
      tierDescription = '👑 VIP Ativo: 10% de cashback e prioridade!';
      nextTierTarget = 15;
      progress = 1.0;
    } else if (_completedRidesCount >= 15) {
      tierName = 'Ouro';
      tierDescription = '👑 Benefício VIP: 10% de cashback e prioridade!';
      nextTierTarget = 15; // Max tier reached
      progress = 1.0;
    } else if (_completedRidesCount >= 5) {
      tierName = 'Prata';
      tierDescription = '⭐ Benefício ativo: 5% de desconto nas viagens!';
      nextTierTarget = 15;
      progress = ((_completedRidesCount - 5) / (15 - 5)).clamp(0.0, 1.0);
    } else {
      tierName = 'Bronze';
      tierDescription = 'Complete 5 corridas para virar Prata!';
      nextTierTarget = 5;
      progress = (_completedRidesCount / 5).clamp(0.0, 1.0);
    }

    final isMaxTier = tierName == 'Ouro' || tierName == 'Ouro Premium';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ColorPalette.neutralVariant99,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ColorPalette.neutral90),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff64748B).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: ColorPalette.primary95,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Ionicons.ribbon_outline,
                  color: ColorPalette.primary40,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Uppi Club',
                          style: context.titleSmall?.copyWith(
                            color: ColorPalette.neutral10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: ColorPalette.primary40,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Nível $tierName',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tierDescription,
                      style: context.bodySmall?.copyWith(
                        color: ColorPalette.primary30,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: ColorPalette.neutral90,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      ColorPalette.primary40,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                isMaxTier 
                    ? '$_completedRidesCount viagens'
                    : '$_completedRidesCount/$nextTierTarget',
                style: context.labelMedium?.copyWith(
                  color: ColorPalette.neutral20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
