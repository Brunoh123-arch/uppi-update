import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uppi_motorista/config/locator/locator.config.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

// IMPORTANTE: O módulo do motorista usa GetIt.asNewInstance() — uma instância
// separada do container de DI do rider-frontend — para evitar colisão de
// singletons quando os dois módulos são acoplados no Super App.
// Nunca use GetIt.instance aqui; isso causaria conflito com as instâncias do rider.
final locator = GetIt.asNewInstance();

@InjectableInit()
void configureDependencies() {
  // Guard: evita re-registrar dependências em hot reload ou re-init do módulo
  if (!locator.isRegistered<SupabaseClient>()) {
    locator.init(environment: prod.name);
  }
}

@module
abstract class ServiceModule {
  @lazySingleton
  Connectivity get connectivity => Connectivity();

  @lazySingleton
  SupabaseClient get supabaseClient => Supabase.instance.client;
}

