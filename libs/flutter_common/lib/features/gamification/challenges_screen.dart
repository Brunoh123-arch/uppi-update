import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/extensions/extensions.dart';

/// Tela de desafios ativos para o motorista — padrão Uppi
class ChallengesScreen extends StatefulWidget {
  const ChallengesScreen({super.key});

  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  List<ChallengeData> challenges = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChallenges();
  }

  Future<void> _loadChallenges() async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'get-active-challenges',
      );

      final raw = response.data['challenges'] as List<dynamic>? ?? [];
      setState(() {
        challenges = raw.map((c) => ChallengeData.fromMap(c)).toList();
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorPalette.neutral95,
      appBar: AppBar(
        title: Text('Desafios Uppi', style: context.titleMedium),
        centerTitle: true,
        elevation: 0,
        backgroundColor: ColorPalette.neutralVariant99,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(
            Ionicons.chevron_back,
            color: ColorPalette.neutral20,
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : challenges.isEmpty
          ? _buildEmptyState(context)
          : RefreshIndicator(
              color: ColorPalette.primary50,
              onRefresh: _loadChallenges,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: challenges.length,
                itemBuilder: (context, index) {
                  return ChallengeCard(challenge: challenges[index]);
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: ColorPalette.secondary95,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Ionicons.trophy_outline,
              size: 48,
              color: ColorPalette.secondary40,
            ),
          ),
          const SizedBox(height: 16),
          Text('Nenhum desafio ativo', style: context.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Novos desafios serão lançados em breve!',
            style: context.bodyMedium?.copyWith(
              color: ColorPalette.neutralVariant50,
            ),
          ),
        ],
      ),
    );
  }
}

/// Card individual de desafio — padrão visual Uppi (borderRadius 16, shadows)
class ChallengeCard extends StatelessWidget {
  final ChallengeData challenge;

  const ChallengeCard({super.key, required this.challenge});

