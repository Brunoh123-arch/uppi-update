import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/config/router/app_router.dart';
import 'package:rider_flutter/core/blocs/auth_bloc.dart';
import 'package:rider_flutter/core/entities/profile.dart';

class AuthGuard extends AutoRouteGuard {
  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    if (kDebugMode) {
      final authBloc = locator<AuthBloc>();
      if (!authBloc.state.isAuthenticated) {
        authBloc.onLoggedIn(
          jwtToken: 'dev-bypass-user-id',
          profile: ProfileEntity.emptyProfile.copyWith(
            firstName: 'Desenvolvedor',
            lastName: 'Passageiro',
            number: '5599999999999',
            email: 'dev@uppi.app',
          ),
        );
      }
      resolver.next(true);
      return;
    }

    final isAuthenticated = locator<AuthBloc>().state.isAuthenticated;
    if (isAuthenticated) {
      // User is logged in, allow navigation
      resolver.next(true);
    } else {
      // User is not logged in, redirect to the Auth screen
      resolver.redirect(const AuthRoute());
    }
  }
}
