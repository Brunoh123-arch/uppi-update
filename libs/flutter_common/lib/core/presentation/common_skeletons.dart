import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/shimmer_placeholder.dart';
import 'package:ionicons/ionicons.dart';

/// Esqueleto shimmer para um item de anúncio/novidade
class AnnouncementSkeletonItem extends StatelessWidget {
  const AnnouncementSkeletonItem({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ColorPalette.neutralVariant99,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ColorPalette.neutral90),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShimmerPlaceholder(
                width: 40,
                height: 40,
                borderRadius: BorderRadius.circular(12),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: ShimmerPlaceholder(
                  width: double.infinity,
                  height: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const ShimmerPlaceholder(
            width: double.infinity,
            height: 12,
          ),
          const SizedBox(height: 8),
          const ShimmerPlaceholder(
            width: 180,
            height: 12,
          ),
        ],
      ),
    );
  }
}

/// Esqueleto shimmer para um item do histórico de corridas
class RideHistorySkeletonItem extends StatelessWidget {
  final bool showDriverInfo;

  const RideHistorySkeletonItem({
    super.key,
    this.showDriverInfo = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ColorPalette.neutralVariant99,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ColorPalette.neutral90),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ShimmerPlaceholder(
                  width: 48,
                  height: 48,
                  borderRadius: BorderRadius.circular(12),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ShimmerPlaceholder(width: 120, height: 16),
                          ShimmerPlaceholder(width: 60, height: 16),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ShimmerPlaceholder(width: 140, height: 12),
                          ShimmerPlaceholder(width: 45, height: 12),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: ColorPalette.neutralVariant99,
              border: Border.all(color: ColorPalette.neutral90),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    ShimmerPlaceholder(
                      width: 8,
                      height: 8,
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                    ),
                    SizedBox(width: 12),
                    ShimmerPlaceholder(width: 200, height: 12),
                  ],
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    ShimmerPlaceholder(
                      width: 8,
                      height: 8,
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                    ),
                    SizedBox(width: 12),
                    ShimmerPlaceholder(width: 220, height: 12),
                  ],
                ),
                if (showDriverInfo) ...[
                  const Divider(height: 20),
                  const Row(
                    children: [
                      ShimmerPlaceholder(
                        width: 36,
                        height: 36,
                        borderRadius: BorderRadius.all(Radius.circular(18)),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShimmerPlaceholder(width: 100, height: 14),
                            SizedBox(height: 8),
                            ShimmerPlaceholder(width: 60, height: 12),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ShimmerPlaceholder(width: 80, height: 12),
                          SizedBox(height: 8),
                          ShimmerPlaceholder(width: 60, height: 16),
                        ],
                      )
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Esqueleto shimmer para a lista de endereços favoritos
class FavoriteLocationsSkeleton extends StatelessWidget {
  const FavoriteLocationsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 3,
      separatorBuilder: (context, index) => const Divider(
        height: 16,
        indent: 64,
      ),
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            ShimmerPlaceholder(
              width: 42,
              height: 42,
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerPlaceholder(width: 100, height: 16),
                  SizedBox(height: 6),
                  ShimmerPlaceholder(width: 220, height: 12),
                ],
              ),
            ),
            const Icon(
              Ionicons.chevron_forward,
              size: 20,
              color: ColorPalette.neutral90,
            ),
          ],
        ),
      ),
    );
  }
}

