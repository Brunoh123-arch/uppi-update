import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/entities/order.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/app_card_sheet.dart';
import '../components/ride_progress_bar.dart';
import 'package:flutter_common/core/presentation/buttons/app_icon_button.dart';
import 'package:flutter_common/core/presentation/buttons/app_text_button.dart';
import 'package:flutter_common/core/presentation/card_handle.dart';
import 'package:rider_flutter/core/presentation/driver_rating.dart';
import 'package:rider_flutter/core/presentation/payment_method_select_field.dart';
import 'package:rider_flutter/core/presentation/vehicle_info/vehicle_info.dart';
import 'package:flutter_common/core/presentation/waypoints_view/waypoints_view.dart';
import 'package:flutter_common/core/presentation/avatars/driver_avatar.dart';
import 'package:rider_flutter/features/home/features/track_order/presentation/blocs/track_order.dart';
import 'package:rider_flutter/features/home/features/track_order/presentation/components/notice_bar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dialogs/ride_options_dialog.dart';
import '../dialogs/ride_safety_dialog.dart';

class OrderInProgressSheet extends StatefulWidget {
  final OrderEntity order;
  static final ValueNotifier<bool> isMinimizedNotifier = ValueNotifier<bool>(false);

  const OrderInProgressSheet({super.key, required this.order});

  @override
  State<OrderInProgressSheet> createState() => _OrderInProgressSheetState();
}

class _OrderInProgressSheetState extends State<OrderInProgressSheet> {
  late bool _isMinimized;

  @override
  void initState() {
    super.initState();
    _isMinimized = OrderInProgressSheet.isMinimizedNotifier.value;
    OrderInProgressSheet.isMinimizedNotifier.addListener(_onMinimizedChanged);
  }

  void _onMinimizedChanged() {
    if (mounted) {
      setState(() {
        _isMinimized = OrderInProgressSheet.isMinimizedNotifier.value;
      });
    }
  }