  @override
  Widget build(BuildContext context) {
    final progress = challenge.goal > 0
        ? (challenge.currentProgress / challenge.goal).clamp(0.0, 1.0)
        : 0.0;
    final isCompleted = challenge.currentProgress >= challenge.goal;
    final remaining = challenge.goal - challenge.currentProgress;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isCompleted
            ? ColorPalette.semanticgreen50
            : ColorPalette.neutralVariant99,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isCompleted
                ? ColorPalette.semanticgreen50.withValues(alpha: 0.25)
                : const Color(0x3F0E275D),
            blurRadius: isCompleted ? 12 : 20,
            offset: const Offset(2, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: isCompleted
                        ? null
                        : Border.all(color: ColorPalette.neutral90),
                    color: isCompleted
                        ? Colors.white.withValues(alpha: 0.2)
                        : null,
                  ),
                  child: Icon(
                    _getChallengeIcon(),
                    color: isCompleted
                        ? Colors.white
                        : ColorPalette.secondary40,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        challenge.title,
                        style: context.labelLarge?.copyWith(
                          color: isCompleted ? Colors.white : null,
                        ),
                      ),
                      Text(
                        challenge.description,
                        style: context.bodySmall?.copyWith(
                          color: isCompleted
                              ? Colors.white70
                              : ColorPalette.neutralVariant50,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCompleted)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '✅ Completo',
                      style: context.labelSmall?.copyWith(
                        color: ColorPalette.semanticgreen50,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Barra de progresso
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: isCompleted
                    ? Colors.white.withValues(alpha: 0.2)
                    : ColorPalette.neutral90,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isCompleted ? Colors.white : ColorPalette.semanticgreen60,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Progresso numérico
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${challenge.currentProgress}/${challenge.goal} corridas',
                  style: context.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isCompleted ? Colors.white : null,
                  ),
                ),
                if (!isCompleted)
                  Text(
                    'Faltam $remaining',
                    style: context.bodySmall?.copyWith(
                      color: ColorPalette.neutralVariant50,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Recompensa
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isCompleted
                    ? Colors.white.withValues(alpha: 0.15)
                    : ColorPalette.primary95,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Ionicons.gift,
                    size: 18,
                    color: isCompleted ? Colors.white : ColorPalette.primary30,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recompensa: ${challenge.rewardLabel}',
                      style: context.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isCompleted
                            ? Colors.white
                            : ColorPalette.primary30,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tempo restante
            if (challenge.endsAt != null && !isCompleted) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Ionicons.time_outline,
                    size: 14,
                    color: ColorPalette.neutralVariant50,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatTimeRemaining(challenge.endsAt!),
                    style: context.bodySmall?.copyWith(
                      color: ColorPalette.neutralVariant50,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getChallengeIcon() {
    switch (challenge.rewardType) {
      case 'commissionExemption':
        return Ionicons.cash_outline;
      case 'walletBonus':
        return Ionicons.wallet_outline;
      case 'priorityQueue':
        return Ionicons.flash_outline;
      case 'badge':
        return Ionicons.medal_outline;
      default:
        return Ionicons.trophy_outline;
    }
  }

  String _formatTimeRemaining(DateTime endsAt) {
    final diff = endsAt.difference(DateTime.now());
    if (diff.isNegative) return 'Expirado';
    if (diff.inDays > 0) {
      return 'Termina em ${diff.inDays}d ${diff.inHours % 24}h';
    }
    if (diff.inHours > 0) {
      return 'Termina em ${diff.inHours}h ${diff.inMinutes % 60}min';
    }
    return 'Termina em ${diff.inMinutes}min';
  }
}

/// Mini card de desafio para drawer/sidebar — padrão Uppi
class ChallengeMiniCard extends StatelessWidget {
  final ChallengeData challenge;
  final VoidCallback? onTap;

  const ChallengeMiniCard({super.key, required this.challenge, this.onTap});

  @override
  Widget build(BuildContext context) {
    final progress = challenge.goal > 0
        ? (challenge.currentProgress / challenge.goal).clamp(0.0, 1.0)
        : 0.0;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ColorPalette.secondary99,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ColorPalette.secondary90),
        ),
        child: Row(
          children: [
            const Icon(
              Ionicons.trophy,
              color: ColorPalette.secondary40,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    challenge.title,
                    style: context.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: ColorPalette.secondary95,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        ColorPalette.secondary40,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${challenge.currentProgress}/${challenge.goal}',
              style: context.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: ColorPalette.secondary40,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modelo de dados do desafio
class ChallengeData {
  final String id;
  final String title;
  final String description;
  final int goal;
  final int currentProgress;
  final String rewardType;
  final String rewardLabel;
  final DateTime? endsAt;
  final bool completed;

  ChallengeData({
    required this.id,
    required this.title,
    required this.description,
    required this.goal,
    required this.currentProgress,
    required this.rewardType,
    required this.rewardLabel,
    this.endsAt,
    this.completed = false,
  });

  factory ChallengeData.fromMap(dynamic data) {
    final map = data as Map<String, dynamic>;

    // O backend envia 'target' como meta e 'rewardDescription' como label
    final goalValue =
        (map['target'] as num?)?.toInt() ?? (map['goal'] as num?)?.toInt() ?? 0;

    final progressValue =
        (map['progress'] as num?)?.toInt() ??
        (map['currentProgress'] as num?)?.toInt() ??
        0;

    final rewardLabelValue =
        map['rewardDescription'] as String? ??
        map['rewardLabel'] as String? ??
        '';

    // Timestamp pode vir como ISO string ou milissegundos
    DateTime? endsAt;
    final endsAtRaw = map['periodEndAt'] ?? map['endsAt'];
    if (endsAtRaw is String) {
      endsAt = DateTime.tryParse(endsAtRaw);
    } else if (endsAtRaw is int) {
      endsAt = DateTime.fromMillisecondsSinceEpoch(endsAtRaw);
    } else if (endsAtRaw is Map) {
      // Firestore Timestamp serializado: {_seconds: X, _nanoseconds: Y}
      final seconds = (endsAtRaw['_seconds'] as num?)?.toInt();
      if (seconds != null)
        endsAt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    }

    return ChallengeData(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? 'Desafio',
      description: map['description'] as String? ?? '',
      goal: goalValue,
      currentProgress: progressValue,
      rewardType: map['rewardType'] as String? ?? 'walletBonus',
      rewardLabel: rewardLabelValue,
      endsAt: endsAt,
      completed: map['completed'] as bool? ?? false,
    );
  }
}
