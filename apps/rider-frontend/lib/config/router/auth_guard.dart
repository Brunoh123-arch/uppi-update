import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/config/router/app_router.dart';
import 'package:rider_flutter/core/blocs/auth_bloc.dart';
import 'package:rider_flutter/core/entities/profile.dart';

class AuthGuard extends AutoRouteGuard {
  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final authBloc = locator<AuthBloc>();
    final authState = authBloc.state;
    final isGuest = authState.map(
      authenticated: (_) => false,
      unauthenticated: (unauth) => unauth.isGuest,
    );



    final isAllowed = authState.isAuthenticated || isGuest;
    if (isAllowed) {
      // User is logged in or is guest, allow navigation
      resolver.next(true);
    } else {
      // User is not logged in, redirect to the Auth screen
      resolver.redirect(const AuthRoute());
    }
  }
}
