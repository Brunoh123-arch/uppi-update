import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Utilitário premium de resiliência de rede e auto-retry silencioso para o ecossistema Uppi.
/// Intercepta instabilidades e re-tenta operações importantes automaticamente em background.
class UppiNetworkResilience {
  UppiNetworkResilience._();

  static final Connectivity _connectivity = Connectivity();

  /// Escuta em tempo real o status de conexão de internet
  static Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged;

  /// Retorna se o dispositivo possui conexão física de rede no momento
  static Future<bool> isConnected() async {
    final results = await _connectivity.checkConnectivity();
    if (results.isEmpty || results.contains(ConnectivityResult.none)) {
      return false;
    }
    return true;
  }

  /// Executa uma operação assíncrona com auto-retry silencioso em caso de falha de conexão.
  /// Aplica a técnica de Exponencial Backoff de forma transparente em background.
  static Future<T> runWithRetry<T>(
    Future<T> Function() operation, {
    int maxAttempts = 5,
    Duration initialDelay = const Duration(seconds: 1),
    FutureOr<void> Function(int attempt, dynamic error)? onAttemptFailed,
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (true) {
      attempt++;
      try {
        // Se sabemos que está desconectado, aguarda a rede voltar antes de tentar
        if (!await isConnected()) {
          debugPrint('UppiNetworkResilience: Sem internet física. Aguardando sinal...');
          await _waitForConnection();
        }

        return await operation();
      } catch (e) {
        final isNetworkError = e is SocketException ||
            e is HttpException ||
            e is TimeoutException ||
            e.toString().contains('SocketException') ||
            e.toString().contains('Failed host lookup');

        if (!isNetworkError || attempt >= maxAttempts) {
          // Se não for erro de rede ou estourar as tentativas, repassa o erro adiante
          rethrow;
        }

        if (onAttemptFailed != null) {
          await onAttemptFailed(attempt, e);
        }

        debugPrint(
            'UppiNetworkResilience: Tentativa $attempt falhou devido a erro de rede. Re-tentando em ${delay.inSeconds}s... Erro: $e');

        await Future.delayed(delay);
        delay *= 2; // Exponencial Backoff
      }
    }
  }

  /// Helper que bloqueia a execução até que o status de conectividade retorne para ativo
  static Future<void> _waitForConnection() async {
    final completer = Completer<void>();
    StreamSubscription? sub;

    sub = onConnectivityChanged.listen((results) {
      if (results.isNotEmpty && !results.contains(ConnectivityResult.none)) {
        completer.complete();
        sub?.cancel();
      }
    });

    // Timeout de segurança para não travar indefinidamente se a escuta falhar
    await completer.future.timeout(const Duration(minutes: 5), onTimeout: () {
      sub?.cancel();
    });
  }
}
