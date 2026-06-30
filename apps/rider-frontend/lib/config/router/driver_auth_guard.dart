import 'package:auto_route/auto_route.dart';
import 'package:uppi_motorista/config/locator/locator.dart' as driver_locator;
import 'package:uppi_motorista/core/blocs/auth_bloc.dart' as driver_auth;
import 'package:rider_flutter/config/router/app_router.dart';

class DriverAuthGuard extends AutoRouteGuard {
  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final isAuthenticated =
        driver_locator.locator<driver_auth.AuthBloc>().state.isAuthenticated;
    if (isAuthenticated) {
      resolver.next(true);
    } else {
      resolver.redirect(const DriverAuthRoute());
    }
  }
}
