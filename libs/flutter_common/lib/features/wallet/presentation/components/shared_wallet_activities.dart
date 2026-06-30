import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/theme/animation_duration.dart';
import 'package:flutter_common/core/extensions/extensions.dart';

class SharedWalletActivities extends StatelessWidget {
  final bool isLoading;
  final String? errorMessage;
  final List<Widget> activities;
  final Widget loadingIndicator;

  const SharedWalletActivities({
    super.key,
    required this.isLoading,
    this.errorMessage,
    required this.activities,
    required this.loadingIndicator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: AnimatedSwitcher(
        duration: AnimationDuration.pageStateTransitionMobile,
        child: _buildChild(context),
      ),
    );
  }

  Widget _buildChild(BuildContext context) {
    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            errorMessage!,
            style: context.bodyMedium?.copyWith(color: ColorPalette.error40),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (isLoading) {
      return const ActivitiesSkeleton();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (activities.isEmpty) ...[
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                context.t.noActivitiesYet,
                style: context.titleSmall?.copyWith(
                  color: ColorPalette.neutralVariant50,
                ),
              ),
            ),
          )
        ],
        if (activities.isNotEmpty) ...[
          Text(
            context.t.activities,
            style: context.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: ColorPalette.neutral10,
            ),
          ),
          const SizedBox(height: 16),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: activities.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: e,
            )).toList(),
          )
        ],
      ],
    );
  }
}

/// Widget auxiliar de Skeleton com efeito Shimmer pulsante nativo
class WidgetSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const WidgetSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<WidgetSkeleton> createState() => _WidgetSkeletonState();
}

class _WidgetSkeletonState extends State<WidgetSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: ColorPalette.neutralVariant90,
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
          ),
        );
      },
    );
  }
}

/// Esqueleto completo simulando a lista de atividades em carregamento
class ActivitiesSkeleton extends StatelessWidget {
  const ActivitiesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const WidgetSkeleton(width: 110, height: 22, borderRadius: 6),
        const SizedBox(height: 20),
        ...List.generate(3, (index) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              // Círculo ou quadrado do ícone da atividade
              const WidgetSkeleton(width: 48, height: 48, borderRadius: 14),
              const SizedBox(width: 16),
              // Detalhes da transação (Título e Data/Hora)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const WidgetSkeleton(width: 140, height: 16, borderRadius: 4),
                    const SizedBox(height: 8),
                    const WidgetSkeleton(width: 90, height: 12, borderRadius: 4),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Valor da transação
              const WidgetSkeleton(width: 65, height: 16, borderRadius: 4),
            ],
          ),
        )),
      ],
    );
  }
}
