import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/blocs/auth_bloc.dart';
import 'package:uppi_motorista/core/entities/profile.dart';
import 'package:uppi_motorista/core/router/app_router.dart';

class LoginGuard extends AutoRouteGuard {
  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    if (kDebugMode) {
      final authBloc = locator<AuthBloc>();
      if (!authBloc.state.isAuthenticated) {
        authBloc.onLoggedIn(
          jwtToken: 'dev-bypass-driver-id',
          profile: ProfileEntity.emptyProfile.copyWith(
            firstName: 'Desenvolvedor',
            lastName: 'Motorista',
            number: '5599999999999',
            email: 'dev-driver@uppi.app',
          ),
        );
      }
      resolver.next(true);
      return;
    }

    final loggedIn = locator<AuthBloc>().state.isAuthenticated;
    if (loggedIn) {
      // if user is authenticated we continue
      resolver.next(true);
    } else {
      // we redirect the user to our login page
      // tip: use resolver.redirect to have the redirected route
      // automatically removed from the stack when the resolver is completed
      resolver.redirect(const DriverAuthRoute());
    }
  }
}
