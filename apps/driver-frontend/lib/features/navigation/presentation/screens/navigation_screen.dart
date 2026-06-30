import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/blocs/auth_bloc.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/core/utils/security_guard.dart';

import 'navigation_screen.desktop.dart';
import 'navigation_screen.mobile.dart';

@RoutePage(name: 'DriverNavigationRoute')
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SecurityGuard.checkIntegrity(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: locator<AuthBloc>(),
      child: Scaffold(
        body: context.responsive(
          const NavigationScreenMobile(child: AutoRouter()),
          xl: const NavigationScreenDesktop(child: AutoRouter()),
        ),
      ),
    );
  }
}
