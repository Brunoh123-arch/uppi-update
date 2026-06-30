/// Uppi â€” Helper para invocar Supabase Edge Functions
///
/// Este helper centraliza todas as chamadas Ã s Edge Functions do Supabase,
/// substituindo os antigos `FirebaseFunctions.instance.httpsCallable(...)`.
///
/// Uso:
/// ```dart
/// import 'package:flutter_common/core/services/edge_functions.dart';
///
/// // Chamar uma Edge Function
/// final result = await UppiEdgeFunctions.invoke('send-tip', body: {
///   'orderId': 'abc123',
///   'amount': 5.00,
/// });
/// ```
library;

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Client centralizado para chamadas Supabase Edge Functions
class UppiEdgeFunctions {
  UppiEdgeFunctions._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Invoca uma Edge Function e retorna os dados deserializados.
  ///
  /// [functionName] — Nome da Edge Function (ex: 'send-tip', 'finish-order')
  /// [body] — Payload JSON para enviar na requisição
  ///
  /// Retorna `Map<String, dynamic>` com os dados da resposta.
  /// Lança [EdgeFunctionException] em caso de erro.
  static Future<Map<String, dynamic>> invoke(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final response = await _client.functions.invoke(
        functionName,
        body: body ?? {},
      ).timeout(const Duration(seconds: 15));

      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        if (data.containsKey('error')) {
          throw EdgeFunctionException(
            functionName: functionName,
            message: data['error']?.toString() ?? 'Erro desconhecido',
            statusCode: response.status,
          );
        }
        return data;
      }

