import 'package:auto_route/auto_route.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/config/router/app_router.dart';
import 'package:rider_flutter/core/blocs/app_mode_cubit.dart';

/// Garante que o usuario escolheu AppMode.driver antes de entrar em /driver/*
/// Se nao escolheu, redireciona para a tela de selecao de papel
class DriverModeGuard extends AutoRouteGuard {
  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final mode = locator<AppModeCubit>().state;
    if (mode == AppMode.driver) {
      resolver.next(true);
    } else {
      resolver.redirect(const RoleSelectionRoute());
    }
  }
}
