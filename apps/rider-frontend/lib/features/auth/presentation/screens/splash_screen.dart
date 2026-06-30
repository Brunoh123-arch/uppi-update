import 'dart:async';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rider_flutter/config/router/app_router.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/blocs/app_mode_cubit.dart';
import 'package:rider_flutter/core/blocs/auth_bloc.dart' as rider_auth
    show AuthBloc, AuthStateX;
import 'package:rider_flutter/features/auth/presentation/blocs/onboarding_cubit.dart';
import 'package:flutter_common/features/lgpd/data/lgpd_preferences.dart';
import 'package:uppi_motorista/config/locator/locator.dart' as driver_locator;
import 'package:uppi_motorista/core/blocs/auth_bloc.dart' as driver_auth
    show AuthBloc;

@RoutePage()
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initiateNavigation();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _initiateNavigation() async {
    debugPrint("UPPI BRASIL [SplashScreen] _initiateNavigation iniciada");
    final minTime = Future.delayed(const Duration(milliseconds: 1500));
    final appMode = context.read<AppModeCubit>().state;
    debugPrint("UPPI BRASIL [SplashScreen] Modo atual do App: $appMode");

    if (appMode == AppMode.rider) {
      final authBloc = locator<rider_auth.AuthBloc>();
      debugPrint(
          "UPPI BRASIL [SplashScreen] Aguardando sessionRestored para Rider...");
      try {
        await authBloc.sessionRestored.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            debugPrint(
                "UPPI BRASIL [SplashScreen] Timeout ao restaurar sessão Rider");
            return false;
          },
        );
      } catch (e) {
        debugPrint(
            "UPPI BRASIL [SplashScreen] Erro ao restaurar sessão Rider: $e");
      }
    } else if (appMode == AppMode.driver) {
      final authBloc = driver_locator.locator<driver_auth.AuthBloc>();
      debugPrint(
          "UPPI BRASIL [SplashScreen] Aguardando sessionRestored para Driver...");
      try {
        await authBloc.sessionRestored.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            debugPrint(
                "UPPI BRASIL [SplashScreen] Timeout ao restaurar sessão Driver");
            return false;
          },
        );
      } catch (e) {
        debugPrint(
            "UPPI BRASIL [SplashScreen] Erro ao restaurar sessão Driver: $e");
      }
    }

    await minTime;
    if (!mounted) {
      debugPrint(
          "UPPI BRASIL [SplashScreen] Widget desmontado antes de navegar");
      return;
    }
    debugPrint("UPPI BRASIL [SplashScreen] Navegando após splash");
    _navigateAfterSplash();
  }

  void _navigateAfterSplash() {
    _continueNavigation();
  }

  void _continueNavigation() {
    if (!mounted) return;

    final hasConsent = LgpdPreferences.hasGivenConsent;
    debugPrint(
        "UPPI BRASIL [SplashScreen] LgpdPreferences.hasGivenConsent: $hasConsent");

    if (!hasConsent) {
      debugPrint(
          "UPPI BRASIL [SplashScreen] Direcionando para LgpdConsentWrapperRoute");
      context.router.replace(const LgpdConsentWrapperRoute()).then((_) {
        debugPrint(
            "UPPI BRASIL [SplashScreen] Navegação para LgpdConsentWrapperRoute finalizada");
      }).catchError((e) {
        debugPrint(
            "UPPI BRASIL [SplashScreen] Erro ao ir para LgpdConsentWrapperRoute: $e");
      });
      return;
    }

    final appMode = context.read<AppModeCubit>().state;
    debugPrint(
        "UPPI BRASIL [SplashScreen] Executando navegação baseada no AppMode: $appMode");
    if (appMode == AppMode.rider) {
      final authBloc = locator<rider_auth.AuthBloc>();
      final isDone = locator<OnboardingCubit>().isDone;
      final authState = authBloc.state;
      final isGuest = authState.map(
        authenticated: (_) => false,
        unauthenticated: (unauth) => unauth.isGuest,
      );
      final isAllowed = authState.isAuthenticated || isGuest;
      debugPrint(
          "UPPI BRASIL [SplashScreen] Rider: isDone=$isDone, isAuthenticated=${authState.isAuthenticated}, isGuest=$isGuest");
      if (isDone) {
        if (isAllowed) {
          debugPrint(
              "UPPI BRASIL [SplashScreen] Direcionando Rider para NavigationRoute");
          context.router.replace(const NavigationRoute());
        } else {
          debugPrint(
              "UPPI BRASIL [SplashScreen] Direcionando Rider para AuthRoute (sem autenticação)");
          context.router.replace(const AuthRoute());
        }
      } else {
        debugPrint(
            "UPPI BRASIL [SplashScreen] Direcionando Rider para AuthRoute (onboarding não concluído)");
        context.router.replace(const AuthRoute());
      }
    } else if (appMode == AppMode.driver) {
      final authBloc = driver_locator.locator<driver_auth.AuthBloc>();
      final isDriverAuth = authBloc.state.isAuthenticated;
      debugPrint(
          "UPPI BRASIL [SplashScreen] Driver: isAuthenticated=$isDriverAuth");
      if (isDriverAuth) {
        debugPrint(
            "UPPI BRASIL [SplashScreen] Direcionando Driver para DriverNavigationRoute");
        context.router.replace(const DriverNavigationRoute());
      } else {
        debugPrint(
            "UPPI BRASIL [SplashScreen] Direcionando Driver para DriverAuthRoute");
        context.router.replace(const DriverAuthRoute());
      }
    } else {
      debugPrint(
          "UPPI BRASIL [SplashScreen] Direcionando para RoleSelectionRoute");
      context.router.replace(const RoleSelectionRoute()).then((_) {
        debugPrint(
            "UPPI BRASIL [SplashScreen] Navegação para RoleSelectionRoute finalizada");
      }).catchError((e) {
        debugPrint(
            "UPPI BRASIL [SplashScreen] Erro ao ir para RoleSelectionRoute: $e");
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C20),
      body: Center(
        child: Image.asset(
          'assets/images/logo.png',
          width: 120,
          height: 120,
        ),
      ),
    );
  }
}
