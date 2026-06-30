import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ionicons/ionicons.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/blocs/location.dart';
import 'package:rider_flutter/core/presentation/app_drawer.dart';
import 'package:rider_flutter/features/home/presentation/components/home_info_panel.dart';
import 'package:rider_flutter/features/home/presentation/components/home_map.dart';
import 'package:rider_flutter/features/home/presentation/components/my_location_button.dart';
import 'package:rider_flutter/features/home/presentation/screens/mobile_layout_delegate.dart';

import '../blocs/home.dart';

class HomeScreenMobile extends StatefulWidget {
  const HomeScreenMobile({super.key});

  @override
  State<HomeScreenMobile> createState() => _HomeScreenMobileState();
}

class _HomeScreenMobileState extends State<HomeScreenMobile> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  double _debouncedKeyboardHeight = 0;
  Timer? _debounceTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentKeyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    if (currentKeyboardHeight == 0) {
      // Se o teclado está fechando ou fechado, cancela qualquer timer pendente e zera imediatamente
      _debounceTimer?.cancel();
      if (_debouncedKeyboardHeight != 0) {
        setState(() {
          _debouncedKeyboardHeight = 0;
        });
      }
    } else if (currentKeyboardHeight != _debouncedKeyboardHeight) {
      // Se o teclado está abrindo, debouncamos a mudança por 350ms para suavizar a transição do botão
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 350), () {
        if (mounted) {
          setState(() {
            _debouncedKeyboardHeight = currentKeyboardHeight;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppDrawer(),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          const Positioned.fill(
            child: RepaintBoundary(
              child: HomeMap(),
            ),
          ),
          BlocBuilder<HomeCubit, HomeState>(
            builder: (context, homeState) {
              final isInputWaypoints = homeState.maybeMap(
                inputWaypoints: (_) => true,
                orElse: () => false,
              );

              return TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0,
                  end: isInputWaypoints ? _debouncedKeyboardHeight : 0.0,
                ),
                duration: const Duration(milliseconds: 250),
                curve: Curves.fastOutSlowIn,
                builder: (context, animKeyboardHeight, child) {
                  return CustomMultiChildLayout(
                    delegate: MobileLayoutDelegate(
                      screenHeight: View.of(context).physicalSize.height / View.of(context).devicePixelRatio,
                      keyboardHeight: isInputWaypoints ? animKeyboardHeight : 0.0,
                    ),
                    children: [
                      LayoutId(
                        id: MobileLayoutDelegate.actionButtonId,
                        child: SafeArea(
                          child: BlocBuilder<HomeCubit, HomeState>(
                            builder: (context, state) {
                              return state.maybeMap(
                                orElse: () => const SizedBox.shrink(),
                                welcome: (_) => menuButton,
                                ridePreview: (_) => backButton,
                                confirmLocation: (_) => backButton,
                              );
                            },
                          ),
                        ),
                      ),
                      LayoutId(
                        id: MobileLayoutDelegate.cardLayoutId,
                        child: const RepaintBoundary(
                          child: HomeInfoPanel(),
                        ),
                      ),
                      LayoutId(
                        id: MobileLayoutDelegate.myLocationButtonId,
                        child: const AppMyLocationButton(),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget get menuButton => FloatingActionButton.small(
        onPressed: () {
          _scaffoldKey.currentState?.openDrawer();
        },
        child: const Icon(Ionicons.menu),
      );

  Widget get backButton => FloatingActionButton.small(
        onPressed: () {
          locator<HomeCubit>().state.maybeMap(
                orElse: () => throw Exception(
                    'This action can only be called from ride preview state'),
                ridePreview: (value) {
                  locator<HomeCubit>().initializeWelcome(
                    pickupPoint: locator<LocationCubit>().state.place,
                  );
                },
                confirmLocation: (value) {
                  locator<HomeCubit>().showWaypoints(
                    waypoints: value.waypoints,
                  );
                },
              );
        },
        child: const Icon(Ionicons.arrow_back),
      );
}
