import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/features/surge/surge_widgets.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:flutter_common/core/entities/payment_method_union.dart';
import 'package:flutter_common/core/entities/ride_option.dart';
import 'package:rider_flutter/core/blocs/location.dart';
import 'package:rider_flutter/core/entities/service_category.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/buttons/app_back_button.dart';
import 'package:flutter_common/core/presentation/app_card_sheet.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/buttons/app_text_button.dart';
import 'package:flutter_common/core/presentation/card_handle.dart';
import 'package:rider_flutter/core/presentation/payment_method_select_field.dart';
import 'package:rider_flutter/features/home/features/apply_coupon/presentation/dialogs/enter_coupon_dialog.dart';
import 'package:rider_flutter/features/home/presentation/blocs/home.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_common/core/presentation/animated_driver_marker.dart';
import 'package:rider_flutter/features/home/features/order_preview/presentation/dialogs/identity_verification_dialog.dart';
import 'package:flutter_common/core/utils/uppi_haptics.dart';
import 'package:rider_flutter/features/home/presentation/components/home_map.dart';


import '../blocs/order_preview.dart';
import '../blocs/order_preview_args.dart';
import '../blocs/order_preview_options.dart';
import '../components/service_item.dart';
import '../dialogs/reserve_time_dialog.dart';
import '../dialogs/ride_preferences_dialog.dart';

class ServicesSelectionSheet extends StatefulWidget {
  final List<PaymentMethodUnion> paymentMethods;
  final List<ServiceCategoryEntity> serviceCategories;
  final String currency;

  const ServicesSelectionSheet({
    super.key,
    required this.paymentMethods,
    required this.serviceCategories,
    required this.currency,
  });

  @override
  State<ServicesSelectionSheet> createState() => _ServicesSelectionSheetState();
}

