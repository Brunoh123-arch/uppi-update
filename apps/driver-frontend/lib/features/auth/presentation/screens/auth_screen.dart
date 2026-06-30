import 'package:auto_route/auto_route.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/blocs/auth_bloc.dart';
import 'package:uppi_motorista/core/blocs/onboarding_cubit.dart';
import 'package:uppi_motorista/core/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:uppi_motorista/core/utils/security_guard.dart';

import '../blocs/login.dart';
import 'auth_screen.desktop.dart';
import 'auth_screen.mobile.dart';

@RoutePage(name: 'DriverAuthRoute')
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SecurityGuard.checkIntegrity(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: locator<OnboardingCubit>()),
          BlocProvider.value(value: locator<LoginBloc>()),
        ],
        child: MultiBlocListener(
          listeners: [
            BlocListener<LoginBloc, LoginState>(
              listenWhen: (previous, current) =>
                  previous.errorMessage != current.errorMessage &&
                  current.errorMessage != null,
              listener: (context, state) {
                context.showErrorSnackBar(state.errorMessage);
              },
            ),
            BlocListener<LoginBloc, LoginState>(
              listenWhen: (previous, current) =>
                  previous.loginPage != current.loginPage,
              listener: (context, state) {
                if (state.jwtToken != null && state.profileFullEntity != null) {
                  locator<AuthBloc>().onLoggedIn(
                    jwtToken: state.jwtToken!,
                    profile: state.profileFullEntity!.toEntity,
                  );
                }
                state.loginPage.mapOrNull(
                  success: (value) {
                    final jwtToken = state.jwtToken ?? '';
                    locator<AuthBloc>().onLoggedIn(
                      jwtToken: jwtToken,
                      profile: value.profile,
                    );
                    locator<OnboardingCubit>().skip();
                    // Aguarda 3 segundos para o usuário ver a tela de sucesso
                    // "Aguarde enquanto analisamos seus documentos"
                    Future.delayed(const Duration(seconds: 3), () {
                      if (context.mounted) {
                        locator<LoginBloc>().clear();
                        locator<LoginBloc>().reset();
                        context.router.replaceAll([const DriverNavigationRoute()]);
                      }
                    });
                  },
                );
              },
            ),
          ],
          child: context.responsive(
            const AuthScreenMobile(),
            xl: const AuthScreenDesktop(),
          ),
        ),
      ),
    );
  }
}
