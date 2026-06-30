// ignore_for_file: use_build_context_synchronously

import 'package:uppi_motorista/core/presentation/app_drawer.dart';
import 'package:uppi_motorista/features/home/presentation/blocs/home.dart';
import 'package:uppi_motorista/features/home/presentation/components/driver_search_radius_button_new.dart';
import 'package:uppi_motorista/features/home/presentation/components/home_my_location_button.dart';
import 'package:uppi_motorista/features/home/presentation/components/map_view.dart';
import 'package:uppi_motorista/features/home/presentation/components/navigate_button.dart';
import 'package:uppi_motorista/features/home/presentation/components/top_nav_bar.dart';
import 'package:uppi_motorista/features/home/presentation/screens/mobile_layout_delegate.dart';
import 'package:uppi_motorista/features/home/presentation/screens/sheets/active_order_sheet.dart';
import 'package:uppi_motorista/features/home/presentation/screens/sheets/chat_sheet.dart';
import 'package:uppi_motorista/features/home/presentation/screens/sheets/online_offline_sheet.dart';
import 'package:uppi_motorista/features/home/presentation/screens/sheets/order_summary.dart';
import 'package:uppi_motorista/features/home/presentation/screens/sheets/rate_rider_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/theme/animation_duration.dart';
import 'package:generic_map/generic_map.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:uppi_motorista/features/auth/presentation/widgets/waiting_approval_screen.dart';

import 'sheets/order_requests_pageview.dart';

class HomeScreenMobile extends StatefulWidget {
  const HomeScreenMobile({super.key});

  @override
  State<HomeScreenMobile> createState() => _HomeScreenMobileState();
}

class _HomeScreenMobileState extends State<HomeScreenMobile> {
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
  MapViewController? controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      drawer: const AppDrawer(),
      extendBody: true,
      body: BlocListener<HomeBloc, HomeState>(
        listenWhen: (previous, current) {
          final errorChanged = previous.error != current.error && current.error != null;
          final statusChangedToApproved = previous.driverStatus == const HomeStateDriverStatus.accessDenied() && 
                                          current.driverStatus == const HomeStateDriverStatus.offline();
          final statusChangedToBlocked = previous.driverStatus != const HomeStateDriverStatus.accessDenied() && 
                                         current.driverStatus == const HomeStateDriverStatus.accessDenied();
          final statusToggled = (previous.driverStatus is OnlineDriverStatus && current.driverStatus is OfflineDriverStatus) ||
                                (previous.driverStatus is OfflineDriverStatus && current.driverStatus is OnlineDriverStatus);
          return errorChanged || statusChangedToApproved || statusChangedToBlocked || statusToggled;
        },
        listener: (context, state) {
          if (state.error != null) {
            context.showSnackBar(
              message: state.error!.errorMessage,
            );
          } else if (state.driverStatus == const HomeStateDriverStatus.accessDenied()) {
             context.showSnackBar(
              message: 'Sua conta está em análise ou bloqueada.',
            );
          } else if (state.driverStatus is OnlineDriverStatus) {
            context.showSnackBar(
              message: 'Você está ONLINE!',
            );
          } else if (state.driverStatus is OfflineDriverStatus) {
            context.showSnackBar(
              message: 'Você está OFFLINE!',
            );
          }
        },
        child: BlocBuilder<HomeBloc, HomeState>(
          buildWhen: (previous, current) {
            if (previous.driverStatus.runtimeType != current.driverStatus.runtimeType) {
              return true;
            }
            final currentMapFull = current.driverStatus.maybeMap(
              orElse: () => false,
              online: (value) => value.orderRequests.isNotEmpty,
            );
            final previousMapFull = previous.driverStatus.maybeMap(
              orElse: () => false,
              online: (value) => value.orderRequests.isNotEmpty,
            );
            return currentMapFull != previousMapFull;
          },
        builder: (context, state) {
          if (state.driverStatus == const HomeStateDriverStatus.accessDenied()) {
            return const WaitingApprovalScreen();
          }
          return CustomMultiChildLayout(
            delegate: MobileLayoutDelegate(
              isMapFull: state.driverStatus.maybeMap(
                orElse: () => false,
                online: (value) => value.orderRequests.isNotEmpty,
              ),
            ),
            children: [
              LayoutId(
                id: MobileLayoutDelegate.mapLayoutId,
                child: const HomeMapView(),
              ),
              LayoutId(
                id: MobileLayoutDelegate.navbarId,
                child: BlocBuilder<HomeBloc, HomeState>(
                  buildWhen: (previous, current) =>
                      previous.driverStatus != current.driverStatus,
                  builder: (context, state) {
                    return state.driverStatus.maybeMap(
                      onTrip: (_) => const SizedBox.shrink(),
                      orElse: () => TopNavBar(
                        onMenuButtonPressed: () =>
                            scaffoldKey.currentState?.openDrawer(),
                      ),
                    );
                  },
                ),
              ),
              LayoutId(
                id: MobileLayoutDelegate.cardLayoutId,
                child: BlocBuilder<HomeBloc, HomeState>(
                  builder: (context, state) {
                    return AnimatedSwitcher(
                      duration: AnimationDuration.pageStateTransitionMobile,
                      child: state.driverStatus.map(
                        accessDenied: (value) => const Text('Acesso negado'),
                        initial: (_) => OnlineOfflineSheet(state: state),
                        loading: (_) => OnlineOfflineSheet(state: state),
                        online: (online) {
                          if (online.orderRequests.isEmpty) {
                            return OnlineOfflineSheet(state: state);
                          } else {
                            return OrderRequestsPageView(
                              requests: online.orderRequests,
                              driverLocation: state.driverLocation,
                            );
                          }
                        },
                        offline: (offline) => OnlineOfflineSheet(state: state),
                        onTrip: (onTrip) => onTrip.page.map(
                          overview: (overview) =>
                              ActiveOrderSheet(state: onTrip),
                          chat: (chat) => ChatSheet(order: onTrip.order),
                          payment: (payment) =>
                              OrderSummary(order: onTrip.order),
                          rate: (rate) => RateRiderSheet(order: onTrip.order),
                        ),
                      ),
                    );
                  },
                ),
              ),
              LayoutId(
                id: MobileLayoutDelegate.navigateButtonId,
                child: const NavigateButton(),
              ),
              LayoutId(
                id: MobileLayoutDelegate.searchRadiusButtonId,
                child: const DriverSearchRadiusButtonNew(),
              ),
              LayoutId(
                id: MobileLayoutDelegate.myLocationButtonId,
                child: const HomeMyLocationButton(),
              ),
            ],
          );
        },
      ),
      ),
    );
  }
}