      return {'data': response.data};
    } on FunctionException catch (e) {
      throw EdgeFunctionException(
        functionName: functionName,
        message: e.details?.toString() ?? e.toString(),
        statusCode: e.status,
      );
    } on TimeoutException catch (_) {
      throw EdgeFunctionException(
        functionName: functionName,
        message: 'Tempo limite de conexão esgotado. Verifique sua internet.',
        statusCode: 408,
      );
    } catch (e) {
      throw EdgeFunctionException(
        functionName: functionName,
        message: 'Falha na conexão de rede. Verifique se está conectado à internet.',
        statusCode: 0,
      );
    }
  }

  /// Invoca e retorna apenas o campo 'data' da resposta (útil para listas)
  static Future<dynamic> invokeRaw(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final response = await _client.functions.invoke(
        functionName,
        body: body ?? {},
      ).timeout(const Duration(seconds: 15));
      return response.data;
    } on FunctionException catch (e) {
      throw EdgeFunctionException(
        functionName: functionName,
        message: e.details?.toString() ?? e.toString(),
        statusCode: e.status,
      );
    } on TimeoutException catch (_) {
      throw EdgeFunctionException(
        functionName: functionName,
        message: 'Tempo limite de conexão esgotado. Verifique sua internet.',
        statusCode: 408,
      );
    } catch (e) {
      throw EdgeFunctionException(
        functionName: functionName,
        message: 'Falha na conexão de rede. Verifique se está conectado à internet.',
        statusCode: 0,
      );
    }
  }

  // ===== MÃ©todos convenientes para as Edge Functions mais usadas =====

  /// Criar novo pedido de corrida
  static Future<Map<String, dynamic>> createOrder({
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String dropoffAddress,
    required double dropoffLat,
    required double dropoffLng,
    required double fare,
    String paymentMethod = 'cash',
    String? couponCode,
  }) =>
      invoke('create-order', body: {
        'pickup_address': pickupAddress,
        'pickup_lat': pickupLat,
        'pickup_lng': pickupLng,
        'dropoff_address': dropoffAddress,
        'dropoff_lat': dropoffLat,
        'dropoff_lng': dropoffLng,
        'fare': fare,
        'payment_method': paymentMethod,
        if (couponCode != null) 'coupon_code': couponCode,
      });

  /// Aceitar corrida (motorista)
  static Future<Map<String, dynamic>> acceptOrder({
    required String rideId,
  }) =>
      invoke('accept-order', body: {'ride_id': rideId});

  /// Motorista chegou no ponto de embarque
  static Future<Map<String, dynamic>> arrivedAtPickup({
    required String rideId,
  }) =>
      invoke('arrived-at-pickup', body: {'ride_id': rideId});

  /// Iniciar corrida
  static Future<Map<String, dynamic>> startOrder({
    required String rideId,
  }) =>
      invoke('start-order', body: {'ride_id': rideId});

  /// Finalizar corrida
  static Future<Map<String, dynamic>> finishOrder({
    required String rideId,
    double? finalFare,
    double? distance,
    double? duration,
  }) =>
      invoke('finish-order', body: {
        'ride_id': rideId,
        if (finalFare != null) 'final_fare': finalFare,
        if (distance != null) 'distance': distance,
        if (duration != null) 'duration': duration,
      });

  /// Cancelar corrida
  static Future<Map<String, dynamic>> cancelOrder({
    required String rideId,
    String? reason,
  }) =>
      invoke('cancel-order', body: {
        'ride_id': rideId,
        if (reason != null) 'reason': reason,
      });

  /// Enviar gorjeta
  static Future<Map<String, dynamic>> sendTip({
    required String orderId,
    required double amount,
  }) =>
      invoke('send-tip', body: {
        'orderId': orderId,
        'amount': amount,
      });

  /// Atualizar localizaÃ§Ã£o do motorista
  static Future<Map<String, dynamic>> updateDriverLocation({
    required double lat,
    required double lng,
    double heading = 0,
  }) =>
      invoke('update-driver-location', body: {
        'lat': lat,
        'lng': lng,
        'heading': heading,
      });

  /// Atualizar status do motorista (online/offline)
  static Future<Map<String, dynamic>> updateDriverStatus({
    required String status,
  }) =>
      invoke('update-driver-status', body: {'status': status});

  /// Enviar mensagem no chat da corrida
  static Future<Map<String, dynamic>> sendChatMessage({
    required String rideId,
    required String content,
  }) =>
      invoke('chat-send-message', body: {
        'ride_id': rideId,
        'content': content,
      });

  /// Enviar avaliaÃ§Ã£o
  static Future<Map<String, dynamic>> submitFeedback({
    required String rideId,
    required int rating,
    String? review,
    List<String>? parameters,
  }) =>
      invoke('submit-feedback', body: {
        'ride_id': rideId,
        'rating': rating,
        if (review != null) 'review': review,
        if (parameters != null) 'parameters': parameters,
      });

  /// Calcular tarifa
  static Future<Map<String, dynamic>> calculateFare({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
  }) =>
      invoke('calculate-fare', body: {
        'pickup_lat': pickupLat,
        'pickup_lng': pickupLng,
        'dropoff_lat': dropoffLat,
        'dropoff_lng': dropoffLng,
      });

  /// Validar cupom
  static Future<Map<String, dynamic>> validateCoupon({
    required String code,
    required double orderAmount,
  }) =>
      invoke('validate-coupon', body: {
        'code': code,
        'order_amount': orderAmount,
      });

  /// Buscar histÃ³rico de corridas
  static Future<Map<String, dynamic>> getOrderHistory({
    int page = 0,
    int limit = 20,
    String? status,
  }) =>
      invoke('get-order-history', body: {
        'page': page,
        'limit': limit,
        if (status != null) 'status': status,
      });

  /// Buscar saldo da carteira
  static Future<Map<String, dynamic>> getWalletBalance() =>
      invoke('get-wallet-balance');

  /// Buscar extrato da carteira
  static Future<Map<String, dynamic>> getWalletHistory({
    int page = 0,
    int limit = 20,
  }) =>
      invoke('get-wallet-history', body: {
        'page': page,
        'limit': limit,
      });

  /// Buscar respostas rÃ¡pidas do chat
  static Future<Map<String, dynamic>> getQuickReplies({
    String role = 'rider',
  }) =>
      invoke('get-quick-replies', body: {'role': role});

  /// Enviar alerta SOS
  static Future<Map<String, dynamic>> sendSos({
    required String rideId,
    double? lat,
    double? lng,
    String? message,
  }) =>
      invoke('send-sos', body: {
        'ride_id': rideId,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (message != null) 'message': message,
      });

  /// Criar pagamento PIX
  static Future<Map<String, dynamic>> createPixPayment({
    required double amount,
    required String description,
  }) =>
      invoke('create-pix-payment', body: {
        'amount': amount,
        'description': description,
      });

  /// Leaderboard dos motoristas
  static Future<Map<String, dynamic>> getLeaderboard({
    String period = 'weekly',
    int limit = 10,
  }) =>
      invoke('get-leaderboard', body: {
        'period': period,
        'limit': limit,
      });

  /// Verificar badges/conquistas
  static Future<Map<String, dynamic>> checkBadge() =>
      invoke('check-badge');

  /// Calcular surge pricing
  static Future<Map<String, dynamic>> calculateSurge({
    required double lat,
    required double lng,
  }) =>
      invoke('calculate-surge', body: {
        'lat': lat,
        'lng': lng,
      });
}

/// ExceÃ§Ã£o customizada para erros em Edge Functions
class EdgeFunctionException implements Exception {
  final String functionName;
  final String message;
  final int? statusCode;

  EdgeFunctionException({
    required this.functionName,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() =>
      'EdgeFunctionException($functionName): $message [status: $statusCode]';
}

