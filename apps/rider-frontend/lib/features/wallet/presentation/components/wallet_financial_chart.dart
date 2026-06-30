import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:ionicons/ionicons.dart';

class WalletFinancialChart extends StatelessWidget {
  const WalletFinancialChart({super.key});

  @override
  Widget build(BuildContext context) {
    // Dados fictícios simulando gastos diários da semana em corridas no Uppi
    final weeklySpending = [
      _DaySpending(day: 'S', amount: 15.0, heightFactor: 0.35),
      _DaySpending(day: 'T', amount: 32.5, heightFactor: 0.65),
      _DaySpending(day: 'Q', amount: 48.0, heightFactor: 0.85),
      _DaySpending(day: 'Q', amount: 20.0, heightFactor: 0.45),
      _DaySpending(day: 'S', amount: 55.0, heightFactor: 0.95),
      _DaySpending(day: 'S', amount: 12.0, heightFactor: 0.25),
      _DaySpending(day: 'D', amount: 28.0, heightFactor: 0.55),
    ];

    final totalWeek = weeklySpending.fold(0.0, (sum, e) => sum + e.amount);

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
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: ColorPalette.primary95,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Ionicons.bar_chart_outline,
                  color: ColorPalette.primary40,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Frequência de Uso Semanal',
                      style: context.titleSmall?.copyWith(
                        color: ColorPalette.neutral10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Total gasto nesta semana: R\$ ${totalWeek.toStringAsFixed(2)}',
                      style: context.bodySmall?.copyWith(
                        color: ColorPalette.neutral40,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Corpo do Gráfico de Barras
          SizedBox(
            height: 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: weeklySpending.map((e) {
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Valor no topo de cada barra ao passar o cursor ou estático discreto
                      Text(
                        'R\$${e.amount.toInt()}',
                        style: context.bodySmall?.copyWith(
                          fontSize: 9,
                          color: ColorPalette.neutral50,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Barra vertical com gradiente azul Uppi
                      Expanded(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0.0, end: e.heightFactor),
                          duration: const Duration(milliseconds: 1000),
                          curve: Curves.easeOutQuart,
                          builder: (context, value, child) {
                            return FractionallySizedBox(
                              heightFactor: value,
                              alignment: Alignment.bottomCenter,
                              child: child,
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  ColorPalette.primary40, // Azul oficial Uppi
                                  ColorPalette.primary80, // Azul celeste suave
                                ],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: ColorPalette.primary40.withValues(alpha: 0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Letra do dia da semana
                      Text(
                        e.day,
                        style: context.labelMedium?.copyWith(
                          color: ColorPalette.neutral30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _DaySpending {
  final String day;
  final double amount;
  final double heightFactor;

  _DaySpending({
    required this.day,
    required this.amount,
    required this.heightFactor,
  });
}
