import 'package:auto_route/auto_route.dart';
import 'package:uppi_motorista/core/router/app_router.dart';
import 'package:flutter/widgets.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/blocs/route.dart';

import 'nav_item.dart';

class RouterObserver extends AutoRouterObserver {
  final Map<String, NavItem> routeMap = {
    DriverHomeRoute.name: NavItem.home,
    DriverEarningsRoute.name: NavItem.earnings,
    DriverAnnouncementsRoute.name: NavItem.announcements,
    DriverPayoutAccountsRoute.name: NavItem.profile,
    DriverPayoutAccountListRoute.name: NavItem.profile,
    DriverProfileRoute.name: NavItem.profile,
    DriverWalletRoute.name: NavItem.wallet,
    DriverRideHistoryRoute.name: NavItem.rideHistory,
    DriverRideHistoryDetailsRoute.name: NavItem.rideHistory,
    DriverSettingsRoute.name: NavItem.settings,
  };

  @override
  void didPush(Route route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    final routeName = route.settings.name;
    if (routeName != null &&
        routeMap.keys.where((e) => e.startsWith(routeName)).isNotEmpty) {
      final route = routeMap[routeName];
      locator<RouteCubit>().routeTo(route!);
    }
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    final routeName = previousRoute?.settings.name;
    if (routeName != null &&
        routeMap.keys.where((e) => e.startsWith(routeName)).isNotEmpty) {
      final route = routeMap[routeName];
      locator<RouteCubit>().routeTo(route!);
    }
  }
}
