import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/shimmer_placeholder.dart';
export 'package:flutter_common/core/presentation/common_skeletons.dart';

/// Esqueleto shimmer para a tela de ganhos (gráfico e viagens recentes)
class EarningsSkeleton extends StatelessWidget {
  const EarningsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Esqueleto do Gráfico de Barras
          Center(
            child: Container(
              height: 250,
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ColorPalette.neutralVariant99,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ColorPalette.primary95),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ShimmerPlaceholder(width: 150, height: 16),
                  const SizedBox(height: 24),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(
                        7,
                        (index) => ShimmerPlaceholder(
                          width: 24,
                          height: (50 + (index * 25) % 130).toDouble(),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Lista de viagens recentes (skeleton)
          ...List.generate(
            3,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ColorPalette.neutralVariant99,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ColorPalette.primary95),
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
            ),
          ),
        ],
      ),
    );
  }
}
