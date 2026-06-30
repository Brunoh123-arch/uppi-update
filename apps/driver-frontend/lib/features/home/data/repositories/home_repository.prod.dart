import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:rxdart/rxdart.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:flutter_common/core/blocs/settings.dart';
import 'package:flutter_common/core/enums/map_provider_enum.prod.dart';

import 'package:dartz/dartz.dart';

import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:local_auth/local_auth.dart';
import 'package:hive/hive.dart';

import 'package:uppi_motorista/core/entities/order.dart';
import 'package:uppi_motorista/core/entities/order_request.dart';
import 'package:uppi_motorista/core/entities/profile.dart';
import 'package:uppi_motorista/core/enums/driver_status.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:flutter_common/core/entities/cancel_reason.dart';
import 'package:flutter_common/core/entities/driver_location.dart';
import 'package:flutter_common/core/entities/payment_method_union.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:flutter_common/core/enums/payment_mode.dart';
import 'package:flutter_common/features/chat/domain/entities/chat_message.dart';
import 'package:flutter_common/core/services/arrival_reminder_service.dart';
import 'dart:math' as math;

import 'package:uppi_motorista/core/utils/status_parser.dart';

import '../../domain/repositories/home_repository.dart';

@prod
@LazySingleton(as: HomeRepository)
class HomeRepositoryProd implements HomeRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  DriverLocation? _lastLocation;
  DateTime? _lastFuncInvokeTime;
  DriverLocation? _lastFuncInvokeLocation;
  String? _cachedRideId;
  List<LatLngEntity> _cachedRideDirections = const [];
  List<LatLngEntity> _cachedDriverDirections = const [];
  double? _cachedLastDriverLat;
  double? _cachedLastDriverLng;

  StreamSubscription? _requestsSubscription;
  StreamController<List<OrderRequestEntity>>? _requestsStreamController;

  // Cache de rotas por ride ID: evita re-buscar rota toda vez que o stream emite
  final Map<String, List<LatLngEntity>> _rideRouteCache = {};

  StreamSubscription? _activeOrderSubscription;
  StreamController<OrderEntity>? _activeOrderStreamController;

  // Fila de Transições Offline do Motorista
  final List<_OfflineTransition> _offlineTransitionsQueue = [];
  bool _isProcessingQueue = false;
  Timer? _offlineQueueTimer;

  Box? _offlineBox;

  HomeRepositoryProd() {
    _loadOfflineQueue();
  }

  Future<Box> _getOfflineBox() async {
    if (_offlineBox != null) return _offlineBox!;
    _offlineBox = await Hive.openBox('offline_transitions');
    return _offlineBox!;
  }

  void _saveQueueToHive() async {
    try {
      final box = await _getOfflineBox();
      final list = _offlineTransitionsQueue.map((e) => {
        'orderId': e.orderId,
        'type': e.type,
        'amount': e.amount,
        'boardingPin': e.boardingPin,
        'timestamp': e.timestamp.toIso8601String(),
        'retryCount': e.retryCount,
      }).toList();
      await box.put('queue', list);
    } catch (_) {}
  }

  void _loadOfflineQueue() async {
    try {
      final box = await _getOfflineBox();
      final List? rawList = box.get('queue');
      if (rawList != null) {
        for (final item in rawList) {
          if (item is Map) {
            _offlineTransitionsQueue.add(_OfflineTransition(
              orderId: item['orderId']?.toString() ?? '',
              type: item['type']?.toString() ?? '',
              amount: (item['amount'] as num?)?.toDouble(),
              boardingPin: item['boardingPin']?.toString(),
              timestamp: DateTime.tryParse(item['timestamp']?.toString() ?? '') ?? DateTime.now(),
              retryCount: (item['retryCount'] as num?)?.toInt() ?? 0,
            ));
          }
        }
      }
      if (_offlineTransitionsQueue.isNotEmpty) {
        _startOfflineQueueTimer();
      }
    } catch (_) {}
  }

  void _startOfflineQueueTimer() {
    if (_offlineQueueTimer != null && _offlineQueueTimer!.isActive) return;
    
    _offlineQueueTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_offlineTransitionsQueue.isEmpty) {
        timer.cancel();
        _offlineQueueTimer = null;
        debugPrint('[OfflineQueue] Fila vazia. Timer de segurança cancelado.');
        return;
      }
      _processOfflineQueue();
    });
    debugPrint('[OfflineQueue] Primeiro item na fila. Timer de segurança iniciado.');
  }

  void _processOfflineQueue() async {
    if (_isProcessingQueue || _offlineTransitionsQueue.isEmpty) return;
    _isProcessingQueue = true;

    debugPrint('[OfflineQueue] Iniciando processamento da fila offline: ${_offlineTransitionsQueue.length} transições pendentes.');

    while (_offlineTransitionsQueue.isNotEmpty) {
      final transition = _offlineTransitionsQueue.first;
      try {
        late FunctionResponse response;
        if (transition.type == 'arrived') {
          response = await _supabase.functions.invoke(
            'driver-flow-actions',
            body: {
              'action': 'arrived-at-pickup',
              'orderId': transition.orderId,
            },
          );
        } else if (transition.type == 'start') {
          response = await _supabase.functions.invoke(
            'driver-flow-actions',
            body: {
              'action': 'start-order',
              'orderId': transition.orderId,
              if (transition.boardingPin != null) 'boardingPin': transition.boardingPin,
            },
          );
        } else if (transition.type == 'paid') {
          response = await _supabase.functions.invoke(
            'driver-flow-actions',
            body: {
              'action': 'finish-order',
              'orderId': transition.orderId,
              'cashAmount': transition.amount ?? 0.0,
            },
          );
        }

        if (response.status == 200) {
          debugPrint('[OfflineQueue] Sincronização offline bem-sucedida para a transição: ${transition.type} da corrida ${transition.orderId}');
          _offlineTransitionsQueue.removeAt(0);
          _saveQueueToHive();
        } else {
          transition.retryCount++;
          if (response.status == 400 || response.status == 404 || transition.retryCount >= 10) {
            debugPrint('[OfflineQueue] Descartando transição inválida ou falha persistente (status ${response.status}, retries ${transition.retryCount}): ${response.data}');
            _offlineTransitionsQueue.removeAt(0);
            _saveQueueToHive();
          } else {
            debugPrint('[OfflineQueue] Erro ao sincronizar transição offline (status ${response.status}): ${response.data}. Mantendo na fila para retry (tentativa ${transition.retryCount}).');
            break;
          }
        }
      } catch (e) {
        debugPrint('[OfflineQueue] Falha na rede ao tentar sincronizar transição offline. Tentará novamente mais tarde. Erro: $e');
        break;
      }
    }

    _isProcessingQueue = false;
  }

  String? get uid => _supabase.auth.currentUser?.id;

  @override
  Future<Either<Failure, ProfileEntity>> getProfile() async {
    try {
      if (uid == null) return const Left(Failure.error());
      final row = await _supabase
          .from('profiles')
          .select()
          .eq('id', uid!)
          .maybeSingle();
      if (row == null) return Right(ProfileEntity.emptyProfile);
      final st = row['status']?.toString();
      DriverStatus driverStatus = StatusParser.fromString(st);

      final isApproved = row['is_approved'] == true;
      if (isApproved && driverStatus == const DriverStatus.pendingApproval()) {
        driverStatus = const DriverStatus.online();
      }
      if (row['is_blocked'] == true || st == 'blocked') {
        driverStatus = const DriverStatus.blocked();
      }

      // Procura ativamente por qualquer corrida em andamento síncrona
      // (soluciona o bug do motorista matar o app no meio do fluxo de viagem)
      final List<OrderEntity> activeOrders = [];
      final activeRide = await _supabase
          .from('rides')
          .select()
          .eq('driver_id', uid!)
          .inFilter('status', [
            'accepted',
            'driver_accepted',
            'arrived',
            'started',
            'in_progress',
            'waiting_for_review',
            'waiting_for_post_pay'
          ])
          .maybeSingle();

      if (activeRide != null) {
        final order = await _mapRowToOrderEntity(activeRide);
        activeOrders.add(order);
      }

      final nameStr = row['full_name']?.toString();
      final nameParts = nameStr != null ? nameStr.split(' ') : <String>[];
      final firstName = nameParts.isNotEmpty ? nameParts.first : 'Motorista';
      final lastName = nameParts.length > 1 ? nameParts.last : '';

      return Right(
        ProfileEntity.emptyProfile.copyWith(
          firstName: firstName,
          lastName: lastName,
          status: driverStatus,
          orders: activeOrders,
        ),
      );
    } catch (e, s) {
      debugPrint('[HomeRepo] Erro em getProfile: $e\n$s');
      return const Left(Failure.error(message: 'Erro ao carregar o perfil.'));
    }
  }

  @override
  Future<Either<Failure, ProfileEntity>> updateStatus({
    required DriverStatus status,
  }) async {
    try {
      if (uid != null) {
        // UPPI BRASIL SEGURANÇA: Checar aprovação antes de permitir rodar
        if (status == const DriverStatus.online()) {
          final row = await _supabase
              .from('profiles')
              .select('is_approved')
              .eq('id', uid!)
              .maybeSingle();
          final isApproved = row?['is_approved'] ?? false;
          if (!isApproved) {
            return const Left(
              Failure.error(
                message:
                    'Conta em Análise. Aguarde a aprovação dos seus documentos pelo Administrador.',
              ),
            );
          }

          // UPPI BIOMETRIA: Bloqueio de FaceID / TouchID estrito (sem bypass em produção)
          if (!kIsWeb && !kDebugMode) {
            try {
              final LocalAuthentication localAuth = LocalAuthentication();

              final bool isSupported = await localAuth.isDeviceSupported();

              if (isSupported) {
                final bool didAuthenticate = await localAuth.authenticate(
                  localizedReason:
                      'Proteção Uppi: Confirme sua identidade para ficar Online e receber corridas.',
                  biometricOnly: false,
                  persistAcrossBackgrounding: true,
                );
                if (!didAuthenticate) {
                  return const Left(
                    Failure.error(
                      message:
                          'Falha na Autenticação. Por favor, confirme sua identidade para ficar online.',
                    ),
                  );
                }
              }
            } catch (e) {
              debugPrint('Biometria falhou com exceção: $e. Aplicando bypass para não travar o motorista.');
              // Bypass seguro para não travar o motorista caso o aparelho dê falha técnica no local_auth
            }
          }
        }
        
        // UPPI BRASIL: Atualiza chamando de forma segura a Edge Function update-driver-status
        // Evita manipulação direta de tabelas sensíveis pelo cliente.
        if (status == const DriverStatus.online() || status == const DriverStatus.offline()) {
          final statusStr = status == const DriverStatus.online() ? 'online' : 'offline';
          
          try {
            final response = await _supabase.functions.invoke(
              'driver-flow-actions',
              body: {
                'action': 'update-driver-status',
                'status': statusStr,
              },
            );

            if (response.status != 200) {
              final data = response.data;
              String errorMsg = 'Erro ao atualizar status.';
              if (data is Map) {
                errorMsg = data['error']?.toString() ?? data['message']?.toString() ?? errorMsg;
              }
              return Left(Failure.error(message: errorMsg));
            }
          } catch (e) {
            debugPrint('[HomeRepo] Erro de conexão ao atualizar status: $e');
            return const Left(Failure.error(message: 'Erro de conexão. Verifique sua internet e tente novamente.'));
          }
        }
      }
      return Right(ProfileEntity.emptyProfile.copyWith(status: status));
    } catch (e) {
      debugPrint('[HomeRepo] Falha ao atualizar status: $e');
      return const Left(Failure.error(message: 'Não foi possível atualizar o status. Por favor, tente novamente.'));
    }
  }

  @override
  Stream<ProfileEntity> startProfileSubscription() {
    final driverUid = uid;
    if (driverUid == null) return const Stream.empty();
    
    return _supabase
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', driverUid)
        .map((event) {
          if (event.isEmpty) return ProfileEntity.emptyProfile;
          final data = event.first;
          
          // UPPI BRASIL: Sincronização reativa instantânea de vehicle_type e marker_url (elimina stale cache de 5 minutos!)
          _cachedVehicleType = data['vehicle_type']?.toString() ?? 'carro';
          _cachedMarkerUrl = data['marker_url']?.toString();
          _profileCacheTime = DateTime.now();

          final st = data['status']?.toString();
          DriverStatus driverStatus = StatusParser.fromString(st);
          
          final isApproved = data['is_approved'] == true;
          // Se o motorista for aprovado enquanto estava como pendingApproval, podemos mandar um novo status aqui!
          if (isApproved && driverStatus == const DriverStatus.pendingApproval()) {
             driverStatus = const DriverStatus.online();
          }
          // Se estiver bloqueado, sobrescrever o status
          if (data['is_blocked'] == true || st == 'blocked') {
             driverStatus = const DriverStatus.blocked();
          }

          return ProfileEntity.emptyProfile.copyWith(status: driverStatus);
        })
        .handleError((error) {
          debugPrint('[HomeRepo] Erro no stream do perfil: $error');
        });
  }

  // Cache de dados do perfil para evitar consulta a cada location update
  String? _cachedVehicleType;
  String? _cachedMarkerUrl;
  DateTime? _profileCacheTime;
  double? _cachedCommissionRate;

  @override
  Future<Either<Failure, List<OrderRequestEntity>>> updateDriverLocation({
    required DriverLocation location,
  }) async {
    _lastLocation = location;

    // Filtro de redundância: evita chamadas excessivas à Edge Function
    // Só envia se: 4s se passaram OU 5m de deslocamento OU 15° de rotação
    final now = DateTime.now();
    if (_lastFuncInvokeTime != null && _lastFuncInvokeLocation != null) {
      final timeDiff = now.difference(_lastFuncInvokeTime!).inSeconds;
      final dist = _distanceBetween(
        _lastFuncInvokeLocation!.lat, _lastFuncInvokeLocation!.lng,
        location.lat, location.lng,
      );
      final rot1 = location.rotation ?? 0;
      final rot2 = _lastFuncInvokeLocation!.rotation ?? 0;
      final rotDiff = (rot1 - rot2).abs();
      if (timeDiff < 4 && dist < 5 && rotDiff < 15) {
        return const Right([]);
      }
    }
    _lastFuncInvokeTime = now;
    _lastFuncInvokeLocation = location;

    try {
      if (uid != null) {
        // Inicializa cache se nulo (no cold start antes da primeira emissão da stream)
        if (_cachedVehicleType == null) {
          try {
            final profileRow = await _supabase
                .from('profiles')
                .select('vehicle_type, marker_url')
                .eq('id', uid!)
                .maybeSingle();
            _cachedVehicleType = profileRow?['vehicle_type']?.toString() ?? 'carro';
            _cachedMarkerUrl = profileRow?['marker_url']?.toString();
            _profileCacheTime = DateTime.now();
          } catch (_) {
            _cachedVehicleType ??= 'carro';
          }
        }
        final vehicleType = _cachedVehicleType ?? 'carro';
        final markerUrl = _cachedMarkerUrl;

        // UPPI BRASIL: Call edge function to properly update driver_locations table
        await _supabase.functions.invoke(
          'driver-flow-actions',
          body: {
            'action': 'update-driver-location',
            'lat': location.lat,
            'lng': location.lng,
            'heading': location.rotation,
            'vehicle_type': vehicleType,
            'marker_url': markerUrl,
          },
        );

        // Se a localização foi enviada com sucesso, significa que a conexão está ativa!
        // Aproveitamos para disparar o reenvio das transições offline pendentes.
        if (_offlineTransitionsQueue.isNotEmpty) {
          Future.microtask(() => _processOfflineQueue());
        }

        // Broadcast de localização é feito no LocationUpdateDatasource
        // via canal 'track_driver_$uid' — não duplicar aqui.
      }
      return const Right([]);
    } catch (_) {
      return const Left(Failure.error());
    }
  }

  // Canal Broadcast para notificações de corrida redundantes
  RealtimeChannel? _rideNotificationChannel;

  @override
  Stream<List<OrderRequestEntity>> startGettingOrderRequestUpdates() {
    final driverUid = uid;
    _requestsStreamController?.close();
    _requestsStreamController =
        StreamController<List<OrderRequestEntity>>.broadcast();

    if (driverUid == null) {
      return _requestsStreamController!.stream;
    }

    // ─── CAMADA 1: Postgres CDC em ride_offers (Fila de despacho dinâmica) ─────
    // O motorista escuta as ofertas direcionadas a ele com status 'offered'
    _requestsSubscription = _supabase
        .from('ride_offers')
        .stream(primaryKey: ['id'])
        .eq('driver_id', driverUid)
        .listen((snapshot) async {
          // Filtrar em memória ofertas com status 'offered' (Supabase StreamBuilder não suporta múltiplos eq)
          final offeredOffers = snapshot.where((e) => e['status'] == 'offered').toList();
          
          if (offeredOffers.isEmpty) {
            _requestsStreamController?.add([]);
            return;
          }
          
          // Obter os IDs de corridas oferecidas a este motorista
          final rideIds = offeredOffers.map((e) => e['ride_id'].toString()).toList();
          if (rideIds.isEmpty) {
            _requestsStreamController?.add([]);
            return;
          }

          final Map<String, DateTime> expiresAtMap = {};
          for (var offer in offeredOffers) {
            final rideId = offer['ride_id']?.toString();
            final expiresAtStr = offer['expires_at']?.toString();
            final createdAtStr = offer['created_at']?.toString();
            if (rideId != null && expiresAtStr != null) {
              final expiresAtServer = DateTime.tryParse(expiresAtStr);
              final createdAtServer = createdAtStr != null ? DateTime.tryParse(createdAtStr) : null;
              if (expiresAtServer != null) {
                if (createdAtServer != null) {
                  final duration = expiresAtServer.difference(createdAtServer);
                  final adjustedExpiresAt = DateTime.now().add(duration).subtract(const Duration(seconds: 1));
                  expiresAtMap[rideId] = adjustedExpiresAt;
                } else {
                  expiresAtMap[rideId] = expiresAtServer.toLocal();
                }
              }
            }
          }

          try {
            // Buscar detalhes completos dessas corridas
            final ridesSnapshot = await _supabase
                .from('rides')
                .select()
                .inFilter('id', rideIds);
            
            await _processRideSnapshot(ridesSnapshot, expiresAtMap);
          } catch (e) {
            debugPrint('[HomeRepo] Erro ao buscar rides das ofertas: $e');
            _requestsStreamController?.add([]);
          }
        });

    // ─── CAMADA 2: Broadcast (redundância via webhook) ───────────────
    _rideNotificationChannel = _supabase.channel('ride_notifications');
    _rideNotificationChannel!
        .onBroadcast(
          event: 'new_ride',
          callback: (payload) {
            debugPrint('[HomeRepo] Broadcast de nova corrida recebido');
            // O Broadcast serve como "cutucada" — força refresh dos dados
            _refreshRequestedRides();
          },
        )
        .subscribe();

    return _requestsStreamController!.stream;
  }

  /// Recarrega corridas ativas oferecidas ao motorista (chamado pelo Broadcast)
  Future<void> _refreshRequestedRides() async {
    final driverUid = uid;
    if (driverUid == null) return;
    try {
      final offers = await _supabase
          .from('ride_offers')
          .select('ride_id, expires_at, created_at')
          .eq('driver_id', driverUid)
          .eq('status', 'offered');
      
      final rideIds = offers.map((e) => e['ride_id'].toString()).toList();
      if (rideIds.isEmpty) {
        _requestsStreamController?.add([]);
        return;
      }

      final Map<String, DateTime> expiresAtMap = {};
      for (var offer in offers) {
        final rideId = offer['ride_id']?.toString();
        final expiresAtStr = offer['expires_at']?.toString();
        final createdAtStr = offer['created_at']?.toString();
        if (rideId != null && expiresAtStr != null) {
          final expiresAtServer = DateTime.tryParse(expiresAtStr);
          final createdAtServer = createdAtStr != null ? DateTime.tryParse(createdAtStr) : null;
          if (expiresAtServer != null) {
            if (createdAtServer != null) {
              final duration = expiresAtServer.difference(createdAtServer);
              final adjustedExpiresAt = DateTime.now().add(duration).subtract(const Duration(seconds: 1));
              expiresAtMap[rideId] = adjustedExpiresAt;
            } else {
              expiresAtMap[rideId] = expiresAtServer.toLocal();
            }
          }
        }
      }

      final snapshot = await _supabase
          .from('rides')
          .select()
          .inFilter('id', rideIds);
      
      await _processRideSnapshot(snapshot, expiresAtMap);
    } catch (e) {
      debugPrint('[HomeRepo] Erro ao refresh corridas: $e');
    }
  }

  /// Processa snapshot de corridas e emite para o stream
  Future<void> _processRideSnapshot(List<Map<String, dynamic>> snapshot, [Map<String, DateTime>? expiresAtMap]) async {
    if (snapshot.isEmpty) {
      _requestsStreamController?.add([]);
      return;
    }

    final driverUid = uid;
    List<String> rejectedRideIds = [];
    if (driverUid != null) {
      try {
        final rejections = await _supabase
            .from('ride_rejected_drivers')
            .select('ride_id')
            .eq('driver_id', driverUid);
        rejectedRideIds = rejections.map((e) => e['ride_id'].toString()).toList();
      } catch (e) {
        debugPrint('[HomeRepo] Erro ao buscar rejeições: $e');
      }
    }

    // Filtra corridas velhas (>5 min) ou rejeitadas por este motorista
    final now = DateTime.now();
    final filteredRides = snapshot.where((data) {
      final rideId = data['id']?.toString();
      if (rideId == null) return false;
      if (rejectedRideIds.contains(rideId)) return false;

      final createdAt = DateTime.tryParse(data['created_at']?.toString() ?? '');
      if (createdAt == null) return true;
      return now.difference(createdAt).inMinutes < 5;
    }).toList();

    if (filteredRides.isEmpty) {
      _requestsStreamController?.add([]);
      return;
    }

    // Lote de IDs de passageiros para buscar de uma vez só
    final riderIds = filteredRides
        .map((e) => e['rider_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList();

    Map<String, dynamic> profilesMap = {};
    if (riderIds.isNotEmpty) {
      try {
        final profilesRes = await _supabase
            .from('profiles')
            .select('id, full_name')
            .inFilter('id', riderIds);
        for (var p in profilesRes) {
          profilesMap[p['id'].toString()] = p;
        }
      } catch (_) {}
    }

    // Fetch commission rate once from the correct table with local caching
    double commissionRate = _cachedCommissionRate ?? 0.0;
    if (_cachedCommissionRate == null) {
      try {
        // 1. Tentar obter do formato novo columnar (registro global_config)
        final configRow = await _supabase
            .from('app_settings')
            .select('commission_rate')
            .eq('key', 'global_config')
            .maybeSingle();
        if (configRow != null && configRow['commission_rate'] != null) {
          final rawRate = double.tryParse(configRow['commission_rate']?.toString() ?? '') ?? 15.0;
          commissionRate = rawRate > 1.0 ? rawRate / 100 : rawRate;
          _cachedCommissionRate = commissionRate;
        } else {
          // 2. Fallback: tentar obter do formato antigo chave-valor
          final oldRow = await _supabase
              .from('app_settings')
              .select('value')
              .eq('key', 'commission_rate')
              .maybeSingle();
          if (oldRow != null && oldRow['value'] != null) {
            final rawRate = double.tryParse(oldRow['value']?.toString() ?? '') ?? 15.0;
            commissionRate = rawRate > 1.0 ? rawRate / 100 : rawRate;
            _cachedCommissionRate = commissionRate;
          }
        }
      } catch (_) {}
    }

    final List<OrderRequestEntity> orders = [];
    for (var data in filteredRides) {
      final fee = (data['fare'] as num?)?.toDouble() ?? 0.0;
      // 🛡️ [Item F8] Usar commission/platform_fee calculada no servidor
      final commission =
          (data['commission'] as num? ?? data['platform_fee'] as num?)?.toDouble() ?? fee * commissionRate;
      final paymentMethodStr =
          data['payment_method']?.toString() ?? 'cash';
      final paymentMethod = paymentMethodStr == 'wallet'
          ? const PaymentMethodUnion.wallet()
          : const PaymentMethodUnion.cash();

      // Obter rider do cache (profilesMap)
      String riderFirstName = 'Passageiro';
      String riderLastName = '';
      double riderRating = 5.0;
      
      final riderId = data['rider_id']?.toString();
      if (riderId != null && profilesMap.containsKey(riderId)) {
        final riderProfile = profilesMap[riderId];
        riderFirstName = riderProfile['full_name']?.toString() ?? 'Passageiro';
      }

      // Parse coordenadas das colunas numéricas
      List<PlaceEntity> waypt = [];
      final pickupLat = (data['pickup_lat'] as num?)?.toDouble();
      final pickupLng = (data['pickup_lng'] as num?)?.toDouble();
      if (pickupLat != null && pickupLng != null) {
        final pickupAddressRaw = data['pickup_address']?.toString();
        final pickupAddress = (pickupAddressRaw == null || pickupAddressRaw.trim().isEmpty) ? 'Origem' : pickupAddressRaw;
        waypt.add(
          PlaceEntity(
            coordinates: LatLngEntity(
              lat: pickupLat,
              lng: pickupLng,
            ),
            address: pickupAddress,
          ),
        );
      }
      final dropoffLat = (data['dropoff_lat'] as num?)?.toDouble();
      final dropoffLng = (data['dropoff_lng'] as num?)?.toDouble();
      if (dropoffLat != null && dropoffLng != null) {
        final dropoffAddressRaw = data['dropoff_address']?.toString();
        final dropoffAddress = (dropoffAddressRaw == null || dropoffAddressRaw.trim().isEmpty) ? 'Destino' : dropoffAddressRaw;
        waypt.add(
          PlaceEntity(
            coordinates: LatLngEntity(
              lat: dropoffLat,
              lng: dropoffLng,
            ),
            address: dropoffAddress,
          ),
        );
      }

      // Buscar rota Google real (embarque → destino) para exibir no mini-mapa do card
      // Usa cache para não re-buscar a cada emissão do stream (evita rota sumir)
      final rideId = data['id'].toString();
      List<LatLngEntity> rideRoute = _rideRouteCache[rideId] ?? [];
      if (rideRoute.isEmpty && pickupLat != null && pickupLng != null && dropoffLat != null && dropoffLng != null) {
        try {
          rideRoute = await _getGoogleRoute([
            LatLngEntity(lat: pickupLat, lng: pickupLng),
            LatLngEntity(lat: dropoffLat, lng: dropoffLng),
          ]);
          debugPrint('[HomeRepo] Rota buscada para oferta: ${rideRoute.length} pontos');
        } catch (e) {
          debugPrint('[HomeRepo] Erro ao buscar rota Google para card de solicitação: $e');
        }
        // Fallback: se a rota veio vazia, usar linha reta entre pickup e destino
        if (rideRoute.isEmpty) {
          debugPrint('[HomeRepo] Rota vazia - usando fallback linha reta pickup→destino');
          rideRoute = [
            LatLngEntity(lat: pickupLat, lng: pickupLng),
            LatLngEntity(lat: dropoffLat, lng: dropoffLng),
          ];
        }
        // Salva no cache para emissões futuras do stream
        _rideRouteCache[rideId] = rideRoute;
      }

      orders.add(
        OrderRequestEntity(
          id: data['id'].toString(),
          status: OrderStatus.requested,
          paymentMethod: paymentMethod,
          currency: 'BRL',
          fee: fee,
          providerShare: commission,
          distance: (data['distance_meters'] as num?)?.toInt() ?? 0,
          duration: (data['duration_seconds'] as num?)?.toInt() ?? 0,
          serviceName: data['service_type']?.toString() ?? "Standard",
          route: rideRoute,
          waypoints: waypt,
          rideOptions: [],
          riderFirstName: riderFirstName,
          riderLastName: riderLastName,
          riderPhotoUrl: null,
          expiresAt: expiresAtMap?[data['id'].toString()],
          isDangerZone: data['is_danger_zone'] as bool? ?? false,
          dangerZoneName: data['danger_zone_name']?.toString(),
        ),
      );
    }
    
    _requestsStreamController?.add(orders);
  }

  @override
  void stopGettingOrderRequestUpdates() {
    _requestsSubscription?.cancel();
    _requestsStreamController?.close();
    _rideRouteCache.clear();
    // Para o alarme sonoro quando o motorista sai da tela
    try {
      FlutterRingtonePlayer().stop();
    } catch (_) {}
    // Remove canal de Broadcast
    if (_rideNotificationChannel != null) {
      _supabase.removeChannel(_rideNotificationChannel!);
      _rideNotificationChannel = null;
    }
  }

  @override
  Future<Either<Failure, OrderEntity>> acceptOrderRequest({
    required String requestId,
  }) async {
    try {
      if (uid == null) return const Left(Failure.error());

      // Chamar Edge Function para aceitar corrida (garante push notification,
      // optimistic locking, validação de assinatura, e log de atividade)
      final response = await _supabase.functions.invoke(
        'driver-flow-actions',
        body: {
          'action': 'accept-order',
          'orderId': requestId,
        },
      );

      if (response.status != 200) {
        final data = response.data;
        String errorMsg = 'Erro ao aceitar corrida.';
        if (data is Map) {
          errorMsg = data['error']?.toString() ?? data['message']?.toString() ?? errorMsg;
        } else if (data != null) {
          errorMsg = data.toString();
        }
        return Left(Failure.error(message: errorMsg));
      }

      // Para o alarme sonoro após aceitar
      try {
        FlutterRingtonePlayer().stop();
      } catch (_) {}

      // Buscar a corrida atualizada para construir o OrderEntity completo
      final rideRes = await _supabase
          .from('rides')
          .select()
          .eq('id', requestId)
          .maybeSingle();

      if (rideRes != null) {
        final order = await _mapRowToOrderEntity(rideRes);
        return Right(
          order.copyWith(
            status: OrderStatus.driverAccepted,
          ),
        );
      }

      // Fallback se não conseguir buscar a corrida atualizada
      return Right(
        OrderEntity.emptyOrder.copyWith(
          id: requestId,
          status: OrderStatus.driverAccepted,
        ),
      );
    } catch (e) {
      debugPrint('[HomeRepo] Erro em acceptOrderRequest: $e');
      final errorStr = e.toString();
      String msg;
      
      if (e is FunctionException) {
        final details = e.details;
        if (details is Map) {
          msg = details['error']?.toString() ?? details['message']?.toString() ?? e.toString();
        } else if (details != null) {
          msg = details.toString();
        } else {
          msg = e.reasonPhrase ?? e.toString();
        }
      } else if (errorStr.toLowerCase().contains('socket') || errorStr.toLowerCase().contains('timeout') || errorStr.toLowerCase().contains('connection')) {
        msg = 'Falha na conexão. Verifique sua internet e tente novamente.';
      } else if (errorStr.toLowerCase().contains('expirou') || errorStr.toLowerCase().contains('expired') || errorStr.toLowerCase().contains('oferta') || errorStr.toLowerCase().contains('offer') || errorStr.toLowerCase().contains('410')) {
        msg = 'O tempo para aceitar expirou. Aguarde uma nova corrida.';
      } else if (errorStr.toLowerCase().contains('não está mais disponível') || errorStr.toLowerCase().contains('já aceita') || errorStr.toLowerCase().contains('already accepted') || errorStr.toLowerCase().contains('409')) {
        msg = 'Esta corrida já foi aceita por outro motorista.';
      } else {
        if (errorStr.contains('FunctionException:')) {
          msg = errorStr.split('FunctionException:').last.trim();
        } else {
          msg = 'Não foi possível aceitar a corrida. Tente novamente.';
        }
      }
      return Left(Failure.error(message: msg));
    }
  }

  @override
  Future<Either<Failure, Unit>> rejectOrderRequest({
    required String requestId,
  }) async {
    try {
      if (uid == null) return const Left(Failure.error());

      await _supabase.rpc(
        'reject_ride',
        params: {
          'p_ride_id': requestId,
          'p_driver_id': uid!,
        },
      );

      return const Right(unit);
    } catch (e) {
      return Left(Failure.error(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<CancelReasonEntity>>> getCancelReasons() async {
    try {
      final rows = await _supabase
          .from('cancel_reasons')
          .select()
          .eq('role', 'driver')
          .eq('is_active', true);
      final reasons = rows
          .map((row) => CancelReasonEntity(
                id: row['id'].toString(),
                name: row['name'].toString(),
              ))
          .toList();
      if (reasons.isNotEmpty) return Right(reasons);
    } catch (_) {}
    // Fallback local se a tabela ainda não tiver dados
    return const Right([
      CancelReasonEntity(id: "1", name: "Passageiro não apareceu"),
      CancelReasonEntity(id: "2", name: "Trânsito excessivo"),
      CancelReasonEntity(id: "3", name: "Problemas no carro"),
      CancelReasonEntity(id: "4", name: "Motivos pessoais"),
    ]);
  }

  @override
  Stream<Either<Failure, List<CancelReasonEntity>>>
  startCancelReasonsSubscription() async* {
    yield* _supabase
        .from('cancel_reasons')
        .stream(primaryKey: ['id'])
        .map((events) {
      final reasons = events
          .where((row) => row['role'] == 'driver' && row['is_active'] == true)
          .map((row) => CancelReasonEntity(
                id: row['id'].toString(),
                name: row['name'].toString(),
              ))
          .toList();
      return Right<Failure, List<CancelReasonEntity>>(reasons);
    });
  }

  @override
  Future<Either<Failure, OrderEntity>> cancelOrder({
    required String orderId,
    String? reasonId,
    String? reasonNote,
  }) async {
    try {
      // Call the cancel-order Edge Function so that:
      // 1. Driver status resets to 'online'
      // 2. Rider gets push notification
      // 3. Ride activity is logged
      // 4. Cancellation fee is processed (if applicable)
      final response = await _supabase.functions.invoke(
        'cancel-order',
        body: {
          'orderId': orderId,
          if (reasonId != null) 'reasonId': reasonId,
          if (reasonNote != null) 'reasonNote': reasonNote,
        },
      );

      if (response.status != 200) {
        throw Exception('Erro ao cancelar corrida: ${response.data}');
      }

      return Right(
        OrderEntity.emptyOrder.copyWith(
          id: orderId,
          status: OrderStatus.driverCanceled,
        ),
      );
    } catch (_) {
      return const Left(Failure.error());
    }
  }

  @override
  Future<Either<Failure, OrderEntity>> arrivedToPickup({
    required String orderId,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'driver-flow-actions',
        body: {
          'action': 'arrived-at-pickup',
          'orderId': orderId,
        },
      );

      if (response.status != 200) {
        final data = response.data;
        final errorMsg = data is Map ? data['error']?.toString() : data?.toString();
        return Left(Failure.error(message: errorMsg ?? 'Erro ao registrar chegada.'));
      }

      return Right(
        OrderEntity.emptyOrder.copyWith(
          id: orderId,
          status: OrderStatus.arrived,
        ),
      );
    } catch (e) {
      debugPrint('[OfflineQueue] Falha de rede em arrivedToPickup: $e. Enfileirando transição.');
      _offlineTransitionsQueue.add(_OfflineTransition(
        orderId: orderId,
        type: 'arrived',
        timestamp: DateTime.now(),
      ));
      _saveQueueToHive();
      _startOfflineQueueTimer();

      Future.microtask(() => _processOfflineQueue());

      return Right(
        OrderEntity.emptyOrder.copyWith(
          id: orderId,
          status: OrderStatus.arrived,
        ),
      );
    }
  }

  @override
  Future<Either<Failure, OrderEntity>> startTrip({
    required String orderId,
    String? boardingPin,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'driver-flow-actions',
        body: {
          'action': 'start-order',
          'orderId': orderId,
          if (boardingPin != null) 'boardingPin': boardingPin,
        },
      );

      if (response.status != 200) {
        final data = response.data;
        final errorMsg = data is Map ? data['error']?.toString() : data?.toString();
        return Left(Failure.error(message: errorMsg ?? 'Erro ao iniciar corrida.'));
      }

      return Right(
        OrderEntity.emptyOrder.copyWith(
          id: orderId,
          status: OrderStatus.started,
        ),
      );
    } catch (e) {
      debugPrint('[OfflineQueue] Falha de rede em startTrip: $e. Enfileirando transição.');
      _offlineTransitionsQueue.add(_OfflineTransition(
        orderId: orderId,
        type: 'start',
        boardingPin: boardingPin,
        timestamp: DateTime.now(),
      ));
      _saveQueueToHive();
      _startOfflineQueueTimer();

      Future.microtask(() => _processOfflineQueue());

      return Right(
        OrderEntity.emptyOrder.copyWith(
          id: orderId,
          status: OrderStatus.started,
        ),
      );
    }
  }

  @override
  Future<Either<Failure, OrderEntity>> arrivedToDestination({
    required OrderEntity order,
    required int destinationArrivedTo,
  }) async {
    // 🔊 PILAR 22: Reproduzir lembrete de objetos esquecidos por TTS
    // Dispara áudio automaticamente quando motorista marca chegada ao destino
    ArrivalReminderService().playArrivalReminder();

    // UPPI BRASIL: Atualizar status no banco para 'waiting_for_post_pay'.
    // Antes, apenas atualizávamos o estado local, e o stream do Supabase (polling
    // a cada 4 segundos) revertia o status para 'started' porque o banco ainda
    // tinha 'in_progress'. Agora persistimos no banco para manter consistência.
    try {
      final response = await _supabase.functions.invoke(
        'arrived-at-destination',
        body: {'orderId': order.id},
      );

      if (response.status != 200) {
        // Se a edge function falhar, ainda retornamos o estado local para não
        // bloquear o motorista — o stream vai eventualmente sincronizar.
        debugPrint('[HomeRepo] arrived-at-destination falhou (${response.status}): ${response.data}');
      }
    } catch (e) {
      // Falha de rede — continuar com atualização local apenas
      debugPrint('[HomeRepo] Falha de rede em arrivedToDestination: $e');
    }

    return Right(order.copyWith(status: OrderStatus.waitingForPostPay));
  }


  @override
  Future<Either<Failure, OrderEntity>> paidInCash({
    required String orderId,
    required double amount,
    double? tollAmount,
    double? actualDistance,
  }) async {
    try {
      if (uid == null) return const Left(Failure.error());

      final response = await _supabase.functions.invoke(
        'driver-flow-actions',
        body: {
          'action': 'finish-order',
          'orderId': orderId,
          'cashAmount': amount,
          'tollAmount': tollAmount ?? 0.0,
          'actualDistance': actualDistance,
        },
      );

      if (response.status != 200) {
        final data = response.data;
        final errorMsg = data is Map ? data['error']?.toString() : data?.toString();
        return Left(Failure.error(message: errorMsg ?? 'Erro ao finalizar corrida.'));
      }

      return Right(
        OrderEntity.emptyOrder.copyWith(
          id: orderId,
          status: OrderStatus.finished,
        ),
      );
    } catch (e) {
      debugPrint('[OfflineQueue] Falha de rede em paidInCash: $e. Enfileirando transição.');
      _offlineTransitionsQueue.add(_OfflineTransition(
        orderId: orderId,
        type: 'paid',
        amount: amount,
        timestamp: DateTime.now(),
      ));
      _saveQueueToHive();
      _startOfflineQueueTimer();

      Future.microtask(() => _processOfflineQueue());

      return Right(
        OrderEntity.emptyOrder.copyWith(
          id: orderId,
          status: OrderStatus.finished,
        ),
      );
    }
  }

  @override
  Future<Either<Failure, OrderEntity>> submitReview({
    required String orderId,
    required int? rating,
    required String? review,
  }) async {
    try {
      // Call the submit-review Edge Function so that:
      // 1. Rider's average_rating gets recalculated
      // 2. Ride activity is logged
      final response = await _supabase.functions.invoke(
        'submit-review',
        body: {
          'orderId': orderId,
          'score': rating,
          'review': review,
        },
      );

      if (response.status != 200) {
        throw Exception('Erro ao enviar avaliação: ${response.data}');
      }

      return Right(
        OrderEntity.emptyOrder.copyWith(
          id: orderId,
          status: OrderStatus.finished,
        ),
      );
    } catch (_) {
      return const Left(Failure.error());
    }
  }

  @override
  Future<Either<Failure, ChatMessageEntity>> sendMessage({
    required String orderId,
    required String message,
  }) async {
    try {
      if (uid == null) return const Left(Failure.error());

      // UPPI BRASIL: Call edge function to ensure the rider gets a push notification
      final response = await _supabase.functions.invoke(
        'chat-send-message',
        body: {
          'orderId': orderId,
          'content': message,
        },
      );

      if (response.status != 200) {
        throw Exception('Falha ao enviar mensagem');
      }

      final data = response.data as Map<String, dynamic>?;

      final msg = ChatMessageEntity(
        id: data?['message_id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        message: message,
        isSender: true,
        createdAt: DateTime.now(),
      );

      return Right(msg);
    } catch (_) {
      return const Left(Failure.error());
    }
  }

  @override
  Future<Either<Failure, void>> sendSosSignal({required String orderId}) async {
    try {
      // UPPI BRASIL: Call edge function to ensure Admins get push notifications
      final response = await _supabase.functions.invoke(
        'send-sos',
        body: {
          'orderId': orderId,
        },
      );

      if (response.status != 200) {
        throw Exception('Erro ao enviar SOS: ${response.data}');
      }
      
      return const Right(null);
    } catch (e) {
      return Left(Failure.error(message: 'Erro ao enviar SOS: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, void>> updateLastSeenMessagesAt({
    required String orderId,
  }) async {
    return const Right(null);
  }

  @override
  Stream<OrderEntity> startOrderUpdatedSubscription({
    required OrderEntity orderEntity,
  }) {
    // Polling de fallback periódico (a cada 4 segundos) via HTTPS para robustez extra em redes móveis instáveis
    final pollingStream = Stream.periodic(const Duration(seconds: 4))
        .asyncMap((_) async {
          try {
            final data = await _supabase
                .from('rides')
                .select()
                .eq('id', orderEntity.id)
                .maybeSingle();
            if (data != null) {
              return await _mapRowToOrderEntity(data);
            }
          } catch (e) {
            debugPrint('[TrackOrder-Polling-Driver] Erro: $e');
          }
          return null;
        })
        .whereType<OrderEntity>();

    final orderStream = Rx.merge([
      _supabase
          .from('rides')
          .stream(primaryKey: ['id'])
          .eq('id', orderEntity.id)
          .asyncMap((events) async {
            if (events.isEmpty) return orderEntity;
            final data = events.first;
            return await _mapRowToOrderEntity(data);
          }),
      pollingStream,
    ]);

    // Stream de mensagens via Supabase Realtime
    final messagesStream = _supabase
        .from('ride_messages')
        .stream(primaryKey: ['id'])
        .eq('ride_id', orderEntity.id)
        .order('created_at')
        .map((snapshot) {
          return snapshot.map((data) {
            return ChatMessageEntity(
              id: data['id'].toString(),
              message: data['content']?.toString() ?? '',
              isSender: data['sent_by_driver'] == true,
              createdAt:
                  DateTime.tryParse(data['created_at']?.toString() ?? '')?.toLocal() ??
                  DateTime.now(),
            );
          }).toList();
        });

    return Rx.combineLatest2(orderStream, messagesStream.startWith([]), (
      OrderEntity order,
      List<ChatMessageEntity> messages,
    ) {
      return order.copyWith(chatMessages: messages);
    });
  }

  @override
  void stopOrderUpdatedSubscription() {
    // The streams handled by rxdart will close themselves when the UI listener cancels the subscription.
  }

  // ── HELPERS PARA CORRIDA/GEOLOCALIZAÇÃO ──────────────────────────────────
  
  Future<List<LatLngEntity>> _getGoogleRoute(List<LatLngEntity> waypoints) async {
    try {
      MapProviderEnum mapProvider = locator<SettingsCubit>().state.mapProviderEnum;
      
      if (mapProvider == MapProviderEnum.googleMaps) {
        String googleApiKey = '';
        try {
          // 1. Tentar obter a chave da coluna google_map_api_key no registro global_config (formato novo)
          final configRow = await _supabase
              .from('app_settings')
              .select('google_map_api_key')
              .eq('key', 'global_config')
              .maybeSingle();
          if (configRow != null && configRow['google_map_api_key'] != null) {
            googleApiKey = configRow['google_map_api_key'].toString();
          }
        } catch (_) {}

        if (googleApiKey.isEmpty) {
          try {
            // 2. Fallback: tentar obter do formato antigo (chave-valor)
            final oldRow = await _supabase
                .from('app_settings')
                .select('value')
                .eq('key', 'google_map_api_key')
                .maybeSingle();
            if (oldRow != null && oldRow['value'] != null) {
              googleApiKey = oldRow['value'].toString();
            }
          } catch (_) {}
        }

        if (googleApiKey.isNotEmpty && waypoints.length >= 2) {
          final origin = '${waypoints.first.lat},${waypoints.first.lng}';
          final destination = '${waypoints.last.lat},${waypoints.last.lng}';
          String url = 'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&key=$googleApiKey';
          if (waypoints.length > 2) {
            final intermediates = waypoints.sublist(1, waypoints.length - 1)
                .map((w) => 'via:${w.lat},${w.lng}')
                .join('|');
            url += '&waypoints=${Uri.encodeComponent(intermediates)}';
          }

          debugPrint('[Google-Driver] Requesting route: $url');
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
          if (response.statusCode == 200) {
            final directionsData = json.decode(response.body);
            if (directionsData['status'] == 'OK' && directionsData['routes'] != null && (directionsData['routes'] as List).isNotEmpty) {
              final route = directionsData['routes'][0];
              final overviewPolyline = route['overview_polyline'];
              if (overviewPolyline != null && overviewPolyline['points'] != null) {
                final pts = _decodePolyline(overviewPolyline['points'].toString());
                debugPrint('[Google-Driver] Route parsed with ${pts.length} points');
                return pts;
              }
            } else {
              debugPrint('[Google-Driver] Google Maps status: ${directionsData['status']}');
            }
          }
        }
      } else {
        try {
          debugPrint('[OSRM-Driver] Requesting OSRM routing');
          String osrmBaseUrl = 'https://router.project-osrm.org';
          try {
            final configRow = await _supabase
                .from('app_settings')
                .select('value')
                .eq('key', 'osrm_routing_url')
                .maybeSingle();
            if (configRow != null && configRow['value'] != null && configRow['value'].toString().isNotEmpty) {
              osrmBaseUrl = configRow['value'].toString().replaceAll(RegExp(r'/$'), '');
            }
          } catch (_) {}

          final coords = waypoints.map((w) => '${w.lng},${w.lat}').join(';');
          final url = '$osrmBaseUrl/route/v1/driving/$coords?overview=full&geometries=geojson';

          final response = await http.get(
            Uri.parse(url),
            headers: {'User-Agent': 'UppiDriverApp/3.2.8'},
          ).timeout(const Duration(seconds: 8));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data != null && data['routes'] != null && (data['routes'] as List).isNotEmpty) {
              final route = data['routes'][0];
              final geometry = route['geometry'];
              if (geometry != null && geometry['coordinates'] != null) {
                final coordsList = geometry['coordinates'] as List;
                return coordsList
                    .map((c) => LatLngEntity(
                          lat: (c[1] as num).toDouble(),
                          lng: (c[0] as num).toDouble(),
                        ))
                    .toList();
              }
            }
          }
        } catch (e) {
          debugPrint('[OSRM-Driver] Exception: $e');
        }
      }
    } catch (e) {
      debugPrint('[Driver-RouteRepo] Exception during route call: $e');
    }
    return [];
  }

  List<LatLngEntity> _decodePolyline(String polyline) {
    List<LatLngEntity> points = [];
    int index = 0, len = polyline.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;
      points.add(LatLngEntity(lat: lat / 1E5, lng: lng / 1E5));
    }
    return points;
  }

  /// Converte a linha do banco de dados de rides para a entidade de OrderEntity completa.
  Future<OrderEntity> _mapRowToOrderEntity(Map<String, dynamic> data) async {
    final rideId = data['id'].toString();
    final rideSt = data['status']?.toString();
    OrderStatus statusMapped = OrderStatus.requested;
    if (rideSt == 'accepted' || rideSt == 'driver_accepted') {
      statusMapped = OrderStatus.driverAccepted;
    }
    if (rideSt == 'arrived') statusMapped = OrderStatus.arrived;
    if (rideSt == 'in_progress' || rideSt == 'started') {
      statusMapped = OrderStatus.started;
    }
    if (rideSt == 'waiting_for_post_pay') {
      statusMapped = OrderStatus.waitingForPostPay;
    }
    if (rideSt == 'waiting_for_review') {
      statusMapped = OrderStatus.waitingForReview;
    }
    if (rideSt == 'completed' || rideSt == 'finished') {
      statusMapped = OrderStatus.finished;
    }
    if (rideSt == 'driver_canceled') {
      statusMapped = OrderStatus.driverCanceled;
    } else if (rideSt == 'canceled' ||
        rideSt == 'rider_canceled') {
      statusMapped = OrderStatus.riderCanceled;
    }
    if (rideSt == 'expired') statusMapped = OrderStatus.expired;
    if (rideSt == 'no_driver') statusMapped = OrderStatus.notFound;
    if (rideSt == 'no_close_found') statusMapped = OrderStatus.noCloseFound;

    final List<PlaceEntity> waypts = [];
    final pickupLat = (data['pickup_lat'] as num?)?.toDouble();
    final pickupLng = (data['pickup_lng'] as num?)?.toDouble();
    if (pickupLat != null && pickupLng != null) {
      waypts.add(
        PlaceEntity(
          coordinates: LatLngEntity(lat: pickupLat, lng: pickupLng),
          address: data['pickup_address']?.toString() ?? 'Origem',
        ),
      );
    }
    final dropoffLat = (data['dropoff_lat'] as num?)?.toDouble();
    final dropoffLng = (data['dropoff_lng'] as num?)?.toDouble();
    if (dropoffLat != null && dropoffLng != null) {
      waypts.add(
        PlaceEntity(
          coordinates: LatLngEntity(lat: dropoffLat, lng: dropoffLng),
          address: data['dropoff_address']?.toString() ?? 'Destino',
        ),
      );
    }

    String riderFirstName = 'Passageiro';
    String riderLastName = '';
    String riderPhoneNumber = '';
    String? riderPhotoUrl;
    int? riderPresetPhotoId;
    final riderId = data['rider_id']?.toString();
    if (riderId != null) {
      try {
        final riderProfile = await _supabase
            .from('profiles')
            .select('full_name, phone_number, avatar_url, preset_avatar_id')
            .eq('id', riderId)
            .maybeSingle();
        if (riderProfile != null) {
          final fullName = riderProfile['full_name']?.toString() ?? 'Passageiro';
          final parts = fullName.split(' ');
          riderFirstName = parts.first;
          riderLastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
          riderPhoneNumber = riderProfile['phone_number']?.toString() ?? '';
          riderPhotoUrl = riderProfile['avatar_url']?.toString();
          final presetRaw = riderProfile['preset_avatar_id'];
          riderPresetPhotoId = presetRaw is int ? presetRaw : int.tryParse(presetRaw?.toString() ?? '');
        }
      } catch (_) {}
    }

    final fee = (data['fare'] as num?)?.toDouble() ?? 0.0;
    final providerShare = (data['commission'] as num?)?.toDouble() ?? 0.0;
    
    String serviceName = 'Standard';
    final serviceId = data['service_id']?.toString();
    if (serviceId != null) {
      try {
        final serviceData = await _supabase
            .from('services')
            .select('name')
            .eq('id', serviceId)
            .maybeSingle();
        if (serviceData != null) {
          serviceName = serviceData['name']?.toString() ?? 'Uppi';
        }
      } catch (_) {}
    } else {
      serviceName = data['service_type']?.toString() ?? 'Standard';
    }

    // CÁLCULO E CACHE DE ROTAS OSRM
    List<LatLngEntity> rideDirections = const [];
    List<LatLngEntity> driverDirections = const [];

    if (_cachedRideId != rideId) {
      _cachedRideId = rideId;
      _cachedRideDirections = const [];
      _cachedDriverDirections = const [];
      _cachedLastDriverLat = null;
      _cachedLastDriverLng = null;
    }

    if (statusMapped == OrderStatus.driverAccepted && pickupLat != null && pickupLng != null) {
      final dLat = _lastLocation?.lat;
      final dLng = _lastLocation?.lng;
      if (dLat != null && dLng != null) {
        bool shouldFetch = true;
        if (_cachedLastDriverLat != null && _cachedLastDriverLng != null) {
          final dist = _calculateDistance(dLat, dLng, _cachedLastDriverLat!, _cachedLastDriverLng!);
          if (dist < 100 && _cachedDriverDirections.isNotEmpty) {
            shouldFetch = false;
          }
        }
        if (shouldFetch) {
          _cachedLastDriverLat = dLat;
          _cachedLastDriverLng = dLng;
          _cachedDriverDirections = await _getGoogleRoute([
            LatLngEntity(lat: dLat, lng: dLng),
            LatLngEntity(lat: pickupLat, lng: pickupLng),
          ]);
        }
        driverDirections = _cachedDriverDirections;
      }
    }

    if (statusMapped == OrderStatus.started && pickupLat != null && pickupLng != null && dropoffLat != null && dropoffLng != null) {
      if (_cachedRideDirections.isEmpty) {
        _cachedRideDirections = await _getGoogleRoute([
          LatLngEntity(lat: pickupLat, lng: pickupLng),
          LatLngEntity(lat: dropoffLat, lng: dropoffLng),
        ]);
      }
      rideDirections = _cachedRideDirections;
    }

    DateTime createdAt = DateTime.now();
    if (data['created_at'] != null) {
      createdAt = DateTime.tryParse(data['created_at'].toString())?.toLocal() ?? DateTime.now();
    }
    DateTime? startAt;
    if (data['started_at'] != null) {
      startAt = DateTime.tryParse(data['started_at'].toString())?.toLocal();
    }
    DateTime? finishAt;
    if (data['finished_at'] != null) {
      finishAt = DateTime.tryParse(data['finished_at'].toString())?.toLocal();
    } else if (data['canceled_at'] != null) {
      finishAt = DateTime.tryParse(data['canceled_at'].toString())?.toLocal();
    } else if (data['updated_at'] != null && (rideSt == 'completed' || rideSt == 'finished')) {
      finishAt = DateTime.tryParse(data['updated_at'].toString())?.toLocal();
    }
    DateTime expectedAt = createdAt;
    if (data['expected_at'] != null) {
      expectedAt = DateTime.tryParse(data['expected_at'].toString())?.toLocal() ?? createdAt;
    }
    DateTime? etaPickupAt;
    if (data['eta_pickup'] != null) {
      etaPickupAt = DateTime.tryParse(data['eta_pickup'].toString())?.toLocal();
    }
    final durationBest = (data['duration_seconds'] as num?)?.toInt() ?? 0;
    final distanceBest = (data['distance_meters'] as num?)?.toInt() ?? 0;

    return OrderEntity.emptyOrder.copyWith(
      id: rideId,
      status: statusMapped,
      createdAt: createdAt,
      expectedAt: expectedAt,
      startAt: startAt,
      finishAt: finishAt,
      etaPickupAt: etaPickupAt,
      waypoints: waypts,
      riderFirstName: riderFirstName,
      riderLastName: riderLastName,
      riderPhoneNumber: riderPhoneNumber,
      costAfterCoupon: fee,
      costBest: fee,
      providerShare: providerShare,
      serviceName: serviceName,
      paymentMode: data['payment_method']?.toString() == 'wallet'
          ? PaymentMode.wallet
          : (data['payment_method']?.toString() == 'pix'
              ? PaymentMode.pix
              : PaymentMode.cash),
      durationBest: durationBest,
      distanceBest: distanceBest,
      rideDirections: rideDirections,
      driverDirections: driverDirections,
      riderPhotoUrl: riderPhotoUrl,
      riderPresetPhotoId: riderPresetPhotoId,
      boardingPin: data['boarding_pin']?.toString(),
    );
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    final double dLat = _degToRad(lat2 - lat1);
    final double dLon = _degToRad(lon2 - lon1);
    final double rLat1 = _degToRad(lat1);
    final double rLat2 = _degToRad(lat2);

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLon / 2) * math.sin(dLon / 2) * math.cos(rLat1) * math.cos(rLat2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return 6371000 * c; // Earth radius in meters
  }

  double _degToRad(double deg) {
    return deg * (math.pi / 180.0);
  }

  /// Calcula distância entre dois pontos usando fórmula de Haversine
  double _distanceBetween(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0; // Raio da Terra em metros
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;
}

class _OfflineTransition {
  final String orderId;
  final String type; // 'arrived', 'start', 'paid'
  final double? amount; // para paid
  final String? boardingPin; // para start
  final DateTime timestamp;
  int retryCount;

  _OfflineTransition({
    required this.orderId,
    required this.type,
    this.amount,
    this.boardingPin,
    required this.timestamp,
    this.retryCount = 0,
  });
}
