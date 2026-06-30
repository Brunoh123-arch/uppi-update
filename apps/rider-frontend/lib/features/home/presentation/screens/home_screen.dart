import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/gen/assets.gen.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/blocs/auth_bloc.dart';
import 'package:rider_flutter/core/blocs/location.dart';
import 'package:flutter_common/core/blocs/settings.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:rider_flutter/features/home/presentation/blocs/home.dart';
import 'package:rider_flutter/features/home/presentation/blocs/place_confirm.dart';

import '../blocs/destination_suggestions.dart';
import '../dialogs/location_permission_request_dialog.dart';
import 'home_screen.desktop.dart';
import 'home_screen.mobile.dart';

@RoutePage()
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AppLifecycleListener _listener;
  bool _isPermissionDialogOpen = false; // Flag para evitar loops de diálogo na Web
  bool _userSkippedPermission = false; // Flag para não reabrir após dismissal manual

  final locationCubit = locator<LocationCubit>();
  final homeCubit = locator<HomeCubit>();
  final authBloc = locator<AuthBloc>();
  final settingsCubit = locator<SettingsCubit>();

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onStateChange: _onStateChanged,
    );
    locationCubit.fetchCurrentLocation(
      language: settingsCubit.state.locale,
      mapProvider: settingsCubit.state.mapProviderEnum,
    );
    locationCubit.state.mapOrNull(
      determined: (determined) {
        homeCubit.initializeWelcome(
          pickupPoint: determined.place,
        );
      },
    );
    homeCubit.onStarted(
      authenticated: authBloc.state.isAuthenticated,
      currentLocationPlace: locationCubit.state.place,
    );
    authBloc.state.mapOrNull(
      authenticated: (authenticated) {
        authBloc.requestUserInfo();
        locator<DestinationSuggestionsCubit>().onStarted();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(Assets.images.carTopView.provider(), context);
    precacheImage(Assets.images.motoTopView.provider(), context);
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  void _onStateChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_isPermissionDialogOpen && !_userSkippedPermission) {
          locationCubit.fetchCurrentLocation(
            language: settingsCubit.state.locale,
            mapProvider: settingsCubit.state.mapProviderEnum,
          );
        }
        homeCubit.onStarted(
          authenticated: authBloc.state.isAuthenticated,
          currentLocationPlace: locationCubit.state.place,
        );
        break;

      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(
          value: locator<LocationCubit>(),
        ),
        BlocProvider.value(
          value: locator<HomeCubit>(),
        ),
        BlocProvider.value(
          value: locator<PlaceConfirmCubit>(),
        )
      ],
      child: MultiBlocListener(
        listeners: [
          BlocListener<AuthBloc, AuthState>(
            listener: (context, state) {
              homeCubit.onStarted(
                authenticated: state.isAuthenticated,
                currentLocationPlace: locationCubit.state.place,
              );
              locator<DestinationSuggestionsCubit>().onStarted();
            },
          ),
          BlocListener<LocationCubit, LocationState>(
            listener: (context, state) {
              state.mapOrNull(
                determined: (determined) {
                  homeCubit.state.maybeMap(
                    rideInProgress: (_) {},
                    rateDriver: (_) {},
                    ridePreview: (_) {},
                    inputWaypoints: (_) {},
                    confirmLocation: (_) {},
                    orElse: () {
                      homeCubit.initializeWelcome(
                        pickupPoint: determined.place,
                      );
                    },
                  );
                },
                error: (errorState) {
                  if ((errorState.error == LocationError.permissionDenied ||
                      errorState.error == LocationError.serviceDisabled) &&
                      !_isPermissionDialogOpen &&
                      !_userSkippedPermission) {
                    _isPermissionDialogOpen = true;
                    showDialog<bool>(
                      context: context,
                      useSafeArea: false,
                      barrierDismissible: false,
                      barrierColor: Colors.black87,
                      builder: (context) =>
                          const LocationPermissionRequestDialog(),
                    ).then((granted) {
                      _isPermissionDialogOpen = false;
                      if (granted != true) {
                        _userSkippedPermission = true;
                      }
                    });
                  }
                },
              );
            },
          ),
        ],
        child: context.responsive(
          const HomeScreenMobile(),
          xl: const HomeScreenDesktop(),
        ),
      ),
    );
  }
}
