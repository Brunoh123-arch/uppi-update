// ignore_for_file: use_build_context_synchronously

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/blocs/location.dart';
import 'package:uppi_motorista/core/datasources/location_datasource.dart';
import 'package:uppi_motorista/core/enums/driver_status.dart';
import 'package:uppi_motorista/core/enums/location_permission.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:ionicons/ionicons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:auto_route/auto_route.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_common/core/entities/announcement.dart';
import 'package:uppi_motorista/features/announcements/presentation/blocs/announcements.dart';
import 'package:uppi_motorista/core/router/app_router.dart';

import '../blocs/home.dart';
import '../dialogs/location_permission_denied_forever_dialog.dart';
import '../dialogs/location_permission_request_dialog.dart';
import '../dialogs/background_location_permission_denied_dialog.dart';

class TopNavBar extends StatelessWidget {
  final Function()? onMenuButtonPressed;
  final BorderRadiusGeometry borderRadius;

  const TopNavBar({
    super.key,
    this.onMenuButtonPressed,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: context.theme.colorScheme.surface,
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: const Color(0xff64748B).withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        child: BlocBuilder<HomeBloc, HomeState>(
          builder: (context, state) {
            return Stack(
              children: [
                if (onMenuButtonPressed != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CupertinoButton(
                          onPressed: onMenuButtonPressed,
                          padding: const EdgeInsets.all(8),
                          minimumSize: Size(0, 0),
                          child: const Icon(
                            Ionicons.menu,
                            color: ColorPalette.neutral50,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const _NotificationBellWidget(),
                      ],
                    ),
                  ),
                Positioned.fill(
                  child: Center(
                    child: state.driverStatus.map(
                      initial: (_) => FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              context.translate.offline,
                              style: context.titleSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 2),
                            const _EarningsTodayWidget(),
                          ],
                        ),
                      ),
                      loading: (_) => const CupertinoActivityIndicator(),
                      online: (_) => FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              context.translate.online,
                              style: context.titleSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 2),
                            const _EarningsTodayWidget(),
                          ],
                        ),
                      ),
                      offline: (_) => FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              context.translate.offline,
                              style: context.titleSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 2),
                            const _EarningsTodayWidget(),
                          ],
                        ),
                      ),
                      onTrip: (_) => Text(
                        context.translate.onTrip,
                        style: context.titleSmall,
                        textAlign: TextAlign.center,
                      ),
                      accessDenied: (_) => Text(
                        context.translate.accessDenied,
                        style: context.titleSmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: switch (state.driverStatus) {
                    InitialDriverStatus() => CupertinoSwitch(
                      value: false,
                      onChanged: (_) async {
                        final homeBloc = locator<HomeBloc>();
                        final locationDatsource = locator<LocationDatasource>();

                        try {
                          final locationPermissionGranted =
                              await locationDatsource
                                  .getLocationPermissionStatus();
                          switch (locationPermissionGranted) {
                            case LocationPermission.denied:
                              final permissionResult = await showDialog(
                                context: context,
                                useSafeArea: false,
                                builder: (context) =>
                                    const LocationPermissionRequestDialog(),
                              );
                              if (permissionResult == false) {
                                return;
                              }
                              break;
                            case LocationPermission.deniedForever:
                              showDialog(
                                context: context,
                                useSafeArea: false,
                                builder: (context) =>
                                    const LocationPermissionDeniedForeverDialog(),
                              );
                              return;
                            case LocationPermission.whileInUse:
                              if (!kIsWeb) {
                                showDialog(
                                  context: context,
                                  useSafeArea: false,
                                  builder: (context) =>
                                      const BackgroundLocationPermissionDeniedDialog(),
                                );
                                return;
                              }
                              break;
                            case LocationPermission.always:
                              break;
                          }
                          // GPS desligado → tenta habilitar; se não der, aborta.
                          // (O onStatusChanged(online) único fica após o try,
                          // senão a chamada ao servidor disparava em dobro.)
                          final locationServiceEnabled = await locationDatsource
                              .isLocationServiceEnabled();
                          if (!locationServiceEnabled) {
                            final serviceEnabled = await locationDatsource
                                .requestLocationService();
                            if (!serviceEnabled) {
                              return;
                            }
                          }
                        } catch (error) {
                          debugPrint("Erro ao verificar permissão de localização: $error");
                        }

                        homeBloc.onStatusChanged(const DriverStatus.online());
                        locator<LocationBloc>().state.mapOrNull(
                          determined: (determined) {
                            locator<HomeBloc>().onLocationUpdated(
                              location: determined.location,
                              forceUpdate: true,
                            );
                          },
                        );
                      },
                      activeTrackColor: ColorPalette.semanticgreen60,
                    ),
                    LoadingDriverStatus() => const CupertinoActivityIndicator(),
                    AccessDeniedDriverStatus() => const SizedBox(),
                    OnTripDriverStatus() => const SizedBox(),
                    OnlineDriverStatus() => CupertinoSwitch(
                      value: true,
                      onChanged: (_) async {
                        locator<HomeBloc>().onStatusChanged(
                          const DriverStatus.offline(),
                        );
                      },
                      activeTrackColor: ColorPalette.semanticgreen60,
                    ),
                    OfflineDriverStatus() => CupertinoSwitch(
                      value: false,
                      onChanged: (_) async {
                        final homeBloc = locator<HomeBloc>();
                        final locationDatsource = locator<LocationDatasource>();

                        try {
                          final locationPermissionGranted =
                              await locationDatsource
                                  .getLocationPermissionStatus();
                          switch (locationPermissionGranted) {
                            case LocationPermission.denied:
                              final permissionResult = await showDialog(
                                context: context,
                                useSafeArea: false,
                                builder: (context) =>
                                    const LocationPermissionRequestDialog(),
                              );
                              if (permissionResult == false) {
                                return;
                              }
                              break;
                            case LocationPermission.deniedForever:
                              showDialog(
                                context: context,
                                useSafeArea: false,
                                builder: (context) =>
                                    const LocationPermissionDeniedForeverDialog(),
                              );
                              return;
                            case LocationPermission.whileInUse:
                              if (!kIsWeb) {
                                showDialog(
                                  context: context,
                                  useSafeArea: false,
                                  builder: (context) =>
                                      const BackgroundLocationPermissionDeniedDialog(),
                                );
                                return;
                              }
                              break;
                            case LocationPermission.always:
                              break;
                          }
                          // GPS desligado → tenta habilitar; se não der, aborta.
                          // (O onStatusChanged(online) único fica após o try,
                          // senão a chamada ao servidor disparava em dobro.)
                          final locationServiceEnabled = await locationDatsource
                              .isLocationServiceEnabled();
                          if (!locationServiceEnabled) {
                            final serviceEnabled = await locationDatsource
                                .requestLocationService();
                            if (!serviceEnabled) {
                              return;
                            }
                          }
                        } catch (error) {
                          // Em caso de falha (ex: Web), logar o erro e forçar online para permitir testes
                          debugPrint("Erro ao verificar permissão de localização: $error");
                        }

                        homeBloc.onStatusChanged(const DriverStatus.online());
                        locator<LocationBloc>().state.mapOrNull(
                          determined: (determined) {
                            locator<HomeBloc>().onLocationUpdated(
                              location: determined.location,
                              forceUpdate: true,
                            );
                          },
                        );
                      },
                      activeTrackColor: ColorPalette.semanticgreen60,
                    ),
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EarningsTodayWidget extends StatefulWidget {
  const _EarningsTodayWidget();

  @override
  State<_EarningsTodayWidget> createState() => _EarningsTodayWidgetState();
}

class _EarningsTodayWidgetState extends State<_EarningsTodayWidget> {
  double _earnings = 0.0;
  bool _isLoading = true;
  RealtimeChannel? _earningsChannel;

  @override
  void initState() {
    super.initState();
    _fetchEarnings();
    _startEarningsListener();
  }

  Future<void> _fetchEarnings() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      // Cria a data de início do dia local e converte para UTC com offset correto (ex: 2026-06-10T03:00:00.000Z)
      final now = DateTime.now();
      final localStartOfDay = DateTime(now.year, now.month, now.day);
      final startOfDayUtc = localStartOfDay.toUtc().toIso8601String();

      // 🛡️ Ganhos REAIS do dia: somar o valor líquido gravado pelo servidor em
      // `driver_earnings` (tarifa − comissão), NUNCA a tarifa bruta de `rides`.
      // Somar a tarifa bruta inflava o "Hoje" assim que a comissão deixasse de
      // ser zero, divergindo da carteira e da tela de Ganhos.
      final result = await Supabase.instance.client
          .from('driver_earnings')
          .select('net_amount')
          .eq('driver_id', uid)
          .gte('created_at', startOfDayUtc);

      double sum = 0.0;
      for (final row in result) {
        sum += (row['net_amount'] as num?)?.toDouble() ?? 0.0;
      }

      // Gorjetas/incentivos (Uppi Flex) são repassados 100% ao motorista, mas
      // não ficam em `driver_earnings` — somar do livro-razão da carteira.
      try {
        final tipRows = await Supabase.instance.client
            .from('wallet_transactions')
            .select('amount')
            .eq('user_id', uid)
            .eq('type', 'tip_incentive')
            .eq('status', 'completed')
            .gte('created_at', startOfDayUtc);
        for (final t in tipRows) {
          sum += ((t['amount'] as num?)?.toDouble() ?? 0.0).abs();
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _earnings = sum;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startEarningsListener() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    _earningsChannel = Supabase.instance.client
        .channel('driver_earnings_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rides',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: uid,
          ),
          callback: (payload) {
            _fetchEarnings();
          },
        );
    try {
      _earningsChannel!.subscribe();
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_earningsChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_earningsChannel!);
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: ColorPalette.primary40,
        ),
      );
    }

    return Text(
      'Hoje: R\$ ${_earnings.toStringAsFixed(2)}',
      style: context.bodySmall?.copyWith(
        color: ColorPalette.primary40,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _NotificationBellWidget extends StatefulWidget {
  const _NotificationBellWidget();

  @override
  State<_NotificationBellWidget> createState() => _NotificationBellWidgetState();
}

class _NotificationBellWidgetState extends State<_NotificationBellWidget> {
  List<String> _readIds = [];
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _initPrefs();
    try {
      locator<AnnouncementsBloc>().load();
    } catch (_) {}
  }

  Future<void> _initPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _prefs = p;
          _readIds = p.getStringList('read_announcements') ?? [];
        });
      }
    } catch (_) {}
  }

  Future<void> _markAllAsRead(List<String> currentIds) async {
    if (_prefs == null) return;
    try {
      final updatedIds = {..._readIds, ...currentIds}.toList();
      await _prefs!.setStringList('read_announcements', updatedIds);
      if (mounted) {
        setState(() {
          _readIds = updatedIds;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AnnouncementsBloc>.value(
      value: locator<AnnouncementsBloc>(),
      child: BlocBuilder<AnnouncementsBloc, AnnouncementsState>(
        builder: (context, state) {
          final announcements = state.maybeMap(
            loaded: (loaded) => loaded.data,
            orElse: () => const <AnnouncementEntity>[],
          );

          final currentIds = announcements.map((a) => a.id).cast<String>().toList();
          final unreadCount = announcements.where((a) => !_readIds.contains(a.id)).length;

          return CupertinoButton(
            onPressed: () async {
              if (currentIds.isNotEmpty) {
                await _markAllAsRead(currentIds);
              }
              context.router.push(const DriverAnnouncementsRoute());
            },
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            minimumSize: Size.zero,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Ionicons.notifications_outline,
                  color: ColorPalette.neutral50,
                  size: 26,
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
