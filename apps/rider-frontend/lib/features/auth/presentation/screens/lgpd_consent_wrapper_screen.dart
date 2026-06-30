import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/features/lgpd/lgpd.dart';
import 'package:rider_flutter/config/router/app_router.dart';

/// Wrapper que conecta a tela compartilhada LGPD ao router do app.
@RoutePage()
class LgpdConsentWrapperScreen extends StatelessWidget {
  const LgpdConsentWrapperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint("UPPI BRASIL [LgpdConsentWrapperScreen] build chamado");
    return LgpdConsentScreen(
      onConsentGiven: () {
        debugPrint("UPPI BRASIL [LgpdConsentWrapperScreen] onConsentGiven chamado");
        // Volta para o splash que agora vai seguir o fluxo normal
        context.router.replace(const SplashRoute());
      },
    );
  }
}
