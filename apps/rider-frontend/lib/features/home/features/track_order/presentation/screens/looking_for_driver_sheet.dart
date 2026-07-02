import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_dialog_header.dart';
import 'package:ionicons/ionicons.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/app_card_sheet.dart';
import 'package:rider_flutter/gen/assets.gen.dart';
import 'package:flutter_common/core/utils/uppi_haptics.dart';

import 'package:rider_flutter/features/home/presentation/blocs/home.dart';
import 'package:rider_flutter/core/blocs/location.dart';
import 'package:rider_flutter/core/entities/order.dart';

import '../blocs/track_order.dart';

class LookingForDriverSheet extends StatefulWidget {
  const LookingForDriverSheet({super.key});

  @override
  State<LookingForDriverSheet> createState() => _LookingForDriverSheetState();
}

class _LookingForDriverSheetState extends State<LookingForDriverSheet> {
  late Timer _textTimer;
  late Timer _elapsedTimer;
  int _textStep = 0;
  int _elapsedSeconds = 0;

  List<String> _getStatusTexts(BuildContext context) {
    if (Localizations.localeOf(context).languageCode == 'en') {
      return [
        "Searching for nearby partner drivers...",
        "Locating the most ideal driver...",
        "Sending trip offer...",
        "Expanding search radius for greater coverage...",
        "Optimizing approach route...",
      ];
    }
    return [
      "Buscando motoristas parceiros próximos...",
      "Localizando o motorista mais ideal...",
      "Enviando oferta de viagem...",
      "Expandindo raio de busca para maior cobertura...",
      "Otimizando rota de aproximação...",
    ];
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return "${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}";
  }

  @override
  void initState() {
    super.initState();

    _textTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) {
        setState(() {
          _textStep = (_textStep + 1) % _getStatusTexts(context).length;
        });
      }
    });

    // Initialize elapsed seconds from the order creation time if available
    final trackOrderBloc = locator<TrackOrderBloc>();
    trackOrderBloc.state.maybeMap(
      orderInProgres: (inProgress) {
        final diff = DateTime.now().difference(inProgress.order.createdAt.toLocal()).inSeconds;
        _elapsedSeconds = diff > 0 ? diff : 0;
      },
      orElse: () {},
    );

    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedSeconds++;
        });
      }
    });
  }

  @override
  void dispose() {
    _textTimer.cancel();
    _elapsedTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusTexts = _getStatusTexts(context);
    return AppCardSheet(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppDialogHeader(
                icon: Ionicons.car_sport,
                title: context.translate.rideRequested,
                subtitle: context.translate.searchingForAnOnlineDriver,
              ),
              const SizedBox(height: 8),
              
              SizedBox(
                height: 120,
                width: 120,
                child: Assets.lottie.looking.lottie(
                  height: 120,
                  width: 120,
                  fit: BoxFit.cover,
                ),
              ),
              
              const SizedBox(height: 16),

              // Premium Cronômetro
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Ionicons.stopwatch_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDuration(_elapsedSeconds),
                      style: context.titleMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              
              // Reactive Gradual Status Text
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.0, 0.2),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  statusTexts[_textStep],
                  key: ValueKey<int>(_textStep),
                  textAlign: TextAlign.center,
                  style: context.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.85),
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Premium Cancel Button
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  color: Colors.red.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(28),
                  onPressed: () {
                    UppiHaptics.errorAlert();
                    final trackOrderBloc = locator<TrackOrderBloc>();
                    final trackState = trackOrderBloc.state;

                    trackOrderBloc.cancelRide(cancelReasonId: null, cancelReasonNote: null);

                    OrderEntity? order;
                    trackState.maybeMap(
                      orderInProgres: (inProgress) => order = inProgress.order,
                      orElse: () => null,
                    );

                    locator.resetLazySingleton<TrackOrderBloc>();

                    if (order != null) {
                      locator<HomeCubit>().showPreview(
                        waypoints: order!.waypoints,
                        directions: order!.rideDirections,
                      );
                    } else {
                      locator<HomeCubit>().initializeWelcome(
                        pickupPoint: locator<LocationCubit>().state.place,
                      );
                    }
                  },
                  child: Text(
                    context.translate.cancelRide,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
