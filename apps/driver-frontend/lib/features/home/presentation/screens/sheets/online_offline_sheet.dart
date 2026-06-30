import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:uppi_motorista/core/blocs/auth_bloc.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/features/home/presentation/blocs/home.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/theme/animation_duration.dart';
import 'package:ionicons/ionicons.dart';
import 'dart:async';
import 'package:flutter/material.dart';

import '../../components/notice_bar_content.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:flutter_common/features/surge/surge_widgets.dart';
import 'package:uppi_motorista/core/enums/driver_status.dart';
import 'package:uppi_motorista/features/home/presentation/widgets/go_home_mode_button.dart';
import 'package:uppi_motorista/features/home/presentation/components/daily_challenges_widget.dart';
import 'rides_radar_sheet.dart';

class OnlineOfflineSheet extends StatefulWidget {
  final HomeState state;

  const OnlineOfflineSheet({super.key, required this.state});

  @override
  State<OnlineOfflineSheet> createState() => _OnlineOfflineSheetState();
}

class _OnlineOfflineSheetState extends State<OnlineOfflineSheet> {
  bool _checkingVerification = false;

  Future<void> _handleGoOnline(BuildContext context) async {
    final supabase = Supabase.instance.client;
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    // Procede para ficar online diretamente
    locator<HomeBloc>().add(HomeEvent.onStatusChanged(status: const DriverStatus.online()));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ColorPalette.primary20,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: AnimationDuration.pageStateTransitionMobile,
            child: widget.state.driverStatus.maybeMap(
              orElse: () => const SizedBox(),
              online: (online) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => locator<HomeBloc>()
                              .add(HomeEvent.onStatusChanged(status: const DriverStatus.offline())),
                          child: NoticeBarContent(
                            icon: Ionicons.search,
                            text: context.translate.driverOnlineTitle,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (context) => RidesRadarSheet(
                              driverLocation: widget.state.driverLocation,
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Ionicons.radio,
                                color: Colors.orangeAccent,
                                size: 16,
                              ),
                              SizedBox(width: 4),
                              Text(
                                "Radar",
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (widget.state.driverLocation != null)
                        _SurgeBadgeFetcher(
                          lat: widget.state.driverLocation!.lat,
                          lng: widget.state.driverLocation!.lng,
                        ),
                    ],
                  ),
                  const GoHomeModeButton(),
                ],
              ),
              offline: (offline) => _checkingVerification
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CupertinoActivityIndicator(color: Colors.white),
                      ),
                    )
                  : CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () async {
                        setState(() => _checkingVerification = true);
                        await _handleGoOnline(context);
                        if (mounted) {
                          setState(() => _checkingVerification = false);
                        }
                      },
                      child: NoticeBarContent(
                        icon: Ionicons.car,
                        text: context.translate.driverOfflineTitle,
                      ),
                    ),
              accessDenied: (accessDenied) => const SizedBox(),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              color: context.theme.colorScheme.surface,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(color: ColorPalette.neutral90),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Ionicons.wallet,
                            color: ColorPalette.primary30,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            context.translate.yourBalance,
                            style: context.labelLarge,
                          ),
                        ),
                        BlocBuilder<AuthBloc, AuthState>(
                          builder: (context, state) {
                            return state.map(
                              authenticated: (value) => Text(
                                (value.profile.mainWallet?.balance ?? 0)
                                    .formatCurrency(
                                      value.profile.mainWallet?.currency ?? "BRL",
                                    ),
                                style: context.labelLarge,
                              ),
                              unauthenticated: (value) => const SizedBox(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  if (widget.state.driverStatus is OnlineDriverStatus) ...[
                    Container(
                      height: 1,
                      color: ColorPalette.neutral90,
                    ),
                    const DailyChallengesWidget(),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SurgeBadgeFetcher extends StatefulWidget {
  final double lat;
  final double lng;

  const _SurgeBadgeFetcher({required this.lat, required this.lng});

  @override
  State<_SurgeBadgeFetcher> createState() => _SurgeBadgeFetcherState();
}

class _SurgeBadgeFetcherState extends State<_SurgeBadgeFetcher> {
  double? _multiplier;
  DateTime? _lastFetch;
  RealtimeChannel? _surgeRealtimeChannel;
  bool _fetching = false;

  static const _cacheDuration = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _fetchSurge();
    _startSurgeRealtimeListener();
  }

  void _startSurgeRealtimeListener() {
    _surgeRealtimeChannel?.unsubscribe();
    _surgeRealtimeChannel = Supabase.instance.client
        .channel('public:surge_zones')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'surge_zones',
          callback: (payload) {
            _fetchSurge();
          },
        );
    _surgeRealtimeChannel!.subscribe();
  }

  @override
  void didUpdateWidget(_SurgeBadgeFetcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    final expired =
        _lastFetch == null ||
        DateTime.now().difference(_lastFetch!) > _cacheDuration;
    final moved =
        (oldWidget.lat - widget.lat).abs() > 0.01 ||
        (oldWidget.lng - widget.lng).abs() > 0.01;
    if (expired && moved) {
      _fetchSurge();
    }
  }

  Future<void> _fetchSurge() async {
    if (_fetching) return;
    _fetching = true;

    try {
      final idToken = Supabase.instance.client.auth.currentSession?.accessToken;
      if (idToken == null) throw Exception("Could not get auth token");

      final response = await http.post(
        Uri.parse('${dotenv.env['SUPABASE_URL']}/functions/v1/calculate-surge'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'data': {'lat': widget.lat, 'lng': widget.lng},
        }),
      );
      final responseBody = response.body;
      final responseJson = jsonDecode(responseBody);
      final data = responseJson['result'] as Map<String, dynamic>? ?? {};

      if (mounted) {
        setState(() {
          _multiplier = (data['multiplier'] as num?)?.toDouble() ?? 1.0;
          _lastFetch = DateTime.now();
        });
      }
    } catch (_) {
    } finally {
      _fetching = false;
    }
  }

  @override
  void dispose() {
    _surgeRealtimeChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_multiplier == null || _multiplier! <= 1.1) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: SurgeBadge(multiplier: _multiplier!),
    );
  }
}
