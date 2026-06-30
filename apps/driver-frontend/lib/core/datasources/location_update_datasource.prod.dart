import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:uppi_motorista/core/datasources/location_update_datasource.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:flutter_common/core/entities/driver_location.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// GPS via Supabase Broadcast — zero writes ao banco por update de posição.
/// Estratégia híbrida:
///   - Cada posição é enviada via Broadcast (efêmero, gratuito, <1ms latência)
///   - A cada 30s persiste no banco para motoristas que ficam offline/online
///   - Reconexão automática do canal Broadcast em caso de desconexão
@prod
@LazySingleton(as: LocationUpdateDatasource)
class LocationUpdateDatasourceProd implements LocationUpdateDatasource {
  final SupabaseClient _supabase = Supabase.instance.client;

  RealtimeChannel? _broadcastChannel;
  RealtimeChannel? _globalBroadcastChannel;
  DateTime? _lastDatabaseWrite;
  DateTime? _lastBroadcastWrite;
  bool _isChannelReady = false;
  bool _isGlobalChannelReady = false;
  int _consecutiveErrors = 0;
  String? _cachedVehicleType;
  String? _cachedMarkerUrl;

  /// Intervalo mínimo entre escritas no banco (persistência)
  static const _dbWriteInterval = Duration(seconds: 45);

  /// Intervalo mínimo entre envios de broadcast (tempo real)
  static const _broadcastWriteInterval = Duration(seconds: 1);
  
  /// Máximo de erros seguidos antes de forçar reconexão
  static const _maxConsecutiveErrors = 3;

  /// Garante que o canal Broadcast privado está conectado e pronto
  Future<RealtimeChannel> _ensureChannel() async {
    if (_broadcastChannel != null && _isChannelReady) {
      return _broadcastChannel!;
    }

    // Limpa canal antigo se existir
    if (_broadcastChannel != null) {
      try {
        _supabase.removeChannel(_broadcastChannel!);
      } catch (_) {}
    }

    final uid = _supabase.auth.currentUser?.id ?? 'anon';
    _broadcastChannel = _supabase.channel(
      'track_driver_$uid',
      opts: const RealtimeChannelConfig(
        self: true,
        ack: true, // Espera confirmação do servidor
      ),
    );
    
    final completer = Completer<void>();
    
    _broadcastChannel!.subscribe((status, [error]) {
      _isChannelReady = (status == RealtimeSubscribeStatus.subscribed);
      if (error != null) {
        debugPrint('[LocationDS] Canal erro: $error');
        _isChannelReady = false;
      }
      if (_isChannelReady && !completer.isCompleted) {
        completer.complete();
      }
    });

    // Aguarda até 3s de forma assíncrona, sem loop de espera ativa bloqueante
    try {
      await completer.future.timeout(const Duration(seconds: 3));
    } catch (_) {
      debugPrint('[LocationDS] Timeout ao tentar conectar ao canal de telemetria.');
    }

    return _broadcastChannel!;
  }

