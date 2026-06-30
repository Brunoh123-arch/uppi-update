import 'package:connectivity_plus/connectivity_plus.dart';


import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rider_flutter/config/locator/locator.config.dart';
import 'package:rider_flutter/core/blocs/app_mode_cubit.dart';

// GetIt.instance — singleton global, compartilhado por rider e driver
// O driver usava GetIt.asNewInstance() — isso foi a raiz dos problemas de DI
final locator = GetIt.instance;

@InjectableInit()
void configureDependencies() {
  locator.init(environment: prod.name);

  // AppModeCubit registrado manualmente pois e HydratedCubit
  // (nao pode ser gerado pelo injectable automaticamente)
  if (!locator.isRegistered<AppModeCubit>()) {
    locator.registerSingleton<AppModeCubit>(AppModeCubit());
  }
}

@module
abstract class ServiceModule {
  @lazySingleton
  Connectivity get connectivity => Connectivity();

  @lazySingleton
  SupabaseClient get supabaseClient => Supabase.instance.client;
}
