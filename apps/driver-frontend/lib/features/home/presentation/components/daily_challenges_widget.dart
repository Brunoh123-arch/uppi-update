import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:ionicons/ionicons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';

class DailyChallengesWidget extends StatefulWidget {
  const DailyChallengesWidget({super.key});

  @override
  State<DailyChallengesWidget> createState() => _DailyChallengesWidgetState();
}

class _DailyChallengesWidgetState extends State<DailyChallengesWidget> {
  int _completedRides = 0;
  bool _isLoading = true;
  RealtimeChannel? _ridesChannel;
  static const int _targetRides = 5;
  static const double _bonusAmount = 25.0;

  @override
  void initState() {
    super.initState();
    _fetchCompletedRidesToday();
    _startRidesListener();
  }

  Future<void> _fetchCompletedRidesToday() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      // Cria a data de início do dia local e converte para UTC com offset correto (ex: 2026-06-10T03:00:00.000Z)
      final now = DateTime.now();
      final localStartOfDay = DateTime(now.year, now.month, now.day);
      final startOfDayUtc = localStartOfDay.toUtc().toIso8601String();
      
      final result = await Supabase.instance.client
          .from('rides')
          .select('id')
          .eq('driver_id', uid)
          .inFilter('status', ['completed', 'finished', 'waiting_for_review'])
          .gte('created_at', startOfDayUtc);

      if (mounted) {
        setState(() {
          _completedRides = result.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao buscar progresso do desafio: $e");
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

    _ridesChannel = Supabase.instance.client
        .channel('driver_rides_challenges_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rides',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: uid,
          ),
          callback: (payload) {
            _fetchCompletedRidesToday();
          },
        );

    try {
      _ridesChannel!.subscribe();
    } catch (e) {
      debugPrint("Erro ao assinar canal de metas: $e");
    }
  }

  @override
  void dispose() {
    if (_ridesChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_ridesChannel!);
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

    final isCompleted = _completedRides >= _targetRides;
    final progressFraction = (_completedRides / _targetRides).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ColorPalette.neutralVariant99,
        borderRadius: BorderRadius.circular(16),
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
                  color: ColorPalette.primary95, // Azul suave padrão
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCompleted ? Ionicons.trophy : Ionicons.trophy_outline,
                  color: ColorPalette.primary40, // Azul oficial Uppi
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.translate.dailyChallengeTitle,
                      style: context.titleSmall?.copyWith(
                        color: ColorPalette.neutral10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isCompleted
                          ? context.translate.dailyChallengeCompleted((_bonusAmount).toStringAsFixed(2))
                          : context.translate.dailyChallengeSubtitle(_targetRides.toString(), (_bonusAmount).toStringAsFixed(2)),
                      style: context.bodySmall?.copyWith(
                        color: isCompleted 
                            ? ColorPalette.primary30 // Azul escuro premium Uppi
                            : ColorPalette.neutral40,
                        fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progressFraction,
                    minHeight: 8,
                    backgroundColor: ColorPalette.neutral90,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      ColorPalette.primary40, // Sempre azul oficial do Uppi
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$_completedRides/$_targetRides',
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
