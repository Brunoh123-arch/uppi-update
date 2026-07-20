import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';

class WaitingAdBanner extends StatefulWidget {
  const WaitingAdBanner({super.key});

  @override
  State<WaitingAdBanner> createState() => _WaitingAdBannerState();
}

class _WaitingAdBannerState extends State<WaitingAdBanner> {
  int _currentAdIndex = 0;
  Timer? _timer;

  final List<Map<String, String>> _ads = [
    {
      'title': 'Pizzaria Bella Massa',
      'description': 'A melhor pizza de Castanhal! Use o cupom UPPI10 e ganhe 10% de desconto.',
      'badge': 'Parceiro Oficial Uppi',
      'icon': 'pizza',
    },
    {
      'title': 'Barbearia do Joe',
      'description': 'Cabelo e barba premium. Apresente sua corrida Uppi e ganhe uma bebida grátis.',
      'badge': 'Desconto Local',
      'icon': 'cut',
    },
    {
      'title': 'Açaí Estação Castanhal',
      'description': 'O açaí mais puro da região! Compre 1L e ganhe desconto na volta para casa.',
      'badge': 'Patrocinador Uppi',
      'icon': 'ice-cream',
    }
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (mounted) {
        setState(() {
          _currentAdIndex = (_currentAdIndex + 1) % _ads.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ads[_currentAdIndex];
    
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.1, 0.0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey<int>(_currentAdIndex),
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              ColorPalette.primary50.withOpacity(0.08),
              ColorPalette.primary80.withOpacity(0.03),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: ColorPalette.primary50.withOpacity(0.15),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ColorPalette.primary50.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getAdIcon(ad['icon'] ?? ''),
                color: ColorPalette.primary40,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        ad['title'] ?? '',
                        style: context.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: ColorPalette.neutral10,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: ColorPalette.primary50.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          ad['badge'] ?? '',
                          style: context.labelSmall?.copyWith(
                            fontSize: 8,
                            color: ColorPalette.primary40,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ad['description'] ?? '',
                    style: context.bodySmall?.copyWith(
                      color: ColorPalette.neutral30,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getAdIcon(String iconName) {
    switch (iconName) {
      case 'pizza':
        return Ionicons.pizza_outline;
      case 'cut':
        return Ionicons.cut_outline;
      case 'ice-cream':
        return Ionicons.ice_cream_outline;
      default:
        return Ionicons.megaphone_outline;
    }
  }
}