  @override
  void dispose() {
    OrderInProgressSheet.isMinimizedNotifier.removeListener(_onMinimizedChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: context.responsive(
        const BoxDecoration(
          color: ColorPalette.primary20,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(16),
          ),
        ),
        xl: const BoxDecoration(),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          context.responsive(
            const NoticeBar(),
            xl: const SizedBox(),
          ),
          AppCardSheet(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    OrderInProgressSheet.isMinimizedNotifier.value = !_isMinimized;
                  },
                  onVerticalDragEnd: (details) {
                    if (details.primaryVelocity != null) {
                      if (details.primaryVelocity! > 0) {
                        OrderInProgressSheet.isMinimizedNotifier.value = true;
                      } else if (details.primaryVelocity! < 0) {
                        OrderInProgressSheet.isMinimizedNotifier.value = false;
                      }
                    }
                  },
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CardHandle(),
                      SizedBox(height: 8),
                    ],
                  ),
                ),
                if (!_isMinimized) ...[
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            DriverAvatar(imageUrl: widget.order.driver?.imageUrl),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.order.driver?.fullName ?? '',
                                    style: context.labelLarge,
                                  ),
                                  DriverRating(
                                    rating: widget.order.driver?.rating,
                                    textSuffix: "(${widget.order.serviceName})",
                                  ),
                                  if (widget.order.status == OrderStatus.started) ...[
                                    const SizedBox(height: 6),
                                    _ChronometerWidget(startTime: widget.order.startedAt),
                                  ],
                                ],
                              ),
                            ),
                            Badge(
                              isLabelVisible: widget.order
                                      .chatMessages.lastOrNull?.createdAt
                                      .isAfter(widget.order.lastSeenMessagesAt) ??
                                  false,
                              child: AppIconButton(
                                icon: Ionicons.chatbubble,
                                onPressed: () {
                                  locator<TrackOrderBloc>().showChat();
                                },
                              ),
                            ),
                            AppIconButton(
                              icon: Ionicons.call,
                              onPressed: () async {
                                final mobile = widget.order.driver?.mobileNumber;
                                if (mobile != null && mobile.isNotEmpty) {
                                  final telUri = Uri.parse('tel:$mobile');
                                  try {
                                    if (await canLaunchUrl(telUri)) {
                                      await launchUrl(telUri);
                                    } else {
                                      throw Exception('Não pôde iniciar ligação convencional');
                                    }
                                  } catch (_) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Não foi possível iniciar a chamada convencional.'),
                                        backgroundColor: ColorPalette.error40,
                                      ),
                                    );
                                  }
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Número do motorista não disponível.'),
                                      backgroundColor: ColorPalette.error40,
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                        if (widget.order.driver != null) ...[
                          const SizedBox(height: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildDriverBadge(
                                  context,
                                  Ionicons.ribbon,
                                  "Motorista Uppi Ouro",
                                ),
                                const SizedBox(width: 8),
                                _buildDriverBadge(
                                  context,
                                  Ionicons.sparkles,
                                  "Expert em Conforto",
                                ),
                                const SizedBox(width: 8),
                                _buildDriverBadge(
                                  context,
                                  Ionicons.star,
                                  "Viagem 5 Estrelas",
                                ),
                              ],
                            ),
                          ),
                        ],
                        const Divider(
                          height: 16,
                          color: ColorPalette.neutral90,
                        ),
                        RideProgressBar(status: widget.order.status),
                        const Divider(
                          height: 16,
                          color: ColorPalette.neutral90,
                        ),
                        if (widget.order.boardingPin != null &&
                            (widget.order.status == OrderStatus.driverAccepted ||
                             widget.order.status == OrderStatus.arrived)) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: ColorPalette.primary95,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: ColorPalette.primary80.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Ionicons.shield,
                                      color: ColorPalette.primary30,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "PIN de Embarque",
                                      style: context.bodyMedium?.copyWith(
                                        color: ColorPalette.primary30,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  widget.order.boardingPin!,
                                  style: context.titleLarge?.copyWith(
                                    color: ColorPalette.primary30,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(
                            height: 16,
                            color: ColorPalette.neutral90,
                          ),
                        ],
                        VehicleInfo(
                          imageUrl: widget.order.serviceImageUrl,
                          serviceName: widget.order.serviceName,
                          vehicleModel: widget.order.driver?.vehicleModel,
                          vehicleColor: widget.order.driver?.vehicleColor,
                          vehiclePlateNumber: widget.order.driver?.vehiclePlateNumber,
                          sizeMode: context.responsive(
                            widget.order.status == OrderStatus.arrived
                                ? VehicleInfoSizeMode.large
                                : VehicleInfoSizeMode.compact,
                            xl: VehicleInfoSizeMode.extraLarge,
                          ),
                        ),
                        if (widget.order.status == OrderStatus.driverAccepted) ...[
                          const Divider(
                            height: 16,
                          ),
                          SizedBox(
                            height: 100,
                            child: SingleChildScrollView(
                              child: WayPointsView(
                                waypoints: widget.order.waypoints,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    height: 16,
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 10,
                          offset: const Offset(0, -5),
                        )
                      ],
                      color: context.theme.colorScheme.surface,
                    ),
                  ),
                ],
                SafeArea(
                  top: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        PaymentMethodSelectField(
                          paymentMethod: widget.order.paymentMethod,
                          onPressed: () {
                            locator<TrackOrderBloc>().showPayment();
                          },
                        ),
                        const SizedBox(
                          height: 9,
                        ),
                        const Divider(
                          height: 16,
                        ),
                        Row(
                          children: [
                            AppTextButton(
                              iconData: Ionicons.cog,
                              isDense: true,
                              text: context.translate.rideOptions,
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  useSafeArea: false,
                                  builder: (context) => RideOptionsSheet(
                                    waitTime: widget.order.waitTime,
                                  ),
                                );
                              },
                            ),
                            const Spacer(),
                            AppTextButton(
                              iconData: Ionicons.shield,
                              isDense: true,
                              text: context.translate.rideSafety,
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  useSafeArea: false,
                                  builder: (context) => RideSafetyDialog(
                                    order: widget.order,
                                  ),
                                );
                              },
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverBadge(BuildContext context, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ColorPalette.primary95,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ColorPalette.primary80.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: ColorPalette.primary30,
            size: 13,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: context.bodySmall?.copyWith(
              color: ColorPalette.primary30,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChronometerWidget extends StatefulWidget {
  final DateTime? startTime;

  const _ChronometerWidget({required this.startTime});

  @override
  State<_ChronometerWidget> createState() => _ChronometerWidgetState();
}

class _ChronometerWidgetState extends State<_ChronometerWidget> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateElapsed();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _updateElapsed();
      }
    });
  }

  void _updateElapsed() {
    if (widget.startTime == null) return;
    final diff = DateTime.now().difference(widget.startTime!.toLocal());
    setState(() {
      _elapsed = diff.isNegative ? Duration.zero : diff;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.startTime == null) return const SizedBox.shrink();
    
    final hours = _elapsed.inHours;
    final minutes = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    final displayTime = hours > 0 
        ? '$hours:$minutes:$seconds' 
        : '$minutes:$seconds';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withOpacity(0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Ionicons.time_outline,
            color: Colors.greenAccent,
            size: 13,
          ),
          const SizedBox(width: 5),
          Text(
            displayTime,
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
