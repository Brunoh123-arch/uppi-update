import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_repository.dart';

/// Repositório de inicialização Firebase (notificações apenas).
/// FCM token agora salvo em profiles.fcm_token no Supabase.
/// cloud_firestore removido completamente.
@prod
@LazySingleton(as: FirebaseRepository)
class FirebaseRepositoryProd implements FirebaseRepository {
  @override
  Future<void> retrieveAndUpdateFcmToken() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final messaging = FirebaseMessaging.instance;

      // Tentar solicitar permissão — pode falhar em dispositivos sem GMS (Huawei, etc.)
      try {
        await messaging.requestPermission(alert: true, badge: true, sound: true);
      } catch (permErr) {
        // Dispositivo sem Google Play Services — notificações push FCM indisponíveis.
        // O app continuará funcionando via Supabase Realtime + polling de 3s.
        debugPrint('[FCM] Permissão de notificação falhou (possível dispositivo sem GMS): $permErr');
        await _setupNotificationChannels(); // Ainda configura canais locais
        return;
      }

      await _setupNotificationChannels();

      final token = await messaging.getToken();

      // token == null em dispositivos sem Google Play Services (Huawei, Xiaomi ROM alterada)
      if (token == null) {
        debugPrint('[FCM] ⚠️ Token FCM indisponível — dispositivo possivelmente sem Google Play Services. '
            'Notificações push serão substituídas por Supabase Realtime.');
        return; // Sem crash — o app funciona normalmente via WebSocket
      }

      // Registrar FCM token via Edge Function (seguro - servidor valida autoria)
      await Supabase.instance.client.functions.invoke(
        'update-fcm-token',
        body: {'token': token},
      );

      // Escutar renovações de token
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        try {
          await Supabase.instance.client.functions.invoke(
            'update-fcm-token',
            body: {'token': newToken},
          );
        } catch (e, st) {
          Sentry.captureException(e, stackTrace: st);
        }
      });
    } catch (e, st) {
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
        description: 'Novas solicitações de corrida, status e alertas críticos',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'wallet',
        'Carteira Digital',
        description: 'Confirmações de recarga PIX e movimentações na carteira',
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

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'newRequest',
        'Novas Corridas',
        description: 'Alerta sonoro quando um passageiro solicita uma corrida',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
  }
}
