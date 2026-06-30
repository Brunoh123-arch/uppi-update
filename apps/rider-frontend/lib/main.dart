import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rider_flutter/config/env.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:flutter_common/core/theme/theme.dart';
import 'package:rider_flutter/config/theme/fonts.dart';
import 'package:flutter_common/core/blocs/settings.dart';
import 'package:rider_flutter/core/blocs/app_mode_cubit.dart';
import 'package:rider_flutter/l10n/messages.dart';
import 'package:flutter_common/l10n/messages.dart' as common_messages;
import 'package:rider_flutter/config/router/app_router.dart';
import 'package:rider_flutter/config/router/router_observer.dart';
import 'package:uppi_motorista/l10n/messages.dart' as driver_messages;
import 'package:rider_flutter/core/widgets/force_update_wrapper.dart';
import 'package:flutter_common/core/blocs/connectivity_cubit.dart';
import 'package:flutter_common/core/presentation/connectivity_banner_wrapper.dart';
import 'package:flutter_common/core/presentation/global_offline_overlay.dart';

import 'package:rider_flutter/core/di/app_initializer.dart';

void main() async {
  try {
    debugPrint("UPPI BRASIL [main] Iniciando inicialização do app...");
    await AppInitializer.init(
      (app) => runApp(app),
    );
    debugPrint("UPPI BRASIL [main] Inicialização concluída com sucesso");
  } catch (e, stack) {
    debugPrint("UPPI BRASIL [main] ERRO CRÍTICO na inicialização: $e");
    debugPrint("UPPI BRASIL [main] StackTrace: $stack");
  } finally {
    debugPrint("UPPI BRASIL [main] Chamando runApp(const MyApp())");
    runApp(const MyApp());
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    if (shortestSide < 600) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }

    return MultiBlocProvider(
      providers: [
        BlocProvider<SettingsCubit>.value(value: locator<SettingsCubit>()),
        BlocProvider<AppModeCubit>.value(value: locator<AppModeCubit>()),
        BlocProvider<ConnectivityCubit>.value(value: locator<ConnectivityCubit>()),
      ],
      child: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          return ForceUpdateWrapper(
            appType: 'rider',
            child: MaterialApp.router(
              scaffoldMessengerKey: rootScaffoldMessengerKey,
              debugShowCheckedModeBanner: false,
              title: Env.appName,
              themeMode: ThemeMode.light,
              theme: AppTheme.light(Fonts.primary, Fonts.secondary),
              darkTheme: AppTheme.dark(Fonts.primary, Fonts.secondary),
              locale: state.locale.contains('_')
                  ? Locale(state.locale.split('_')[0], state.locale.split('_')[1])
                  : Locale(state.locale),
              localizationsDelegates: const [
                ...S.localizationsDelegates,
                common_messages.S.delegate,
                driver_messages.S.delegate,
              ],
              supportedLocales: S.supportedLocales,
              routerConfig: locator<AppRouter>().config(
                navigatorObservers: () => [RouterObserver()],
              ),
              builder: (context, child) {
                return GlobalOfflineOverlay(
                  child: ConnectivityBannerWrapper(child: child!),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
