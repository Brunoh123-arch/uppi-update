import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';

class RideProgressBar extends StatelessWidget {
  final OrderStatus status;

  const RideProgressBar({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    // Mapeamento dos estágios
    final step1Active = status == OrderStatus.driverAccepted ||
        status == OrderStatus.arrived ||
        status == OrderStatus.started;
    final step2Active = status == OrderStatus.arrived || status == OrderStatus.started;
    final step3Active = status == OrderStatus.started;

    // Conexões ativas
    final line1Active = status == OrderStatus.arrived || status == OrderStatus.started;
    final line2Active = status == OrderStatus.started;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Nó 1: Aceito
              _buildProgressNode(
                active: step1Active,
                completed: status == OrderStatus.arrived || status == OrderStatus.started,
                label: 'Confirmado',
              ),
              
              // Linha 1
              _buildConnectionLine(active: line1Active),
              
              // Nó 2: Chegou
              _buildProgressNode(
                active: step2Active,
                completed: status == OrderStatus.started,
                label: 'No Embarque',
              ),
              
              // Linha 2
              _buildConnectionLine(active: line2Active),
              
              // Nó 3: Em Viagem
              _buildProgressNode(
                active: step3Active,
                completed: false,
                label: 'Em Viagem',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildNodeLabel(context, 'Confirmado', step1Active, status == OrderStatus.driverAccepted),
              _buildNodeLabel(context, 'No Embarque', step2Active, status == OrderStatus.arrived),
              _buildNodeLabel(context, 'Em Viagem', step3Active, status == OrderStatus.started),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressNode({
    required bool active,
    required bool completed,
    required String label,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: completed
            ? ColorPalette.primary40 // Concluído (Azul oficial)
            : active
                ? ColorPalette.primary40
                : ColorPalette.neutral90, // Inativo
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? Colors.white : Colors.transparent,
          width: 2,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: ColorPalette.primary40.withValues(alpha: 0.3),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Center(
        child: completed
            ? const Icon(
                Icons.check,
                color: Colors.white,
                size: 14,
              )
            : Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active ? Colors.white : ColorPalette.neutral60,
                  shape: BoxShape.circle,
                ),
              ),
      ),
    );
  }

  Widget _buildConnectionLine({required bool active}) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        height: 3,
        decoration: BoxDecoration(
          color: active ? ColorPalette.primary40 : ColorPalette.neutral90,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildNodeLabel(
    BuildContext context,
    String text,
    bool active,
    bool isCurrent,
  ) {
    return Expanded(
      child: Text(
        text,
        textAlign: text == 'Confirmado'
            ? TextAlign.left
            : text == 'Em Viagem'
                ? TextAlign.right
                : TextAlign.center,
        style: context.bodySmall?.copyWith(
          color: isCurrent
              ? ColorPalette.primary30 // Destaque para o estágio atual
              : active
                  ? ColorPalette.neutral30
                  : ColorPalette.neutral60,
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
