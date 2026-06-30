import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:generic_map/interfaces/map_provider_enum.dart';

import 'package:rider_flutter/config/locator/locator.dart';
import 'package:flutter_common/core/blocs/settings.dart';
import 'package:rider_flutter/core/blocs/app_mode_cubit.dart';
import 'package:rider_flutter/firebase_options.dart';
import 'package:rider_flutter/core/utils/map_injector.dart';
import 'package:rider_flutter/features/home/features/track_order/presentation/blocs/track_order.dart';
import 'package:flutter_common/features/lgpd/data/lgpd_preferences.dart';
import 'package:flutter_common/config/constants.dart';
import 'package:flutter_common/core/blocs/connectivity_cubit.dart';
import 'package:flutter_common/core/presentation/uppi_feedback.dart';

import 'package:uppi_motorista/features/home/presentation/blocs/home.dart';
import 'package:uppi_motorista/config/locator/locator.dart' as driver_locator;

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[BG-FCM] Mensagem recebida em background: ${message.data}');
}

class AppInitializer {
  static Future<void> init(FutureOr<void> Function(Widget) appRunner) async {
    debugPrint("UPPI BRASIL [AppInitializer.init] Início do método init");
    SentryWidgetsFlutterBinding.ensureInitialized();
    debugPrint("UPPI BRASIL [AppInitializer.init] SentryWidgetsFlutterBinding.ensureInitialized concluído");
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    const String env = String.fromEnvironment('ENV', defaultValue: 'prod');
    debugPrint("UPPI BRASIL [AppInitializer.init] Ambiente: $env");
    if (env == 'staging') {
      await dotenv.load(fileName: '.env.staging');
    } else {
      await dotenv.load(fileName: '.env');
    }
    debugPrint("UPPI BRASIL [AppInitializer.init] DotEnv carregado");

    HydratedBloc.storage = await HydratedStorage.build(
      storageDirectory: kIsWeb
          ? HydratedStorage.webStorageDirectory
          : await getApplicationDocumentsDirectory(),
    );
    debugPrint("UPPI BRASIL [AppInitializer.init] HydratedBloc.storage configurado");

    // Configuração dos contêineres de Injeção de Dependências
    configureDependencies();
    driver_locator.configureDependencies();
    debugPrint("UPPI BRASIL [AppInitializer.init] Injeção de dependências configurada");

    // Registra SettingsCubit unificado nos locators do Rider e Driver
    if (!locator.isRegistered<SettingsCubit>()) {
      locator.registerSingleton<SettingsCubit>(SettingsCubit());
    }
    if (!driver_locator.locator.isRegistered<SettingsCubit>()) {
      driver_locator.locator.registerSingleton<SettingsCubit>(locator<SettingsCubit>());
    }
    debugPrint("UPPI BRASIL [AppInitializer.init] SettingsCubit unificado registrado nos locators");

    // Registra ConnectivityCubit unificado nos locators do Rider e Driver
    if (!locator.isRegistered<ConnectivityCubit>()) {
      locator.registerSingleton<ConnectivityCubit>(ConnectivityCubit());
    }
    if (!driver_locator.locator.isRegistered<ConnectivityCubit>()) {
      driver_locator.locator.registerSingleton<ConnectivityCubit>(locator<ConnectivityCubit>());
    }

    Constants.onSwitchToPassenger = () {
      try {
        if (locator.isRegistered<AppModeCubit>()) {
          locator<AppModeCubit>().selectRider();
        }
      } catch (_) {}
    };

    // Inicialização assíncrona dos SDKs locais
    debugPrint("UPPI BRASIL [AppInitializer.init] Inicializando Hive...");
    await Hive.initFlutter();
    debugPrint("UPPI BRASIL [AppInitializer.init] Hive.initFlutter() concluído. Iniciando Future.wait...");
    late final SharedPreferences prefs;
    await Future.wait([
      LgpdPreferences.init().then((_) => debugPrint("UPPI BRASIL [AppInitializer.init] LgpdPreferences.init() concluído")),
      Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform).then((_) => debugPrint("UPPI BRASIL [AppInitializer.init] Firebase.initializeApp() concluído")),
      SharedPreferences.getInstance().then((p) {
        prefs = p;
        debugPrint("UPPI BRASIL [AppInitializer.init] SharedPreferences obtido");
      }),
    ]);
    debugPrint("UPPI BRASIL [AppInitializer.init] Future.wait dos SDKs concluído");

