import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:ionicons/ionicons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';

class UppiClubBottomSheet extends StatefulWidget {
  const UppiClubBottomSheet({super.key});

  @override
  State<UppiClubBottomSheet> createState() => _UppiClubBottomSheetState();
}

class _UppiClubBottomSheetState extends State<UppiClubBottomSheet> {
  int _completedRidesCount = 0;
  bool _isLoading = true;
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _loadPremiumStatus();
    _fetchCompletedRides();
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

  Future<void> _togglePremiumStatus(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('uppi_club_premium', value);
      if (mounted) {
        setState(() {
          _isPremium = value;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchCompletedRides() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

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
      debugPrint("Erro ao buscar contagem do Uppi Club para o bottom sheet: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tiers de fidelidade
    String tierName = 'Bronze';
    String tierDescription = 'Viaje mais para desbloquear bônus!';
    int nextTierTarget = 5;
    double progress = 0.0;
    Color tierColor = const Color(0xffCD7F32); // Bronze
    IconData tierIcon = Ionicons.medal_outline;

    if (_isPremium) {
      tierName = 'Ouro Premium';
      tierDescription = '👑 VIP Ativo: 10% de cashback e prioridade máxima!';
      nextTierTarget = 15;
      progress = 1.0;
      tierColor = const Color(0xffFFD700); // Ouro
      tierIcon = Ionicons.trophy;
    } else if (_completedRidesCount >= 15) {
      tierName = 'Ouro';
      tierDescription = '👑 Benefício VIP: 10% de cashback e prioridade!';
      nextTierTarget = 15;
      progress = 1.0;
      tierColor = const Color(0xffFFD700); // Ouro
      tierIcon = Ionicons.trophy;
    } else if (_completedRidesCount >= 5) {
      tierName = 'Prata';
      tierDescription = '⭐ Benefício ativo: 5% de desconto nas viagens!';
      nextTierTarget = 15;
      progress = ((_completedRidesCount - 5) / (15 - 5)).clamp(0.0, 1.0);
      tierColor = const Color(0xffC0C0C0); // Prata
      tierIcon = Ionicons.ribbon;
    } else {
      tierName = 'Bronze';
      tierDescription = 'Complete 5 corridas para virar Prata!';
      nextTierTarget = 5;
      progress = (_completedRidesCount / 5).clamp(0.0, 1.0);
      tierColor = const Color(0xffCD7F32); // Bronze
      tierIcon = Ionicons.medal_outline;
    }

    final isMaxTier = tierName == 'Ouro' || tierName == 'Ouro Premium';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.only(top: 10, left: 24, right: 24, bottom: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle de arraste superior
          Center(
            child: Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: ColorPalette.neutral90,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Título principal do Uppi Club
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Ionicons.ribbon,
                color: ColorPalette.primary40,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(
                'Uppi Club',
                style: context.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: ColorPalette.neutral10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Seu programa de vantagens exclusivo no Uppi',
            textAlign: TextAlign.center,
            style: context.bodyMedium?.copyWith(
              color: ColorPalette.neutralVariant50,
            ),
          ),
          const SizedBox(height: 28),

          // Card de Status Atual do Usuário
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  tierColor.withValues(alpha: 0.15),
                  tierColor.withValues(alpha: 0.03),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: tierColor.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 80,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.0,
                        color: ColorPalette.primary40,
                      ),
                    ),
                  )
                : Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: tierColor.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  tierIcon,
                                  color: tierColor,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Nível Atual',
                                    style: context.labelSmall?.copyWith(
                                      color: ColorPalette.neutralVariant40,
                                    ),
                                  ),
                                  Text(
                                    tierName,
                                    style: context.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: ColorPalette.neutral10,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: ColorPalette.neutralVariant99,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: ColorPalette.neutral90),
                            ),
                            child: Text(
                              isMaxTier
                                  ? '$_completedRidesCount viagens'
                                  : '$_completedRidesCount/$nextTierTarget',
                              style: context.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: ColorPalette.neutral20,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      // Barra de progresso
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 10,
                          backgroundColor: ColorPalette.neutral90,
                          valueColor: AlwaysStoppedAnimation<Color>(tierColor),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tierDescription,
                        textAlign: TextAlign.center,
                        style: context.bodyMedium?.copyWith(
                          color: ColorPalette.neutral10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),

          // Seção da Opção Premium
          if (!_isPremium) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ColorPalette.primary95.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: ColorPalette.primary80.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: ColorPalette.primary95,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Ionicons.star,
                          color: ColorPalette.primary40,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Uppi Club Premium',
                              style: context.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: ColorPalette.neutral10,
                              ),
                            ),
                            Text(
                              'Vire Ouro na hora por apenas R\$ 19,90/mês!',
                              style: context.bodySmall?.copyWith(
                                color: ColorPalette.neutralVariant50,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Assinar Uppi Club Premium'),
                          content: const Text(
                            'Deseja assinar o Uppi Club Premium por R\$ 19,90/mês e garantir todos os benefícios VIP do nível Ouro imediatamente?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancelar'),
                            ),
                            TextButton(
                              onPressed: () async {
                                Navigator.pop(ctx);
                                await _togglePremiumStatus(true);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Uppi Club Premium assinado com sucesso! 🎉'),
                                      backgroundColor: ColorPalette.primary40,
                                    ),
                                  );
                                }
                              },
                              child: const Text('Confirmar Assinatura'),
                            ),
                          ],
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ColorPalette.primary40,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 38),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Quero ser Premium',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.green.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Ionicons.checkmark_circle,
                    color: Colors.green,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Sua assinatura Uppi Club Premium está ativa! 🌟',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Cancelar Assinatura'),
                          content: const Text(
                            'Tem certeza que deseja cancelar sua assinatura Premium do Uppi Club?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Voltar'),
                            ),
                            TextButton(
                              onPressed: () async {
                                Navigator.pop(ctx);
                                await _togglePremiumStatus(false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Assinatura cancelada com sucesso.'),
                                    ),
                                  );
                                }
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: ColorPalette.error40,
                              ),
                              child: const Text('Cancelar Assinatura'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Seção "Regras e Benefícios"
          Text(
            'NÍVEIS E BENEFÍCIOS',
            style: context.labelSmall?.copyWith(
              color: ColorPalette.neutralVariant50,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          // Bronze
          _buildTierInfoRow(
            context: context,
            tierName: 'Bronze',
            description: 'Nível inicial automático para novos usuários.',
            ridesRange: '0 - 4 viagens',
            color: const Color(0xffCD7F32),
            icon: Ionicons.medal_outline,
            isActive: tierName == 'Bronze',
          ),
          const Divider(height: 20),

          // Prata
          _buildTierInfoRow(
            context: context,
            tierName: 'Prata',
            description: 'Ganhe 5% de desconto automático em todas as suas corridas!',
            ridesRange: '5 - 14 viagens',
            color: const Color(0xffC0C0C0),
            icon: Ionicons.ribbon,
            isActive: tierName == 'Prata',
          ),
          const Divider(height: 20),

          // Ouro
          _buildTierInfoRow(
            context: context,
            tierName: 'Ouro',
            description: 'Vantagens VIP: 10% de cashback e prioridade nas chamadas.',
            ridesRange: '15+ viagens',
            color: const Color(0xffFFD700),
            icon: Ionicons.trophy,
            isActive: tierName == 'Ouro' || tierName == 'Ouro Premium',
          ),
          const SizedBox(height: 32),

          // Botão Entendi
          SafeArea(
            top: false,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: ColorPalette.primary40,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Entendi',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierInfoRow({
    required BuildContext context,
    required String tierName,
    required String description,
    required String ridesRange,
    required Color color,
    required IconData icon,
    required bool isActive,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: isActive ? Border.all(color: color, width: 1.5) : null,
          ),
          child: Icon(
            icon,
            color: color,
            size: 20,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    tierName,
                    style: context.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isActive ? color : ColorPalette.neutral10,
                    ),
                  ),
                  Text(
                    ridesRange,
                    style: context.bodySmall?.copyWith(
                      color: ColorPalette.neutralVariant50,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: context.bodySmall?.copyWith(
                  color: ColorPalette.neutralVariant40,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
