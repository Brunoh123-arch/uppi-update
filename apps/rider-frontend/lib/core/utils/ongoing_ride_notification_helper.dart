import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:rider_flutter/core/entities/order.dart';
import 'package:flutter_common/core/enums/order_status.dart';

class OngoingRideNotificationHelper {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const int _notificationId = 8888; // ID único para a notificação de corrida

  static OrderStatus? _lastStatus;
  static String? _lastDriverId;

  static Future<void> updateNotification(OrderEntity order) async {
    final status = order.status;
    final driverId = order.driver?.mobileNumber;

    if (_lastStatus == status && _lastDriverId == driverId) {
      return;
    }
    _lastStatus = status;
    _lastDriverId = driverId;

    // Se a corrida acabou ou foi cancelada, cancela a notificação e encerra
    if (status == OrderStatus.finished ||
        status == OrderStatus.riderCanceled ||
        status == OrderStatus.driverCanceled ||
        status == OrderStatus.waitingForReview ||
        status == OrderStatus.expired) {
      await cancelNotification();
      return;
    }

    String title = "Uppi Mobilidade";
    String body = "Acompanhe sua viagem.";
    int progress = 0;
    bool showProgressBar = false;

    final driverName = order.driver?.fullName ?? "Motorista";
    final carModel = order.driver?.vehicleModel ?? "";
    final carPlate = order.driver?.vehiclePlateNumber ?? "";
    final vehicleInfo = [carModel, carPlate].where((e) => e.isNotEmpty).join(' - ');

    switch (status) {
      case OrderStatus.requested:
        title = "Buscando motorista... 🔍";
        body = "Estamos procurando o melhor motorista para você.";
        showProgressBar = true;
        progress = 0;
        break;
      case OrderStatus.driverAccepted:
        title = "Motorista a caminho! 🚗";
        body = "$driverName está a caminho${vehicleInfo.isNotEmpty ? " ($vehicleInfo)" : ""}";
        showProgressBar = true;
        progress = 25;
        break;
      case OrderStatus.arrived:
        title = "Motorista chegou! 🎉";
        body = "$driverName chegou e está aguardando você no local.";
        showProgressBar = false;
        break;
      case OrderStatus.started:
        title = "Corrida em andamento! 🚀";
        body = "A caminho do seu destino.";
        showProgressBar = true;
        progress = 75;
        break;
      case OrderStatus.waitingForPostPay:
      case OrderStatus.waitingForPrePay:
        title = "Aguardando pagamento 💳";
        body = "Por favor, finalize o pagamento da sua viagem.";
        showProgressBar = false;
        break;
      default:
        break;
    }

    final androidDetails = AndroidNotificationDetails(
      'tripEvents', // Canal existente no app para eventos de viagem
      'Eventos de Viagem',
      channelDescription: 'Atualizações em tempo real durante a viagem',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true, // Mantém a notificação fixa
      onlyAlertOnce: true, // Avisa sonoramente apenas no primeiro disparo
      showProgress: showProgressBar,
      maxProgress: 100,
      progress: progress,
      icon: '@mipmap/ic_launcher',
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _plugin.show(
      _notificationId,
      title,
      body,
      notificationDetails,
    );
  }

  static Future<void> cancelNotification() async {
    _lastStatus = null;
    _lastDriverId = null;
    await _plugin.cancel(_notificationId);
  }
}