/// Esqueleto shimmer para a lista de métodos de pagamento
class PaymentMethodsSkeleton extends StatelessWidget {
  const PaymentMethodsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 2,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) => Container(
        decoration: BoxDecoration(
          color: ColorPalette.neutralVariant99,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ColorPalette.neutral90),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ShimmerPlaceholder(
                        width: 32,
                        height: 24,
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                      ),
                      SizedBox(width: 12),
                      ShimmerPlaceholder(width: 120, height: 20),
                    ],
                  ),
                  SizedBox(height: 32),
                  ShimmerPlaceholder(width: 80, height: 12),
                  SizedBox(height: 8),
                  ShimmerPlaceholder(width: 140, height: 14),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: const BoxDecoration(
                color: ColorPalette.neutralVariant95,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: const Row(
                children: [
                  ShimmerPlaceholder(width: 150, height: 16),
                  Spacer(),
                  ShimmerPlaceholder(
                    width: 44,
                    height: 24,
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Esqueleto shimmer para a lista de viagens agendadas
class ScheduledRidesSkeleton extends StatelessWidget {
  const ScheduledRidesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 2,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) => Container(
        decoration: BoxDecoration(
          color: ColorPalette.neutralVariant99,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ColorPalette.neutral90),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ShimmerPlaceholder(
                    width: 48,
                    height: 48,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ShimmerPlaceholder(width: 120, height: 16),
                            ShimmerPlaceholder(width: 60, height: 16),
                          ],
                        ),
                        SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ShimmerPlaceholder(width: 140, height: 12),
                            ShimmerPlaceholder(width: 45, height: 12),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: ColorPalette.neutralVariant99,
                border: Border.all(color: ColorPalette.neutral90),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ShimmerPlaceholder(
                        width: 20,
                        height: 20,
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                      SizedBox(width: 12),
                      ShimmerPlaceholder(width: 120, height: 12),
                    ],
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      ShimmerPlaceholder(
                        width: 8,
                        height: 8,
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                      ),
                      SizedBox(width: 12),
                      ShimmerPlaceholder(width: 200, height: 12),
                    ],
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      ShimmerPlaceholder(
                        width: 8,
                        height: 8,
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                      ),
                      SizedBox(width: 12),
                      ShimmerPlaceholder(width: 220, height: 12),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Esqueleto shimmer para os campos da tela de Perfil
class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          // Avatar circular
          Center(
            child: ShimmerPlaceholder(
              width: 96,
              height: 96,
              borderRadius: BorderRadius.circular(48),
            ),
          ),
          const SizedBox(height: 32),
          // Campos de formulário
          ...List.generate(3, (index) => Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ShimmerPlaceholder(width: 80, height: 12),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: ColorPalette.neutralVariant99,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ColorPalette.neutral90),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  child: const ShimmerPlaceholder(width: 180, height: 16),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

/// Esqueleto shimmer para a tela de resumo de feedbacks (Gauge e listagem)
class FeedbacksSummarySkeleton extends StatelessWidget {
  const FeedbacksSummarySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Esqueleto do Gauge/Rating Circular
          Center(
            child: ShimmerPlaceholder(
              width: 140,
              height: 140,
              borderRadius: BorderRadius.circular(70),
            ),
          ),
          const SizedBox(height: 32),
          // Listagem de reviews
          ...List.generate(2, (index) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ColorPalette.neutralVariant99,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ColorPalette.neutral90),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const ShimmerPlaceholder(width: 100, height: 16),
                      const Spacer(),
                      const ShimmerPlaceholder(width: 40, height: 14),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const ShimmerPlaceholder(width: double.infinity, height: 12),
                  const SizedBox(height: 8),
                  const ShimmerPlaceholder(width: 220, height: 12),
                ],
              ),
            ),
          )),
        ],
      ),
    );
  }
}

/// Esqueleto shimmer para a lista de motivos de cancelamento (radio buttons)
class CancelReasonSkeleton extends StatelessWidget {
  const CancelReasonSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(4, (index) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: ShimmerPlaceholder(
                width: double.infinity,
                height: 16,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 16),
            ShimmerPlaceholder(
              width: 22,
              height: 22,
              borderRadius: BorderRadius.circular(11),
            ),
          ],
        ),
      )),
    );
  }
}

/// Esqueleto shimmer para o diálogo de seleção de método de pagamento/payout
class PayoutMethodDialogSkeleton extends StatelessWidget {
  const PayoutMethodDialogSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(3, (index) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                ShimmerPlaceholder(
                  width: 24,
                  height: 24,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(width: 12),
                const ShimmerPlaceholder(width: 120, height: 16),
                const Spacer(),
                ShimmerPlaceholder(
                  width: 22,
                  height: 22,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            ),
            if (index < 2) const Padding(
              padding: EdgeInsets.only(left: 48, top: 10),
              child: Divider(height: 1),
            ),
          ],
        ),
      )),
    );
  }
}

/// Esqueleto shimmer para a lista de atividades da carteira/wallet
class WalletActivitiesSkeleton extends StatelessWidget {
  const WalletActivitiesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(4, (index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ColorPalette.neutralVariant99,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ColorPalette.neutral90),
          ),
          child: Row(
            children: [
              ShimmerPlaceholder(
                width: 40,
                height: 40,
                borderRadius: BorderRadius.circular(20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerPlaceholder(width: 140, height: 14),
                    SizedBox(height: 8),
                    ShimmerPlaceholder(width: 90, height: 12),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const ShimmerPlaceholder(width: 60, height: 16),
            ],
          ),
        ),
      )),
    );
  }
}

/// Esqueleto shimmer compacto para loading inline (place search, small cards)
class InlineLoadingSkeleton extends StatelessWidget {
  final double width;
  final double height;

