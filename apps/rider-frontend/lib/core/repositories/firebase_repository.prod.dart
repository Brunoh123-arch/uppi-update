import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/repositories/firebase_repository.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter/foundation.dart';

@prod
@LazySingleton(as: FirebaseRepository)
class FirebaseRepositoryProd implements FirebaseRepository {
  final FirebaseDatasource firebaseDatasource;

  FirebaseRepositoryProd(this.firebaseDatasource);

  @override
  Future<void> retrieveAndUpdateFcmToken() async {
    try {
      if (kIsWeb) {
        return; // FCM on web requires vapidKey and service worker, skip for now.
      }

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Criar canais de notificação Android
      await _setupNotificationChannels();

      final token = await messaging.getToken();
      if (token != null && firebaseDatasource.uid != null) {
        // Registrar FCM token via Edge Function (seguro, servidor valida autoria)
        await firebaseDatasource.supabaseClient.functions.invoke(
          'update-fcm-token',
          body: {'token': token},
        );
      }

      // Escutar atualizações futuras do token
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        if (firebaseDatasource.uid != null) {
          try {
            await firebaseDatasource.supabaseClient.functions.invoke(
              'update-fcm-token',
              body: {'token': newToken},
            );
          } catch (e, st) {
            Sentry.captureException(e, stackTrace: st);
          }
        }
      });
    } catch (e, st) {
      debugPrint('Error retrieving FCM token: $e');
      Sentry.captureException(e, stackTrace: st);
    }
  }

  Future<void> _setupNotificationChannels() async {
    final plugin = FlutterLocalNotificationsPlugin();
    final androidPlugin = AndroidFlutterLocalNotificationsPlugin();

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'high_importance_channel',
        'Corridas e Alertas',
        description:
            'Notificações de novas corridas, status e alertas críticos',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'wallet',
        'Carteira Digital',
        description:
            'Confirmações de pagamento PIX e movimentações na carteira',
        importance: Importance.high,
        playSound: true,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'safety',
        'Segurança',
        description: 'Alertas de desvio de rota e notificações de segurança',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'admin',
        'Suporte Uppi',
        description: 'Mensagens e alertas da equipe de suporte Uppi',
        importance: Importance.high,
        playSound: true,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'announcements',
        'Anúncios e Promoções',
        description: 'Novidades, promoções e comunicados da Uppi',
        importance: Importance.defaultImportance,
        playSound: false,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'orders',
        'Corridas',
        description: 'Novas solicitações e status de corrida',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'tripEvents',
        'Eventos de Viagem',
        description: 'Atualizações em tempo real durante a viagem',
        importance: Importance.high,
        playSound: true,
      ),
    );

    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
  }
}