  /// Garante que o canal Broadcast global está conectado e pronto
  Future<RealtimeChannel> _ensureGlobalChannel() async {
    if (_globalBroadcastChannel != null && _isGlobalChannelReady) {
      return _globalBroadcastChannel!;
    }

    // Limpa canal antigo se existir
    if (_globalBroadcastChannel != null) {
      try {
        _supabase.removeChannel(_globalBroadcastChannel!);
      } catch (_) {}
    }

    _globalBroadcastChannel = _supabase.channel(
      'driver_locations',
      opts: const RealtimeChannelConfig(
        self: true,
        ack: true,
      ),
    );

    final completer = Completer<void>();

    _globalBroadcastChannel!.subscribe((status, [error]) {
      _isGlobalChannelReady = (status == RealtimeSubscribeStatus.subscribed);
      if (error != null) {
        debugPrint('[LocationDS] Canal global erro: $error');
        _isGlobalChannelReady = false;
      }
      if (_isGlobalChannelReady && !completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await completer.future.timeout(const Duration(seconds: 3));
    } catch (_) {
      debugPrint('[LocationDS] Timeout ao tentar conectar ao canal global de telemetria.');
    }

    return _globalBroadcastChannel!;
  }

  @override
  Future<Either<Failure, bool>> updateDriverLocation({
    required DriverLocation location,
  }) async {
    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) return const Right(false);

      final now = DateTime.now();

      // 1. BROADCAST: envia posição em tempo real sem gravar no banco (com throttle de 3s)
      final shouldSendBroadcast = _lastBroadcastWrite == null ||
          now.difference(_lastBroadcastWrite!) >= _broadcastWriteInterval;

      if (shouldSendBroadcast) {
        _lastBroadcastWrite = now;

        // Inicializa cache se nulo (evita chamadas redundantes)
        if (_cachedVehicleType == null) {
          try {
            final profileRow = await _supabase
                .from('profiles')
                .select('vehicle_type, marker_url')
                .eq('id', uid)
                .maybeSingle();
            _cachedVehicleType = profileRow?['vehicle_type']?.toString() ?? 'carro';
            _cachedMarkerUrl = profileRow?['marker_url']?.toString();
          } catch (_) {
            _cachedVehicleType ??= 'carro';
          }
        }
        final vehicleType = _cachedVehicleType ?? 'carro';
        final markerUrl = _cachedMarkerUrl;

        final payload = {
          'driver_id': uid,
          'lat': location.lat,
          'lng': location.lng,
          'heading': location.rotation,
          'vehicle_type': vehicleType,
          'marker_url': markerUrl,
          'timestamp': now.millisecondsSinceEpoch,
        };

        // Envia para canal privado do passageiro
        try {
          final channel = await _ensureChannel();
          await channel.sendBroadcastMessage(
            event: 'location_update',
            payload: payload,
          );
          _consecutiveErrors = 0; // Reset no sucesso
        } catch (e) {
          _consecutiveErrors++;
          debugPrint('[LocationDS] Broadcast privado falhou (tentativa $_consecutiveErrors): $e');
          
          // Força reconexão após erros consecutivos
          if (_consecutiveErrors >= _maxConsecutiveErrors) {
            _isChannelReady = false;
            _consecutiveErrors = 0;
          }
        }

        // Envia para canal global do admin panel
        try {
          final globalChannel = await _ensureGlobalChannel();
          await globalChannel.sendBroadcastMessage(
            event: 'location_update',
            payload: payload,
          );
        } catch (e) {
          debugPrint('[LocationDS] Broadcast global falhou: $e');
          _isGlobalChannelReady = false;
        }
      }

      // 2. BANCO: persiste apenas a cada 30 segundos (minimiza uso do DB)
      final shouldWriteDb = _lastDatabaseWrite == null ||
          now.difference(_lastDatabaseWrite!) > _dbWriteInterval;

      if (shouldWriteDb) {
        _lastDatabaseWrite = now;
        await _supabase.functions.invoke(
          'update-driver-location',
          body: {
            'lat': location.lat,
            'lng': location.lng,
            'heading': location.rotation,
          },
        );
      }

      return const Right(true);
    } catch (e, st) {
      debugPrint('[LocationDS] Erro geral: $e');
      Sentry.captureException(e, stackTrace: st);
      return Left(Failure(message: e.toString()));
    }
  }

  /// Limpa os canais de broadcast quando o motorista fica offline
  void dispose() {
    if (_broadcastChannel != null) {
      try {
        _supabase.removeChannel(_broadcastChannel!);
      } catch (_) {}
      _broadcastChannel = null;
      _isChannelReady = false;
    }
    if (_globalBroadcastChannel != null) {
      try {
        _supabase.removeChannel(_globalBroadcastChannel!);
      } catch (_) {}
      _globalBroadcastChannel = null;
      _isGlobalChannelReady = false;
    }
  }
}
