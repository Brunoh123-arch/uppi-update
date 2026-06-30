import 'package:flutter/cupertino.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:rider_flutter/core/entities/service.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';

class ServiceItem extends StatelessWidget {
  final ServiceEntity entity;
  final String currency;
  final bool isSelected;
  final Function() onPressed;
  final double? surgeMultiplier;

  const ServiceItem({
    super.key,
    required this.entity,
    required this.isSelected,
    required this.onPressed,
    required this.currency,
    this.surgeMultiplier,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      minimumSize: Size(0, 0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? ColorPalette.primary40 : ColorPalette.primary95,
            width: isSelected ? 2.0 : 1.0,
          ),
          color: isSelected ? ColorPalette.primary95 : ColorPalette.primary99,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            AnimatedScale(
              scale: isSelected ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutBack,
              child: Image.asset(
                _getLocalImageForService(entity.name),
                width: 48,
                height: 48,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        entity.name,
                        style: context.labelLarge,
                      ),
                      if (surgeMultiplier != null &&
                          surgeMultiplier! > 1.0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6B00), // Neon Orange
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Ionicons.flash,
                                color: Color(0xFFFFFFFF),
                                size: 10,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${surgeMultiplier!.toStringAsFixed(1)}x',
                                style: const TextStyle(
                                  fontFamily: 'Outfit',
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (entity.capacity != null) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Ionicons.person,
                          color: ColorPalette.neutral70,
                          size: 16,
                        ),
                        Transform.translate(
                          offset: const Offset(0, -3),
                          child: Text(
                            entity.capacity.toString(),
                            style: context.bodySmall,
                          ),
                        ),
                      ]
                    ],
                  ),
                  if (entity.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      entity.description!,
                      style: context.bodyMedium?.copyWith(
                        color: ColorPalette.neutralVariant50,
                      ),
                    )
                  ]
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(sizeFactor: animation, child: child),
              ),
              child: entity.priceAfterCouponApplied == null
                  ? Text(
                      key: const ValueKey('normal_price'),
                      entity.price.formatCurrency(currency),
                      style: context.titleSmall?.copyWith(
                        color: ColorPalette.primary40,
                      ),
                    )
                  : Column(
                      key: const ValueKey('coupon_price'),
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          entity.price.formatCurrency(currency),
                          style: context.titleSmall?.copyWith(
                            color: ColorPalette.primary40,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          (entity.priceAfterCouponApplied ?? 0)
                              .formatCurrency(currency),
                          style: context.titleSmall?.copyWith(
                            color: ColorPalette.primary40,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _getLocalImageForService(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.contains('taxi') && lowerName.contains('moto')) {
      return 'assets/images/yellow_moto.png';
    } else if (lowerName.contains('taxi')) {
      return 'assets/images/yellow_taxi.png';
    } else if (lowerName.contains('moto')) {
      return 'assets/images/white_moto.png';
    } else {
      // Default (Regular, Uppi X, Uppi, etc.)
      return 'assets/images/white_car.png';
    }
  }
}