    // Configuração do Modo de Economia de Bateria
    try {
      UppiPerformance.batterySaverMode = prefs.getBool('battery_saver_mode') ?? false;
    } catch (_) {}

    // Configuração do Firebase Cloud Messaging (FCM)
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessageHandler);

    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Ouvinte para mensagens FCM recebidas em Foreground (app ativo)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FG-FCM] Mensagem recebida em foreground: ${message.data}');
      final notification = message.notification;
      if (notification != null && notification.title != null) {
        if (locator.isRegistered<AppModeCubit>() &&
            locator<AppModeCubit>().state == AppMode.driver) {
          final type = message.data['type']?.toString();
          final allowedTypes = ['announcement', 'announcements', 'admin', 'admin_notification', 'aviso'];
          final blockedTypes = [
            'new_ride', 'chat_message', 'chat_reopened', 'ride_started',
            'driver_arrived', 'sos_alert', 'tip_received', 'session_kick', 'destination_updated'
          ];

          final isAllowed = allowedTypes.contains(type) || (type == null || type.isEmpty);
          final isBlocked = blockedTypes.contains(type);

          if (isBlocked || !isAllowed) {
            debugPrint('[FG-FCM] Ignorando notificação de foreground no modo Motorista (Tipo: $type)');
            return;
          }
        }

        final type = message.data['type']?.toString();
        final rideId = message.data['ride_id']?.toString();

        if (type == 'chat_message' && rideId != null) {
          bool isRiderInChat = false;
          if (locator.isRegistered<TrackOrderBloc>()) {
            try {
              final trackOrderBloc = locator<TrackOrderBloc>();
              isRiderInChat = trackOrderBloc.state.maybeMap(
                orderInProgres: (inProgress) {
                  final isChatPage = inProgress.page.maybeMap(
                    chat: (_) => true,
                    orElse: () => false,
                  );
                  return isChatPage && inProgress.order.id == rideId;
                },
                orElse: () => false,
              );
            } catch (_) {}
          }

          bool isDriverInChat = false;
          if (driver_locator.locator.isRegistered<HomeBloc>()) {
            try {
              final homeBloc = driver_locator.locator<HomeBloc>();
              isDriverInChat = homeBloc.state.driverStatus.maybeMap(
                onTrip: (onTrip) {
                  final isChatPage = onTrip.page.maybeMap(
                    chat: (_) => true,
                    orElse: () => false,
                  );
                  return isChatPage && onTrip.order.id == rideId;
                },
                orElse: () => false,
              );
            } catch (_) {}
          }

          if (isRiderInChat || isDriverInChat) {
            debugPrint('[FG-FCM] Ignorando notificação de chat redundante em foreground (usuário ativo na aba de chat)');
            return;
          }
        }

        rootScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 32, left: 24, right: 24),
            padding: EdgeInsets.zero,
            content: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(50),
                color: const Color(0xFF096EFF),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.title!,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                        ),
                        if (notification.body != null)
                          Text(
                            notification.body!,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });

    // Inicialização do Supabase
    final supabaseUrl = dotenv.maybeGet('SUPABASE_URL');
    final supabaseAnonKey = dotenv.maybeGet('SUPABASE_ANON_KEY');
    debugPrint("UPPI BRASIL [AppInitializer.init] Supabase URL: $supabaseUrl");
    if (supabaseUrl != null && supabaseAnonKey != null && supabaseUrl.isNotEmpty) {
      debugPrint("UPPI BRASIL [AppInitializer.init] Chamando Supabase.initialize...");
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
      debugPrint("UPPI BRASIL [AppInitializer.init] Supabase.initialize concluído");

      // Carregar configurações do Supabase REST
      debugPrint("UPPI BRASIL [AppInitializer.init] Chamando _loadAppSettings()...");
      await _loadAppSettings();
      debugPrint("UPPI BRASIL [AppInitializer.init] _loadAppSettings() concluído");

      // Escuta mudanças de auth para recarregar configurações
      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (data.event == AuthChangeEvent.signedIn) {
          debugPrint("UPPI BRASIL - Usuário logou, recarregando app_settings.");
          _loadAppSettings();
        }
      });
    } else {
      debugPrint("UPPI BRASIL [AppInitializer.init] Supabase URL ou Anon Key ausente!");
    }

    if (kIsWeb && kDebugMode) {
      debugPrint('UPPI BRASIL - Web mode: Firebase SMS Auth ativado.');
    }

    try {
      if (locator.isRegistered<AppModeCubit>()) {
        locator<AppModeCubit>().selectRider();
        debugPrint("UPPI BRASIL [AppInitializer.init] Forçando modo Rider para testes");
      }
    } catch (_) {}
  }

  static Future<void> _loadAppSettings() async {
    try {
      debugPrint("UPPI BRASIL [_loadAppSettings] Buscando configurações no Supabase com timeout de 5 segundos...");
      final List<dynamic> data = await Supabase.instance.client
          .from('app_settings')
          .select()
          .timeout(const Duration(seconds: 5));
      debugPrint("UPPI BRASIL - Supabase app_settings loaded: $data");
      if (data.isNotEmpty) {
        final Map<String, String> settings = {};
        for (final row in data) {
          final key = row['key']?.toString() ?? '';
          final value = row['value']?.toString() ?? '';
          if (key.isNotEmpty) settings[key] = value;
        }

        String? mapProviderStr;
        String? googleApiKeyStr;

        Map<String, dynamic>? globalConfigRow;
        for (final row in data) {
          if (row is Map && row['key'] == 'global_config') {
            globalConfigRow = Map<String, dynamic>.from(row);
            break;
          }
        }
        if (globalConfigRow != null) {
          mapProviderStr = globalConfigRow['map_provider']?.toString();
          googleApiKeyStr = globalConfigRow['google_map_api_key']?.toString();
        }

        mapProviderStr ??= settings['map_provider'];
        googleApiKeyStr ??= settings['google_map_api_key'];

        if (!kDebugMode && googleApiKeyStr != null && googleApiKeyStr.isNotEmpty) {
          dotenv.env['GOOGLE_MAP_API_KEY'] = googleApiKeyStr;
        }

        final mapboxTokenStr = settings['mapbox_token'] ?? (globalConfigRow != null ? globalConfigRow['mapbox_token']?.toString() : null);
        if (mapboxTokenStr != null && mapboxTokenStr.isNotEmpty) {
          dotenv.env['MAPBOX_TOKEN'] = mapboxTokenStr;
        }

        debugPrint("UPPI BRASIL - Map provider carregado: $mapProviderStr");

        final resolvedApiKey = (googleApiKeyStr != null && googleApiKeyStr.isNotEmpty)
            ? googleApiKeyStr
            : dotenv.maybeGet('GOOGLE_MAP_API_KEY');

        if (resolvedApiKey != null && resolvedApiKey.isNotEmpty && mapProviderStr == 'googleMaps') {
          try {
            await injectGoogleMaps(resolvedApiKey).timeout(const Duration(seconds: 7));
          } catch (e) {
            debugPrint("Erro ou Timeout ao injetar script do Google Maps (migrando para OpenStreetMaps): $e");
            mapProviderStr = 'openStreetMaps';
          }
        }

        if (mapProviderStr != null) {
          MapProviderEnum providerEnum;
          switch (mapProviderStr) {
            case 'googleMaps':
              providerEnum = MapProviderEnum.googleMaps;
              break;
            case 'openStreetMaps':
              providerEnum = MapProviderEnum.openStreetMaps;
              break;
            case 'mapBox':
              providerEnum = MapProviderEnum.mapBox;
              break;
            default:
              providerEnum = MapProviderEnum.googleMaps;
          }

          locator<SettingsCubit>().changeMapProvider(providerEnum);
          debugPrint("UPPI BRASIL - SettingsCubit map provider alterado para: $providerEnum");
        }
      }
    } catch (e) {
      debugPrint("Erro ao carregar app_settings: $e");
      final localApiKey = dotenv.maybeGet('GOOGLE_MAP_API_KEY');
      if (localApiKey != null && localApiKey.isNotEmpty) {
        debugPrint("UPPI BRASIL - Fallback de rede: Forçando Google Maps com chave local do .env");
        locator<SettingsCubit>().changeMapProvider(MapProviderEnum.googleMaps);
      }
    }
  }
}