class _ServicesSelectionSheetState extends State<ServicesSelectionSheet>
    with TickerProviderStateMixin {
  double? _surgeMultiplier;
  bool _isRaining = false;
  bool _isExpanded = true;

  void _setExpanded(bool expanded) {
    if (_isExpanded != expanded) {
      setState(() {
        _isExpanded = expanded;
      });
      try {
        HomeMap.isPreviewExpanded.value = expanded;
      } catch (_) {}
    }
  }

  // Preferências de 1 Toque (Fase 19)
  final Set<String> _selectedPreferences = {};

  Future<void> _savePendingPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_ride_preferences', jsonEncode(_selectedPreferences.toList()));
    } catch (_) {}
  }

  void _togglePreference(String pref) {
    setState(() {
      if (_selectedPreferences.contains(pref)) {
        _selectedPreferences.remove(pref);
      } else {
        _selectedPreferences.add(pref);
      }
    });
    _savePendingPreferences();
  }

  @override
  void initState() {
    super.initState();
    _fetchSurgeMultiplier();
    _checkRainingStatus();
    _startRainingRealtimeListener();
    try {
      HomeMap.isPreviewExpanded.value = true;
    } catch (_) {}
  }

  @override
  void dispose() {
    UppiRainDetector.removeListener(_onRainChanged);
    try {
      HomeMap.isPreviewExpanded.value = false;
    } catch (_) {}
    super.dispose();
  }

  void _checkRainingStatus() {
    _isRaining = UppiRainDetector.isRaining;
  }

  void _startRainingRealtimeListener() {
    UppiRainDetector.addListener(_onRainChanged);
  }

  void _onRainChanged() {
    if (mounted) {
      setState(() {
        _isRaining = UppiRainDetector.isRaining;
      });
    }
  }

  Future<void> _fetchSurgeMultiplier() async {
    try {
      final locCubit = locator<LocationCubit>();
      final place = locCubit.state.place;
      final argsCubit = locator<OrderPreviewArgsCubit>();
      final waypoints = argsCubit.state.calculateFareArgs.waypoints;

      final pickup = waypoints.firstOrNull ?? place;
      if (pickup == null) return;

      final dropoff = waypoints.length >= 2 ? waypoints.last : pickup;

      final pLat = pickup.coordinates.lat;
      final pLng = pickup.coordinates.lng;
      final dLat = dropoff.coordinates.lat;
      final dLng = dropoff.coordinates.lng;

      final response = await Supabase.instance.client.rpc(
        'rpc_calculate_ride_fare',
        params: {
          'p_pickup_lat': pLat,
          'p_pickup_lng': pLng,
          'p_dropoff_lat': dLat,
          'p_dropoff_lng': dLng,
          'p_base_fare': 10.0,
        },
      );

      if (response != null) {
        final mult = (response['multiplier'] as num?)?.toDouble() ?? 1.0;
        if (mounted) {
          setState(() {
            _surgeMultiplier = mult;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching surge: $e');
      if (mounted) {
        setState(() {
          _surgeMultiplier = 1.0;
        });
      }
    }
  }



  @override
  Widget build(BuildContext context) {

    final optionsCubit = locator<OrderPreviewOptionsCubit>();
    final argsCubit = locator<OrderPreviewArgsCubit>();
    final remoteDataCubit = locator<OrderPreviewCubit>();

    return AppCardSheet(
      child: BlocBuilder<OrderPreviewOptionsCubit, OrderPreviewOptionsState>(
        builder: (context, stateOptions) {
          return SafeArea(
            top: false,
            child: DefaultTabController(
              length: widget.serviceCategories.length,
              initialIndex: stateOptions.selectedServiceCategory == null
                  ? 0
                  : widget.serviceCategories.indexOf(
                      widget.serviceCategories.firstWhere(
                        (e) => e.id == stateOptions.selectedServiceCategory?.id,
                        orElse: () => widget.serviceCategories.first,
                      ),
                    ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragEnd: (details) {
                      if (details.primaryVelocity != null) {
                        if (details.primaryVelocity! < -100 && !_isExpanded) {
                          UppiHaptics.selection();
                          _setExpanded(true);
                        } else if (details.primaryVelocity! > 100 && _isExpanded) {
                          UppiHaptics.selection();
                          _setExpanded(false);
                        }
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: context.responsive(
                            const CardHandle(),
                            xl: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: AppBackButton(
                                onPressed: () =>
                                    locator<HomeCubit>().initializeWelcome(
                                  pickupPoint: locator<LocationCubit>().state.place,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Visibility(
                          visible: _isExpanded && widget.serviceCategories.length > 1,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: SegmentedButton<ServiceCategoryEntity?>(
                              multiSelectionEnabled: false,
                              onSelectionChanged: (value) =>
                                  optionsCubit.onServiceCategorySelected(value.first!),
                              segments: widget.serviceCategories
                                  .map(
                                    (e) => ButtonSegment(
                                      value: e,
                                      label: Text(e.name),
                                    ),
                                  )
                                  .toList(),
                              selected: {stateOptions.selectedServiceCategory},
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Letreiro animado Taxa Zero na Chuva
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    child: _isRaining
                        ? Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [ColorPalette.primary40, ColorPalette.primary20],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: ColorPalette.primary40.withValues(alpha: 0.15),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: const Row(
                              children: [
                                Icon(Ionicons.umbrella, color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Somente no Uppi: Taxa Zero na Chuva! 🌧️',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _isExpanded
                          ? SizedBox(
                              height: context.responsive(290),
                              child: TabBarView(
                                physics: const NeverScrollableScrollPhysics(),
                                controller: TabController(
                                  length: widget.serviceCategories.length,
                                  initialIndex: stateOptions.selectedServiceCategory == null
                                      ? 0
                                      : widget.serviceCategories.indexOf(
                                          widget.serviceCategories.firstWhere(
                                            (e) => e.id == stateOptions.selectedServiceCategory?.id,
                                            orElse: () => widget.serviceCategories.first,
                                          ),
                                        ),
                                  vsync: this,
                                ),
                                children: widget.serviceCategories.mapIndexed(
                                  (index, e) {
                                    return ListView.separated(
                                      padding: EdgeInsets.zero,
                                      itemCount: e.services.length,
                                      separatorBuilder: (context, index) =>
                                          const Divider(
                                            height: 8,
                                            thickness: 0.5,
                                            color: ColorPalette.neutral95,
                                            indent: 68,
                                          ),
                                      itemBuilder: (context, index) {
                                        return ServiceItem(
                                          currency: widget.currency,
                                          entity: e.services[index],
                                          isSelected: stateOptions.selectedService?.id ==
                                              e.services[index].id,
                                          surgeMultiplier: _surgeMultiplier,
                                          onPressed: () {
                                            UppiHaptics.selection();
                                            optionsCubit.onServiceSelected(e.services[index]);
                                          },
                                        );
                                      },
                                    );
                                  },
                                ).toList(),
                              ),
                            )
                          : (stateOptions.selectedService != null
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                                  child: ServiceItem(
                                    currency: widget.currency,
                                    entity: stateOptions.selectedService!,
                                    isSelected: true,
                                    surgeMultiplier: _surgeMultiplier,
                                    onPressed: () {
                                      UppiHaptics.selection();
                                      _setExpanded(true);
                                    },
                                  ),
                                )
                              : const SizedBox.shrink()),
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

                  // ── Surge Banner para o passageiro ──
                  BlocBuilder<LocationCubit, LocationState>(
                    builder: (context, locState) {
                      final place = locState.place;
                      if (place == null) return const SizedBox.shrink();
                      return _SurgeInfoWidget(
                        lat: place.coordinates.lat,
                        lng: place.coordinates.lng,
                      );
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Chips de Preferências com 1 Toque (Fase 19) ──
                        AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          child: _isExpanded
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        _buildPreferenceChip('silent', Ionicons.volume_mute, 'Silêncio'),
                                        _buildPreferenceChip('ac', Ionicons.snow, 'Ar Frio'),
                                        _buildPreferenceChip('chat', Ionicons.chatbubbles, 'Conversar'),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ),
                        PaymentMethodSelectField(
                          paymentMethod: stateOptions.paymentMethod,
                          onPressed: remoteDataCubit.goToPaymentMethodPage,
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          child: _isExpanded
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Divider(
                                      color: ColorPalette.neutral95,
                                      height: 24,
                                    ),
                                    Row(
                                      children: [
                                        BlocBuilder<OrderPreviewArgsCubit,
                                            OrderPreviewArgsState>(
                                          builder: (context, state) {
                                            return AppTextButton(
                                                isDense: true,
                                                badge: state.rideOptions.length +
                                                    (state.isTwoWay ? 1 : 0) +
                                                    (state.waitTime == null ? 0 : 1),
                                                text: context.translate.ridePreferences,
                                                iconData: Ionicons.options,
                                                onPressed: () async {
                                                  final dialogResult = await showDialog<
                                                      (bool, int?, List<RideOptionEntity>)>(
                                                    context: context,
                                                    useSafeArea: false,
                                                    builder: (context) =>
                                                        RidePreferencesDialog(
                                                      currency: widget.currency,
                                                      selectedRideOptions:
                                                          argsCubit.state.rideOptions,
                                                      rideOptions: optionsCubit
                                                              .state
                                                              .selectedService
                                                              ?.rideOptions ??
                                                          [],
                                                      isTwoWayTrip:
                                                          argsCubit.state.isTwoWay,
                                                      defaultWaitTime:
                                                          argsCubit.state.waitTime,
                                                    ),
                                                  );
                                                  if (dialogResult != null) {
                                                    argsCubit.onRidePreferencesChanged(
                                                      isTwoWayTrip: dialogResult.$1,
                                                      waitTime: dialogResult.$2,
                                                      rideOptions: dialogResult.$3,
                                                    );
                                                  }
                                                });
                                          },
                                        ),
                                        const Spacer(),
                                        AppTextButton(
                                          isDense: true,
                                          text: context.translate.couponCode,
                                          iconData: Ionicons.ticket,
                                          onPressed: () async {
                                            final dialogResult = await showDialog<String>(
                                              context: context,
                                              useSafeArea: false,
                                              builder: (context) => EnterCouponDialog(
                                                calculateFareArgs:
                                                    argsCubit.state.calculateFareArgs,
                                              ),
                                            );
                                            if (dialogResult != null) {
                                              argsCubit.onCouponCodeChanged(dialogResult);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                )
                              : const SizedBox(height: 12),
                        ),
                        BlocBuilder<OrderPreviewCubit, OrderPreviewState>(
                          builder: (context, state) {
                            return Row(
                              children: [
                                if (_isExpanded) ...[
                                  AppPrimaryButton(
                                    isDisabled:
                                        stateOptions.canConfirm == false ||
                                            state.isLoading,
                                    onPressed: () async {
                                      final isVerified =
                                          await _checkIdentityVerification(
                                              context);
                                      if (!isVerified) return;

                                      try {
                                        final result = await showDialog<DateTime>(
                                          context: context,
                                          useSafeArea: false,
                                          builder: (context) =>
                                              const ReserveTimeDialog(),
                                        );
                                        if (result != null) {
                                          remoteDataCubit.confirmRide(
                                            pickupTime: result,
                                            args:
                                                argsCubit.state.calculateFareArgs,
                                            selectedPaymentMethod:
                                                stateOptions.paymentMethod!,
                                            selectedService:
                                                stateOptions.selectedService!,
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      'Erro ao agendar corrida. Tente novamente.')));
                                        }
                                      }
                                    },
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 200),
                                      child: state.isLoading
                                          ? const SizedBox(
                                              key: ValueKey('spinner_cal'),
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                              ),
                                            )
                                          : const Icon(
                                              key: ValueKey('icon_cal'),
                                              Ionicons.calendar,
                                              color: Colors.white,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                ],
                                Expanded(
                                  child: AppPrimaryButton(
                                    isDisabled:
                                        stateOptions.selectedService == null ||
                                            state.isLoading,
                                    onPressed: () async {
                                      if (stateOptions.paymentMethod == null) {
                                        remoteDataCubit.goToPaymentMethodPage();
                                        return;
                                      }

                                      final isVerified =
                                          await _checkIdentityVerification(
                                              context);
                                      if (!isVerified) return;

                                      try {
                                        remoteDataCubit.confirmRide(
                                          pickupTime: DateTime.now(),
                                          args:
                                              argsCubit.state.calculateFareArgs,
                                          selectedPaymentMethod:
                                              stateOptions.paymentMethod!,
                                          selectedService:
                                              stateOptions.selectedService!,
                                        );
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      'Erro ao solicitar corrida. Tente novamente.')));
                                        }
                                      }
                                    },
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 200),
                                      child: state.isLoading
                                          ? const SizedBox(
                                              key: ValueKey('loading'),
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                valueColor: AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                              ),
                                            )
                                          : Column(
                                              key: const ValueKey('text'),
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  context.translate.bookNow,
                                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                                ),
                                                if (stateOptions.selectedService != null)
                                                  Text(
                                                    stateOptions.selectedService!.name,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.normal,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _checkIdentityVerification(BuildContext context) async {
    try {
      final supabase = Supabase.instance.client;
      final uid =
          supabase.auth.currentUser?.id ?? locator<FirebaseDatasource>().uid;

      if (uid != null) {
        final profile = await supabase
            .from('profiles')
            .select('identity_verification_status')
            .eq('id', uid)
            .maybeSingle();

        final status =
            profile?['identity_verification_status'] as String? ?? 'unverified';

        if (status == 'approved' || status == 'pending') {
          return true; // Já verificado ou aguardando
        }
      }

      if (context.mounted) {
        final verified = await showDialog<bool>(
          context: context,
          useSafeArea: false,
          builder: (context) => const IdentityVerificationDialog(),
        );
        return verified == true;
      }
      return false;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Erro ao verificar identidade. Tente novamente.')));
      }
      return false;
    }
  }

  Widget _buildPreferenceChip(String key, IconData icon, String label) {
    final isSelected = _selectedPreferences.contains(key);
    return Expanded(
      child: GestureDetector(
        onTap: () => _togglePreference(key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? ColorPalette.primary40 : ColorPalette.primary95,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.transparent : ColorPalette.primary95,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? Colors.white : ColorPalette.primary40,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : ColorPalette.primary30,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget que busca o surge e exibe SurgeBanner se > 1.0
class _SurgeInfoWidget extends StatefulWidget {
  final double lat;
  final double lng;

  const _SurgeInfoWidget({required this.lat, required this.lng});

  @override
  State<_SurgeInfoWidget> createState() => _SurgeInfoWidgetState();
}

class _SurgeInfoWidgetState extends State<_SurgeInfoWidget> {
  double? _multiplier;
  bool _fetched = false;

  @override
  void initState() {
    super.initState();
    _fetchSurge();
  }

  Future<void> _fetchSurge() async {
    try {
      final response = await Supabase.instance.client.rpc(
        'rpc_calculate_ride_fare',
        params: {
          'p_pickup_lat': widget.lat,
          'p_pickup_lng': widget.lng,
          'p_dropoff_lat': widget.lat,
          'p_dropoff_lng': widget.lng,
          'p_base_fare': 10.0,
        },
      );

      if (mounted && response != null) {
        setState(() {
          _multiplier = (response['multiplier'] as num?)?.toDouble() ?? 1.0;
          _fetched = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _fetched = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_fetched || _multiplier == null || _multiplier! <= 1.0) {
      return const SizedBox.shrink();
    }
    return SurgeBanner(multiplier: _multiplier!);
  }
}
