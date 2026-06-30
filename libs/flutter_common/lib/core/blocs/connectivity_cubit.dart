import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

enum ConnectivityStatus { connected, disconnected }

class ConnectivityState {
  final ConnectivityStatus status;
  final List<ConnectivityResult> results;

  const ConnectivityState({required this.status, required this.results});

  factory ConnectivityState.initial() {
    return const ConnectivityState(
      status: ConnectivityStatus.connected,
      results: [],
    );
  }

  ConnectivityState copyWith({
    ConnectivityStatus? status,
    List<ConnectivityResult>? results,
  }) {
    return ConnectivityState(
      status: status ?? this.status,
      results: results ?? this.results,
    );
  }

  bool get isConnected => status == ConnectivityStatus.connected;
  bool get isDisconnected => status == ConnectivityStatus.disconnected;
}

class ConnectivityCubit extends Cubit<ConnectivityState> {
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isChecking = false;

  ConnectivityCubit({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity(),
      super(ConnectivityState.initial()) {
    _init();
  }

  Future<void> _init() async {
    try {
      final results = await _connectivity.checkConnectivity();
      await _updateStatus(results);
    } catch (_) {
      // Graceful fallback: assume connected
      emit(state.copyWith(status: ConnectivityStatus.connected));
    }

    _subscription = _connectivity.onConnectivityChanged.listen(_updateStatus);
  }

  Future<void> _updateStatus(List<ConnectivityResult> results) async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      final hasConnectionInterface = results.any(
        (result) => result != ConnectivityResult.none,
      );
      if (!hasConnectionInterface) {
        emit(
          ConnectivityState(
            status: ConnectivityStatus.disconnected,
            results: results,
          ),
        );
        return;
      }

      // Se há interface ativa, verifica o acesso real à internet (exceto na Web)
      if (!kIsWeb) {
        final hasRealAccess = await _checkActualInternetAccess();
        emit(
          ConnectivityState(
            status: hasRealAccess
                ? ConnectivityStatus.connected
                : ConnectivityStatus.disconnected,
            results: results,
          ),
        );
      } else {
        emit(
          ConnectivityState(
            status: ConnectivityStatus.connected,
            results: results,
          ),
        );
      }
    } finally {
      _isChecking = false;
    }
  }

  Future<bool> _checkActualInternetAccess() async {
    try {
      // Faz lookup em dois servidores DNS altamente confiáveis e de baixa latência no Brasil
      final result = await InternetAddress.lookup(
        'dns.google',
      ).timeout(const Duration(seconds: 2));
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {}

    try {
      final result = await InternetAddress.lookup(
        'one.one.one.one',
      ).timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {}

    return true;
  }

  Future<void> checkConnection() async {
    try {
      final results = await _connectivity.checkConnectivity();
      await _updateStatus(results);
    } catch (_) {
      emit(state.copyWith(status: ConnectivityStatus.connected));
    }
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
