import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/core/presentation/slider_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_common/core/services/arrival_reminder_service.dart';
import 'package:flutter_common/core/presentation/buttons/app_text_button.dart';
import 'package:flutter_common/core/presentation/waypoints_view/waypoints_view.dart';
import 'package:flutter_common/core/theme/animation_duration.dart';
import 'package:flutter_common/core/presentation/card_handle.dart';
import 'package:flutter_common/core/presentation/buttons/app_icon_button.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:ionicons/ionicons.dart';

import '../../blocs/home.dart';
import '../../components/notice_bar_content.dart';
import '../../components/payment_method_select_field.dart';
import '../../dialogs/ride_options_dialog.dart';
import '../../dialogs/ride_safety_dialog.dart';
import '../../components/navigation_overlay.dart';

class ActiveOrderSheet extends StatefulWidget {
  final OnTripDriverStatus state;
  static final ValueNotifier<bool> isMinimizedNotifier = ValueNotifier<bool>(false);

  const ActiveOrderSheet({super.key, required this.state});

  @override
  State<ActiveOrderSheet> createState() => _ActiveOrderSheetState();
}

class _ActiveOrderSheetState extends State<ActiveOrderSheet> {
  // Ride Chaining
  _ChainedRide? _chainedRide;
  bool _chainingLoading = false;
  bool _chainingResponded = false;
  // Já buscamos uma corrida encadeada para esta corrida? Sem esse flag, toda
  // atualização do pedido (ETA, chat, status) refazia a chamada à Edge
  // Function quando a busca anterior não encontrava nada.
  bool _chainingSearched = false;
  late bool _isMinimized;

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.toInt()} m';
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).ceil();
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      return '$hours h $remainingMinutes min';
    }
    return '$minutes min';
  }

  String _formatArrivalTime(double seconds) {
    final arrival = DateTime.now().add(Duration(seconds: seconds.toInt()));
    final hour = arrival.hour.toString().padLeft(2, '0');
    final minute = arrival.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  List<String> _ridePreferences = [];

  @override
  void initState() {
    super.initState();
    // Auto-minimizar ao iniciar se já estiver a caminho do passageiro ou destino
    if (widget.state.order.status == OrderStatus.driverAccepted ||
        widget.state.order.status == OrderStatus.started) {
      ActiveOrderSheet.isMinimizedNotifier.value = true;
    }
    _isMinimized = ActiveOrderSheet.isMinimizedNotifier.value;
    ActiveOrderSheet.isMinimizedNotifier.addListener(_onMinimizedChanged);
    _loadRidePreferences();
  }

  Future<void> _loadRidePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? prefsJson = prefs.getString('ride_preference_${widget.state.order.id}');
      prefsJson ??= prefs.getString('pending_ride_preferences');
      
      if (prefsJson != null) {
        final List<dynamic> decoded = jsonDecode(prefsJson);
        if (mounted) {
          setState(() {
            _ridePreferences = decoded.cast<String>();
          });
        }
      }
    } catch (_) {}
  }

  void _onMinimizedChanged() {
    if (mounted) {
      setState(() {
        _isMinimized = ActiveOrderSheet.isMinimizedNotifier.value;
      });
    }
  }

  @override
  void dispose() {
    ActiveOrderSheet.isMinimizedNotifier.removeListener(_onMinimizedChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(ActiveOrderSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Auto-minimizar ao transicionar para a caminho do passageiro ou destino
    if ((widget.state.order.status == OrderStatus.driverAccepted &&
            oldWidget.state.order.status != OrderStatus.driverAccepted) ||
        (widget.state.order.status == OrderStatus.started &&
            oldWidget.state.order.status != OrderStatus.started)) {
      ActiveOrderSheet.isMinimizedNotifier.value = true;
    }

    // Auto-expandir quando chegar no local de embarque (aguardando passageiro)
    if (widget.state.order.status == OrderStatus.arrived &&
        oldWidget.state.order.status != OrderStatus.arrived) {
      ActiveOrderSheet.isMinimizedNotifier.value = false;
    }

    // Disparar busca de corrida encadeada quando status = started e não buscamos ainda
    if (widget.state.order.status == OrderStatus.started &&
        !_chainingSearched &&
        !_chainingResponded &&
        !_chainingLoading &&
        _chainedRide == null) {
      _trySearchNextRide();
    }
  }

  Future<void> _trySearchNextRide() async {
    final order = widget.state.order;
    _chainingSearched = true;
    setState(() => _chainingLoading = true);

    try {
      final idToken = Supabase.instance.client.auth.currentSession?.accessToken;
      if (idToken == null) throw Exception("Could not get auth token");

      final response = await http.post(
        Uri.parse('${dotenv.env['SUPABASE_URL']}/functions/v1/search-next-ride'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'data': {
            'currentOrderId': order.id,
            'currentLat': order.waypoints.last.coordinates.lat,
            'currentLng': order.waypoints.last.coordinates.lng,
          },
        }),
      );
      final responseBody = response.body;
      final responseJson = jsonDecode(responseBody);
      final data = responseJson['result'] as Map<String, dynamic>? ?? {};

      if (data['found'] == true) {
        setState(() {
          _chainedRide = _ChainedRide(
            nextOrderId: data['nextOrderId'] as String,
            pickupAddress: data['pickupAddress'] as String? ?? '',
            destinationAddress: data['destinationAddress'] as String? ?? '',
            distanceToPickup: (data['distanceToPickup'] as num?)?.toInt() ?? 0,
            estimatedFare: (data['estimatedFare'] as num?)?.toDouble() ?? 0,
          );
        });
      }
    } catch (_) {
      // Silencioso — não prejudica o fluxo principal
    } finally {
      if (mounted) setState(() => _chainingLoading = false);
    }
  }

  Future<void> _respondToChain(bool accept) async {
    if (_chainedRide == null) return;
    setState(() => _chainingResponded = true);

    try {
      final idToken = Supabase.instance.client.auth.currentSession?.accessToken;
      if (idToken == null) throw Exception("Could not get auth token");

      await http.post(
        Uri.parse('${dotenv.env['SUPABASE_URL']}/functions/v1/respond-to-chained-ride'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'data': {'nextOrderId': _chainedRide!.nextOrderId, 'accept': accept},
        }),
      );
    } catch (_) {
      // Silencioso
    } finally {
      if (mounted) setState(() => _chainedRide = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: context.responsive(
        BoxDecoration(
          color: ColorPalette.primary20,
          borderRadius: BorderRadius.circular(30),
        ),
        xl: const BoxDecoration(),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          context.responsive(
            AnimatedSwitcher(
              duration: AnimationDuration.pageStateTransitionMobile,
              child:
                  (widget.state.order.status == OrderStatus.driverAccepted &&
                      widget.state.order.etaPickupAt != null)
                  ? NoticeBarContent(
                      icon: Ionicons.time,
                      text: context.translate.noticePickingUpRiderIn,
                      isLate: () {
                        final eta = widget.state.order.etaPickupAt?.toLocal();
                        if (eta == null) return false;
                        return eta.isBefore(DateTime.now());
                      }(),
                    )
                  : widget.state.order.status == OrderStatus.arrived
                  ? NoticeBarContent(
                      icon: Ionicons.information_circle,
                      text: context.translate.noticeRiderNotified,
                    )
                  : widget.state.order.status == OrderStatus.started
                  ? NoticeBarContent(
                      icon: Ionicons.time,
                      text: context.translate.headingToDestination,
                    )
                  : const SizedBox.shrink(),
            ),
            xl: const SizedBox(),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              color: context.theme.colorScheme.surface,
            ),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      ActiveOrderSheet.isMinimizedNotifier.value = !_isMinimized;
                    },
                    onVerticalDragEnd: (details) {
                      if (details.primaryVelocity != null) {
                        if (details.primaryVelocity! > 0) {
                          ActiveOrderSheet.isMinimizedNotifier.value = true;
                        } else if (details.primaryVelocity! < 0) {
                          ActiveOrderSheet.isMinimizedNotifier.value = false;
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
                  if (_isMinimized) ...[
                    ValueListenableBuilder<double>(
                      valueListenable: HomeNavigationOverlay.remainingDistanceNotifier,
                      builder: (context, distance, _) {
                        return ValueListenableBuilder<double>(
                          valueListenable: HomeNavigationOverlay.remainingDurationNotifier,
                          builder: (context, duration, _) {
                            if (distance <= 0 && duration <= 0) {
                              return const SizedBox.shrink();
                            }
                            final isDark = Theme.of(context).brightness == Brightness.dark;
                            final greenColor = isDark ? const Color(0xFF00E676) : const Color(0xFF188038);
                            final subTextColor = isDark ? Colors.white70 : ColorPalette.neutral40;
                            // Barra de ETA estilo Google Maps: tempo verde em
                            // destaque no centro, distância e horário ao lado.
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        _formatDuration(duration).replaceAll(' ', ''),
                                        style: context.titleLarge?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 24,
                                          color: greenColor,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(
                                        Ionicons.leaf,
                                        color: greenColor,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_formatDistance(distance)} • ${_formatArrivalTime(duration)}',
                                    style: context.bodyLarge?.copyWith(
                                      color: subTextColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                    const Divider(height: 16),
                  ],
                  if (!_isMinimized) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              border: Border.all(color: ColorPalette.neutral90),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Ionicons.person_circle,
                              color: ColorPalette.primary30,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.state.order.riderFullName,
                                  style: context.labelMedium,
                                ),
                                Text(
                                  widget.state.order.serviceName,
                                  style: context.bodyMedium?.copyWith(
                                    color: ColorPalette.neutralVariant50,
                                  ),
                                ),
                                if (widget.state.order.status == OrderStatus.started) ...[
                                  const SizedBox(height: 6),
                                  _ChronometerWidget(startTime: widget.state.order.startAt),
                                ],
                                if (_ridePreferences.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: _ridePreferences.map((pref) {
                                      final isSilent = pref == 'silent';
                                      final isAc = pref == 'ac';
                                      
                                      final icon = isSilent 
                                          ? Ionicons.volume_mute 
                                          : isAc 
                                              ? Ionicons.snow 
                                              : Ionicons.chatbubbles;
                                      final label = isSilent 
                                          ? context.translate.preferenceSilent 
                                          : isAc 
                                              ? context.translate.preferenceAc 
                                              : context.translate.preferenceChatty;

                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: ColorPalette.primary95,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: ColorPalette.neutral90),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              icon,
                                              size: 11,
                                              color: ColorPalette.primary30,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              label,
                                              style: context.bodySmall?.copyWith(
                                                color: ColorPalette.primary30,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Badge(
                            isLabelVisible:
                                widget
                                    .state
                                    .order
                                    .chatMessages
                                    .lastOrNull
                                    ?.createdAt
                                    .isAfter(
                                      widget.state.order.lastSeenMessagesAt,
                                    ) ??
                                false,
                            child: AppIconButton(
                              icon: Ionicons.chatbubble,
                              onPressed: () {
                                locator<HomeBloc>().add(
                                  const HomeEvent.onShowChat(),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          AppIconButton(
                            icon: Ionicons.call,
                            onPressed: () async {
                              final phone = widget.state.order.riderPhoneNumber;
                              if (phone.isNotEmpty) {
                                final uri = Uri.parse('tel:$phone');
                                try {
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri);
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
                                    content: Text('Número do passageiro não disponível.'),
                                    backgroundColor: ColorPalette.error40,
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      height: 120,
                      child: SingleChildScrollView(
                        child: WayPointsView(
                          waypoints: widget.state.order.waypoints,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 16,
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 10,
                            offset: const Offset(0, -5),
                          ),
                        ],
                        color: context.theme.colorScheme.surface,
                      ),
                    ),
                  ],
                  if (!_isMinimized)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PaymentMethodSelectField(
                            order: widget.state.order,
                            onPressed: null,
                          ),
                          const SizedBox(height: 9),
                          const Divider(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: AppTextButton(
                                    iconData: Ionicons.cog,
                                    isDense: true,
                                    text: context.translate.rideOptions,
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        useSafeArea: false,
                                        builder: (context) => RideOptionsSheet(
                                          orderId: widget.state.order.id,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AppTextButton(
                                    iconData: Ionicons.shield,
                                    isDense: true,
                                    text: context.translate.rideSafety,
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        useSafeArea: false,
                                        builder: (context) => RideSafetyDialog(
                                          order: widget.state.order,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── Ride Chaining Banner ──
                  if (_chainedRide != null && !_chainingResponded)
                    _RideChainingBanner(
                      ride: _chainedRide!,
                      onAccept: () => _respondToChain(true),
                      onDecline: () => _respondToChain(false),
                    ),

                  AnimatedSwitcher(
                    duration: AnimationDuration.pageStateTransitionMobile,
                    child: Padding(
                      padding: const EdgeInsets.all(16).copyWith(bottom: 8),
                      child:
                          widget.state.order.status ==
                              OrderStatus.driverAccepted
                          ? SliderButton(
                              text: context.translate.slideToConfirmArrival,
                              onSlided: () {
                                HapticFeedback.mediumImpact();
                                locator<HomeBloc>().add(
                                  HomeEvent.onArrivedToPickupPoint(
                                    orderId: widget.state.order.id,
                                  ),
                                );
                              },
                            )
                          : widget.state.order.status == OrderStatus.arrived
                          ? SliderButton(
                              text: context.translate.slideToConfirmPickup,
                              onSlided: () {
                                HapticFeedback.mediumImpact();
                                if (widget.state.order.boardingPin != null) {
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (context) {
                                      final pinController = TextEditingController();
                                      return AlertDialog(
                                        title: const Row(
                                          children: [
                                            Icon(Ionicons.shield, color: ColorPalette.primary30),
                                            SizedBox(width: 8),
                                            Text("Confirmar PIN"),
                                          ],
                                        ),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text("Solicite o código de 4 dígitos ao passageiro para confirmar o embarque seguro:"),
                                            const SizedBox(height: 16),
                                            TextField(
                                              controller: pinController,
                                              keyboardType: TextInputType.number,
                                              maxLength: 4,
                                              decoration: const InputDecoration(
                                                hintText: "Digite o PIN",
                                                border: OutlineInputBorder(),
                                              ),
                                              style: const TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 8,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                            },
                                            child: const Text("Cancelar"),
                                          ),
                                          ElevatedButton(
                                            onPressed: () {
                                              final pin = pinController.text.trim();
                                              if (pin.length == 4) {
                                                Navigator.of(context).pop();
                                                locator<HomeBloc>().add(
                                                  HomeEvent.onStripStarted(
                                                    orderId: widget.state.order.id,
                                                    boardingPin: pin,
                                                  ),
                                                );
                                              }
                                            },
                                            child: const Text("Confirmar"),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                } else {
                                  locator<HomeBloc>().add(
                                    HomeEvent.onStripStarted(
                                      orderId: widget.state.order.id,
                                    ),
                                  );
                                }
                              },
                            )
                          : widget.state.order.status == OrderStatus.started
                          ? SliderButton(
                              text: context.translate.slideToConfirmDropoff,
                              onSlided: () {
                                HapticFeedback.mediumImpact();
                                // 🎙️ Lembrete por voz ativa (TTS) de prevenção de perdas (Pilar 22)
                                try {
                                  ArrivalReminderService().playArrivalReminder();
                                } catch (_) {}

                                locator<HomeBloc>().add(
                                  HomeEvent.onArrivedToDestination(
                                    order: widget.state.order,
                                    destinationArrivedTo:
                                        (widget
                                                .state
                                                .order
                                                .destinationArrivedTo ??
                                            -1) +
                                        1,
                                  ),
                                );
                              },
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Modelo de corrida encadeada ──
class _ChainedRide {
  final String nextOrderId;
  final String pickupAddress;
  final String destinationAddress;
  final int distanceToPickup;
  final double estimatedFare;

  const _ChainedRide({
    required this.nextOrderId,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.distanceToPickup,
    required this.estimatedFare,
  });
}

// ── Banner de Ride Chaining — padrão Uppi ──
class _RideChainingBanner extends StatelessWidget {
  final _ChainedRide ride;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _RideChainingBanner({
    required this.ride,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [ColorPalette.secondary40, ColorPalette.secondary30],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: ColorPalette.secondary40.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Ionicons.flash,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.translate.chainedRideAvailable,
                    style: context.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${ride.distanceToPickup}m',
                    style: context.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '📍 ${ride.pickupAddress}',
                style: context.bodySmall?.copyWith(color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '🏁 ${ride.destinationAddress}',
                style: context.bodySmall?.copyWith(color: Colors.white70),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (ride.estimatedFare > 0) ...[
                const SizedBox(height: 4),
                Text(
                  context.translate.rideEstimate('R\$ ${ride.estimatedFare.toStringAsFixed(2)}'),
                  style: context.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: onDecline,
                      child: Text(context.translate.decline),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: ColorPalette.secondary30,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        elevation: 0,
                      ),
                      onPressed: onAccept,
                      child: Text(
                        context.translate.acceptOrder,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