  const InlineLoadingSkeleton({
    super.key,
    this.width = 80,
    this.height = 80,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ShimmerPlaceholder(
            width: width * 0.6,
            height: 14,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          ShimmerPlaceholder(
            width: width * 0.4,
            height: 12,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}

/// Esqueleto shimmer para o preview de corrida/order
class OrderPreviewSkeleton extends StatelessWidget {
  const OrderPreviewSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: ShimmerPlaceholder(
              width: 40,
              height: 4,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          
          // Lista de Carros (3 itens)
          ...List.generate(3, (index) => Padding(
            padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
            child: Row(
              children: [
                // Imagem do carro
                ShimmerPlaceholder(
                  width: 60,
                  height: 60,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(width: 12),
                // Nome e Descrição
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      ShimmerPlaceholder(width: 100, height: 16),
                      SizedBox(height: 8),
                      ShimmerPlaceholder(width: 150, height: 12),
                    ],
                  ),
                ),
                // Preço
                const ShimmerPlaceholder(width: 60, height: 16),
              ],
            ),
          )),
          
          const Divider(color: ColorPalette.neutral95, height: 16),
          const SizedBox(height: 16),
          
          // Chips de Preferência
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(3, (index) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ShimmerPlaceholder(
                    width: double.infinity,
                    height: 36,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              )),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Carteira
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ShimmerPlaceholder(
              width: double.infinity,
              height: 56,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Row de Preferências e Cupom
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                ShimmerPlaceholder(width: 140, height: 20),
                ShimmerPlaceholder(width: 120, height: 20),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Botões Pedir Agora
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ShimmerPlaceholder(
                  width: 56,
                  height: 56,
                  borderRadius: BorderRadius.circular(12),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ShimmerPlaceholder(
                    width: double.infinity,
                    height: 56,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Esqueleto shimmer compacto para card de transição (track order states)
class TransitionCardSkeleton extends StatelessWidget {
  const TransitionCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ShimmerPlaceholder(
            width: 48,
            height: 48,
            borderRadius: BorderRadius.circular(24),
          ),
          const SizedBox(height: 12),
          const ShimmerPlaceholder(width: 160, height: 16),
        ],
      ),
    );
  }
}

/// Esqueleto shimmer para sugestões de destino (recentes + favoritos)
class DestinationSuggestionsSkeleton extends StatelessWidget {
  const DestinationSuggestionsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: ShimmerPlaceholder(width: 80, height: 14),
        ),
        const SizedBox(height: 12),
        ...List.generate(3, (index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              ShimmerPlaceholder(
                width: 36,
                height: 36,
                borderRadius: BorderRadius.circular(18),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerPlaceholder(width: 150, height: 14),
                    SizedBox(height: 6),
                    ShimmerPlaceholder(width: 200, height: 12),
                  ],
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }
}

/// Esqueleto shimmer para a lista de motoristas favoritos
class FavoriteDriversSkeleton extends StatelessWidget {
  const FavoriteDriversSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 3,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ColorPalette.neutralVariant99,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ColorPalette.neutral90),
        ),
        child: Row(
          children: [
            ShimmerPlaceholder(
              width: 48,
              height: 48,
              borderRadius: BorderRadius.circular(24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerPlaceholder(width: 140, height: 16),
                  SizedBox(height: 8),
                  ShimmerPlaceholder(width: 100, height: 12),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const ShimmerPlaceholder(width: 60, height: 14),
          ],
        ),
      ),
    );
  }
}

/// Esqueleto shimmer para a tela de avaliação (rating params + comment)
class RateRideSkeleton extends StatelessWidget {
  const RateRideSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Avatar do motorista
          Center(
            child: ShimmerPlaceholder(
              width: 64,
              height: 64,
              borderRadius: BorderRadius.circular(32),
            ),
          ),
          const SizedBox(height: 16),
          // Nome
          const Center(
            child: ShimmerPlaceholder(width: 120, height: 18),
          ),
          const SizedBox(height: 24),
          // Estrelas
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ShimmerPlaceholder(
                width: 36,
                height: 36,
                borderRadius: BorderRadius.circular(4),
              ),
            )),
          ),
          const SizedBox(height: 24),
          // Parâmetros de avaliação
          ...List.generate(3, (index) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ShimmerPlaceholder(
                  width: 100,
                  height: 14,
                  borderRadius: BorderRadius.circular(4),
                ),
                ShimmerPlaceholder(
                  width: 60,
                  height: 30,
                  borderRadius: BorderRadius.circular(15),
                ),
              ],
            ),
          )),
          const SizedBox(height: 16),
          // Campo de comentário
          ShimmerPlaceholder(
            width: double.infinity,
            height: 80,
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      ),
    );
  }
}

