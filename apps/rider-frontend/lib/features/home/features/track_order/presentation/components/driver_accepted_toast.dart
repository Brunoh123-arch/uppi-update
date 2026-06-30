import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/avatars/driver_avatar.dart';
import 'package:ionicons/ionicons.dart';
import 'package:rider_flutter/core/entities/order.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';

void showDriverAcceptedToast(BuildContext context, OrderEntity order) {
  final overlayState = Overlay.of(context);
  late OverlayEntry overlayEntry;

  overlayEntry = OverlayEntry(
    builder: (context) => _AnimatedDriverAcceptedToast(
      order: order,
      onDismiss: () {
        overlayEntry.remove();
      },
    ),
  );

  overlayState.insert(overlayEntry);
}

class _AnimatedDriverAcceptedToast extends StatefulWidget {
  final OrderEntity order;
  final VoidCallback onDismiss;

  const _AnimatedDriverAcceptedToast({
    required this.order,
    required this.onDismiss,
  });

  @override
  State<_AnimatedDriverAcceptedToast> createState() => _AnimatedDriverAcceptedToastState();
}

class _AnimatedDriverAcceptedToastState extends State<_AnimatedDriverAcceptedToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _opacityAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      reverseDuration: const Duration(milliseconds: 400),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    ));

    _controller.forward();

    _dismissTimer = Timer(const Duration(milliseconds: 4500), _dismiss);
  }

  void _dismiss() {
    if (mounted) {
      _controller.reverse().then((_) {
        widget.onDismiss();
      });
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final driver = widget.order.driver;
    final driverName = driver?.fullName ?? 'Motorista';
    final vehicleModel = driver?.vehicleModel ?? '';
    final vehicleColor = driver?.vehicleColor ?? '';
    final vehiclePlate = driver?.vehiclePlateNumber ?? '';

    final carInfo = [
      if (vehicleColor.isNotEmpty) vehicleColor,
      if (vehicleModel.isNotEmpty) vehicleModel,
      if (vehiclePlate.isNotEmpty) '($vehiclePlate)',
    ].join(' ');

    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: _dismiss,
          child: FadeTransition(
            opacity: _opacityAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: ColorPalette.primary30, // Azul oficial sofisticado do Uppi
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24, width: 1.5),
                        shape: BoxShape.circle,
                      ),
                      child: DriverAvatar(
                        imageUrl: driver?.imageUrl,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Motorista a caminho!',
                            style: context.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$driverName ➔ $carInfo',
                            style: context.bodySmall?.copyWith(
                              color: ColorPalette.primary95, // Azul claro super legível
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Ionicons.car_sport_outline,
                      color: ColorPalette.primary95,
                      size: 26,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
