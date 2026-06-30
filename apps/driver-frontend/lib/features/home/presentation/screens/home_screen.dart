import 'package:auto_route/auto_route.dart';
import 'package:uppi_motorista/core/blocs/auth_bloc.dart';
import 'package:uppi_motorista/core/enums/driver_status.dart';
import 'package:uppi_motorista/core/blocs/location.dart';
import 'package:uppi_motorista/core/datasources/location_datasource.dart';
import 'package:uppi_motorista/core/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:flutter_common/core/presentation/buttons/app_bordered_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../blocs/home.dart';
import 'home_screen.desktop.dart';
import 'home_screen.mobile.dart';

@RoutePage(name: 'DriverHomeRoute')
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AppLifecycleListener _listener;

  // Reatividade climática
  RealtimeChannel? _rainChannel;
  bool _isRaining = false;

  @override
  void initState() {
    _listener = AppLifecycleListener(onStateChange: _onStateChanged);
    locator<AuthBloc>().requestUserInfo();
    final locationBloc = locator<LocationBloc>();
    locationBloc.fetchCurrentLocation();
    
    final driverLocation = locationBloc.state.maybeMap(
      determined: (determined) => determined.location,
      orElse: () => null,
    );
    locator<HomeBloc>().onStarted(driverLocation: driverLocation);
    _startRainingRealtimeListener();
    super.initState();
  }

  void _startRainingRealtimeListener() {
    // 1. Busca estado inicial silenciosamente
    Supabase.instance.client
        .from('app_settings')
        .select('value')
        .eq('key', 'is_raining')
        .maybeSingle()
        .then((row) {
      if (row != null && mounted) {
        _isRaining = row['value']?.toString() == 'true';
      }
    });

    // 2. Escuta alterações em tempo real via CDC
    _rainChannel = Supabase.instance.client
        .channel('driver_settings_rain')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_settings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'key',
            value: 'is_raining',
          ),
          callback: (payload) {
            final newValue = payload.newRecord['value']?.toString() == 'true';
            if (newValue && !_isRaining) {
              _isRaining = true;
              if (mounted) {
                _showRainBonusDialog();
              }
            } else if (!newValue) {
              _isRaining = false;
            }
          },
        );
    try {
      _rainChannel!.subscribe();
    } catch (_) {}
  }

  void _showRainBonusDialog() {
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (context) => AppResponsiveDialog(
        type: context.responsive(DialogType.bottomSheet, xl: DialogType.dialog),
        iconColor: ColorPalette.primary40,
        header: (
          Icons.cloudy_snowing,
          '🌧️ Está Chovendo!',
          'A Uppi ativou o bônus climático de chuva em Castanhal!',
        ),
        primaryButton: AppBorderedButton(
          onPressed: () => Navigator.of(context).pop(),
          title: 'Aproveitar Bônus',
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ColorPalette.primary99,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: ColorPalette.primary70,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.celebration,
                      color: ColorPalette.primary30,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Promoção Uppi Taxa Zero na Chuva ativa! Passageiros viajam sem taxa, mas você ganha bônus de Multiplicador Surge Garantido pela Uppi! Fique online para faturar mais!',
                        style: context.bodyMedium?.copyWith(
                          color: ColorPalette.primary30,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    if (_rainChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_rainChannel!);
      } catch (_) {}
    }
    super.dispose();
  }

  void _onStateChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        locator<HomeBloc>().onStarted(
          driverLocation: locator<LocationBloc>().state.maybeMap(
            determined: (determined) => determined.location,
            orElse: () => null,
          ),
        );
        locator<AuthBloc>().requestUserInfo();

        break;

      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationBloc = locator<LocationBloc>();
    final homeBloc = locator<HomeBloc>();
    return Scaffold(
      body: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: locator<HomeBloc>()),
          BlocProvider.value(value: locator<LocationBloc>()),
        ],
        child: MultiBlocListener(
          listeners: [
            BlocListener<LocationBloc, LocationState>(
              listener: (context, state) {
                state.mapOrNull(
                  error: (error) =>
                      context.showSnackBar(message: error.error.name),
                  determined: (determined) =>
                      homeBloc.onLocationUpdated(location: determined.location),
                );
              },
            ),
            BlocListener<HomeBloc, HomeState>(
              listener: (context, state) {
                state.driverStatus.mapOrNull(
                  initial: (value) {
                    homeBloc.onStarted(
                      driverLocation: locator<LocationBloc>().state.maybeMap(
                        determined: (determined) => determined.location,
                        orElse: () => null,
                      ),
                    );
                    locator<AuthBloc>().requestUserInfo();
                  },
                  online: (_) {
                    locator<LocationDatasource>().updateLocationSettings(inRide: false);
                    locationBloc.startGettingLocationUpdates();
                  },
                  onTrip: (onTrip) {
                    locator<LocationDatasource>().updateLocationSettings(inRide: true);
                    locationBloc.startGettingLocationUpdates();
                  },
                  offline: (_) => locationBloc.stopGettingLocationUpdates(),
                  accessDenied: (value) {
                    final authState = locator<AuthBloc>().state;
                    final driverStatus = authState.mapOrNull(
                      authenticated: (a) => a.profile.status,
                    );
                    if (driverStatus is PendingApprovalState ||
                        driverStatus is SoftRejectState) {
                      return;
                    }
                    locator<AuthBloc>().onLoggedOut();
                    context.router.replace(const DriverAuthRoute());
                  },
                );
              },
            ),
            // if new request added play sound
            BlocListener<HomeBloc, HomeState>(
              listenWhen: (previous, current) => current.driverStatus.maybeMap(
                online: (online) =>
                    online.orderRequests.length >
                    previous.driverStatus.maybeMap(
                      online: (online) => online.orderRequests.length,
                      orElse: () => 0,
                    ),
                orElse: () => false,
              ),
              listener: (context, state) {
                FlutterRingtonePlayer().play(
                  fromAsset: "packages/uppi_motorista/assets/notification.mp3",
                  looping: false,
                  volume: 1.0,
                  asAlarm: true,
                );
              },
            ),
            BlocListener<HomeBloc, HomeState>(
              listenWhen: (previous, current) {
                final wasOnTrip = previous.driverStatus is OnTripDriverStatus;
                final isNotOnTrip = current.driverStatus is! OnTripDriverStatus;
                return wasOnTrip && isNotOnTrip;
              },
              listener: (context, state) {
                if (homeBloc.lastFinishedOrderStatus == OrderStatus.riderCanceled ||
                    homeBloc.lastFinishedOrderStatus == OrderStatus.expired) {
                  homeBloc.lastFinishedOrderStatus = null;
                  showDialog(
                    context: context,
                    useSafeArea: false,
                    builder: (context) => AppResponsiveDialog(
                      type: context.responsive(DialogType.bottomSheet, xl: DialogType.dialog),
                      iconColor: ColorPalette.semanticgreen30,
                      header: (
                        Icons.check_circle_outline_rounded,
                        'Corrida Cancelada',
                        'O passageiro cancelou a corrida.',
                      ),
                      primaryButton: AppBorderedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        title: 'Fechar',
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: ColorPalette.semanticgreen99,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: ColorPalette.semanticgreen70,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.account_balance_wallet_outlined,
                                    color: ColorPalette.semanticgreen30,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Compensação Recebida: Um valor de R\$ 5,00 foi creditado em sua carteira para compensar o seu tempo de deslocamento.',
                                      style: context.bodyMedium?.copyWith(
                                        color: ColorPalette.semanticgreen30,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
              },
            ),
          ],
          child: context.responsive(
            const HomeScreenMobile(),
            xl: const HomeScreenDesktop(),
          ),
        ),
      ),
    );
  }
}
