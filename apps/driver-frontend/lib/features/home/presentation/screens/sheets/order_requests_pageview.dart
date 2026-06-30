import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/entities/driver_location.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/entities/order_request.dart';
import 'package:uppi_motorista/features/home/presentation/components/order_request_item.dart';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';

import '../../blocs/home.dart';

class OrderRequestsPageView extends StatelessWidget {
  final List<OrderRequestEntity> requests;
  final DriverLocation? driverLocation;

  const OrderRequestsPageView({
    super.key,
    required this.requests,
    this.driverLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Pulsing Glowing Header Warning (Top of the screen)
        Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          left: 16,
          right: 16,
          child: const Center(child: _PulsingHeader()),
        ),

        // Page View for the offers (Bottom of the screen)
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: SizedBox(
            height: 350,
            child: PageView.builder(
              controller: PageController(viewportFraction: 0.92),
              onPageChanged: (value) => locator<HomeBloc>().add(
                HomeEvent.onOrderRequestPageChanged(request: requests[value]),
              ),
              itemCount: requests.length,
              itemBuilder: (context, index) {
                return Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: OrderRequestItem(
                        request: requests[index],
                        driverLocation: driverLocation,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _PulsingHeader extends StatefulWidget {
  const _PulsingHeader();

  @override
  State<_PulsingHeader> createState() => _PulsingHeaderState();
}

class _PulsingHeaderState extends State<_PulsingHeader> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    
    _glowAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xE60F172A), // Slate-900 com opacidade elegante
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulse Neon Shield Icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ColorPalette.primary50.withValues(alpha: 0.06 * _glowAnimation.value), // Uppi's brand neon blue
                  border: Border.all(
                    color: ColorPalette.primary50.withValues(alpha: 0.3 * _glowAnimation.value),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: ColorPalette.primary50.withValues(alpha: 0.12 * _glowAnimation.value),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(
                  Ionicons.flash,
                  color: ColorPalette.primary50.withValues(alpha: _glowAnimation.value),
                  size: 24,
                ),
              ),
              const SizedBox(height: 8),

              // Pulsing warning text
              Text(
                "NOVA OFERTA DE CORRIDA",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: _glowAnimation.value),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  shadows: [
                    Shadow(
                      color: ColorPalette.primary50.withValues(alpha: 0.4 * _glowAnimation.value),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                "Você tem resposta exclusiva para esta corrida",
                style: TextStyle(
                  color: ColorPalette.neutral70,
                  fontSize: 11,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
