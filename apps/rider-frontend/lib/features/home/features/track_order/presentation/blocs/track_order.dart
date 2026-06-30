
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:flutter_common/core/entities/driver_location.dart';
import 'package:flutter_common/features/chat/chat.dart';
import 'package:rider_flutter/core/entities/order.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter_common/core/blocs/connectivity_cubit.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'dart:async';
import 'package:rider_flutter/core/utils/ongoing_ride_notification_helper.dart';

import '../../domain/repositories/track_order_repository.dart';

part 'track_order.event.dart';
part 'track_order.state.dart';
part 'track_order.models.dart';
part 'track_order.freezed.dart';
part 'track_order.g.dart';

@lazySingleton
class TrackOrderBloc extends Bloc<TrackOrderEvent, TrackOrderState> {
  final TrackOrderRepository repository;
  Stream<(OrderEntity, DriverLocation?)>? orderUpdates;
  final List<ChatMessageEntity> pendingMessages = [];
  StreamSubscription? _connectivitySubscription;
  Timer? _expirationTimer;

  void initConnectivityListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription =
        locator<ConnectivityCubit>().stream.listen((connState) {
      if (connState.isConnected) {
        retryPendingMessages();
      }
    });
  }

  Future<void> sendChatMessage(String messageText) async {
    final isConnected = locator<ConnectivityCubit>().state.isConnected;
    final orderId = state.maybeMap(
      orderInProgres: (inProgress) => inProgress.order.id,
      orElse: () => '',
    );

    if (orderId.isEmpty) return;

    final tempId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final tempMsg = ChatMessageEntity(
      id: tempId,
      message: messageText,
      isSender: true,
      createdAt: DateTime.now(),
    );

    if (!isConnected) {
      pendingMessages.add(tempMsg);
      _forceRebuild();
      return;
    }

    final res =
        await repository.sendMessage(orderId: orderId, message: messageText);
    res.fold(
      (l) {
        pendingMessages.add(tempMsg);
        _forceRebuild();
      },
      (r) {
        add(TrackOrderEvent.messageSent(message: r));
      },
    );
  }

  Future<void> retryMessage(ChatMessageEntity msg) async {
    final isConnected = locator<ConnectivityCubit>().state.isConnected;
    if (!isConnected) return;

    final orderId = state.maybeMap(
      orderInProgres: (inProgress) => inProgress.order.id,
      orElse: () => '',
    );
    if (orderId.isEmpty) return;

    final res =
        await repository.sendMessage(orderId: orderId, message: msg.message);
    res.fold(
      (l) {},
      (r) {
        pendingMessages.removeWhere((m) => m.id == msg.id);
        add(TrackOrderEvent.messageSent(message: r));
      },
    );
  }

  Future<void> retryPendingMessages() async {
    if (pendingMessages.isEmpty) return;
    final isConnected = locator<ConnectivityCubit>().state.isConnected;
    if (!isConnected) return;

    final orderId = state.maybeMap(
      orderInProgres: (inProgress) => inProgress.order.id,
      orElse: () => '',
    );
    if (orderId.isEmpty) return;

    final messagesToRetry = List<ChatMessageEntity>.from(pendingMessages);
    for (final msg in messagesToRetry) {
      final res =
          await repository.sendMessage(orderId: orderId, message: msg.message);
      res.fold(
        (l) {},
        (r) {
          pendingMessages.removeWhere((m) => m.id == msg.id);
          add(TrackOrderEvent.messageSent(message: r));
        },
      );
    }
    _forceRebuild();
  }

  void _forceRebuild() {
    state.maybeMap(
      orderInProgres: (inProgress) {
        // ignore: invalid_use_of_visible_for_testing_member
        emit(inProgress.copyWith());
      },
      orElse: () => null,
    );
  }

  void _manageExpirationTimer(OrderEntity order) {
    _expirationTimer?.cancel();
    _expirationTimer = null;

    if (order.status == OrderStatus.requested) {
      final now = DateTime.now();
      final difference = now.difference(order.createdAt);
      final remaining = const Duration(minutes: 20) - difference;

      if (remaining.isNegative) {
        print('[TrackOrderBloc] Corrida expirada por tempo limite de 20 minutos (início). Cancelando...');
        _cancelExpiredOrder();
      } else {
        _expirationTimer = Timer(remaining, () {
          print('[TrackOrderBloc] Corrida atingiu limite de 20 minutos. Cancelando...');
          _cancelExpiredOrder();
        });
      }
    }
  }

  void _cancelExpiredOrder() {
    _expirationTimer?.cancel();
    _expirationTimer = null;
    final orderId = state.maybeMap(
      orderInProgres: (inProgress) => inProgress.order.id,
      orElse: () => null,
    );
    if (orderId != null) {
      cancelRide(cancelReasonId: null, cancelReasonNote: null);
    }
  }

  TrackOrderBloc(this.repository)
      : super(
          const TrackOrderState.initial(),
        ) {
    initConnectivityListener();

    on<_OnStarted>(
      (event, emit) async {
        // Detectar mudança de corrida ou mudança de status para limpar a stream cacheada em singleton
        final previousOrderId = state.maybeMap(
          orderInProgres: (val) => val.order.id,
          orElse: () => null,
        );
        final previousStatus = state.maybeMap(
          orderInProgres: (val) => val.order.status,
          orElse: () => null,
        );
        if (previousOrderId != event.order.id || previousStatus != event.order.status) {
          orderUpdates = null;
        }

        final initialState = TrackOrderState.orderInProgres(
          order: event.order,
          driverLocation: event.driverLocation,
          page: const TrackOrderPage.overview(),
        );
        emit(initialState);
        OngoingRideNotificationHelper.updateNotification(event.order);
        _manageExpirationTimer(event.order);

        if (orderUpdates == null) {
          // Stream reativa de conectividade que gerencia a reconexão automática baseada no estado real de rede
          final connectionStream = locator<ConnectivityCubit>()
              .stream
              .map((cState) => cState.isConnected)
              .startWith(locator<ConnectivityCubit>().state.isConnected)
              .distinct();

          orderUpdates = connectionStream.switchMap((isOnline) {
            if (isOnline) {
              return repository.listenToOrderUpdates(
                  orderEntity: event.order);
            } else {
              return Stream<(OrderEntity, DriverLocation?)>.empty();
            }
          });

          await emit.forEach(
            orderUpdates!,
            onData: (order) {
              OngoingRideNotificationHelper.updateNotification(order.$1);
              _manageExpirationTimer(order.$1);

              final isFindingDriver = order.$1.status == OrderStatus.requested;
              final isExpired = DateTime.now().difference(order.$1.createdAt).inMinutes >= 20;
              if (isFindingDriver && isExpired) {
                print('[TrackOrderBloc] Corrida de busca de motorista passou de 20 minutos. Cancelando...');
                repository.cancelOrder(
                  orderId: order.$1.id,
                  cancelReasonId: null,
                  cancelReasonNote: null,
                );
                orderUpdates = null;
                OngoingRideNotificationHelper.cancelNotification();
                return const TrackOrderState.done();
              }

              if (order.$1.status.viewMode == OrderStatusViewMode.finished) {
                orderUpdates = null;
                OngoingRideNotificationHelper.cancelNotification();
                return const TrackOrderState.done();
              }
              return state.maybeMap(
                orElse: () => throw Exception('Invalid state'),
                orderInProgres: (value) => value.copyWith.call(
                  order: order.$1,
                  driverLocation: order.$2,
                ),
              );
            },
          );
        }
      },
      transformer: (events, mapper) => events.switchMap(mapper),
    );

    on<TrackOrderEvent>((event, emit) async {
      if (event is _OnStarted) return;
      await event.map(
        onStarted: (_) {},
        cancelRide: (cancelRide) async {
          _expirationTimer?.cancel();
          _expirationTimer = null;
          final result = await repository.cancelOrder(
            orderId: state.maybeMap(
              orderInProgres: (inProgress) => inProgress.order.id,
              orElse: () => throw Exception("Invalid state"),
            ),
            cancelReasonId: cancelRide.cancelReasonId,
            cancelReasonNote: cancelRide.cancelReasonNote,
          );
          result.fold(
            (l) {
              emit(
                state.maybeMap(
                  orderInProgres: (inProgress) {
                    return inProgress.copyWith(
                      error: l.errorMessage,
                    );
                  },
                  orElse: () => throw Exception("Invalid state"),
                ),
              );
            },
            (r) {
              orderUpdates = null;
              OngoingRideNotificationHelper.cancelNotification();
              emit(const TrackOrderState.done());
            },
          );
        },
        changePage: (value) async {
          emit(
            state.maybeMap(
              orderInProgres: (inprogress) => inprogress.copyWith.call(
                page: value.page,
              ),
              orElse: () => throw Exception("Invalid state"),
            ),
          );
        },
        hideChat: (value) async {
          await state.maybeMap(
            orderInProgres: (inProgress) async {
              final result = await repository.updateLastSeenMessages(
                orderId: inProgress.order.id,
              );
              result.fold(
                (l) async => throw Exception(l.errorMessage),
                (r) async => emit(
                  state.maybeMap(
                    orderInProgres: (inProgress) {
                      return inProgress.copyWith(
                        page: const TrackOrderPage.overview(),
                        order: inProgress.order.copyWith(
                          lastSeenMessagesAt: DateTime.now(),
                        ),
                      );
                    },
                    orElse: () => throw Exception("Invalid state"),
                  ),
                ),
              );
            },
            orElse: () => throw Exception("Invalid state"),
          );
        },
        messageSent: (value) async {
          emit(
            state.maybeMap(
              orderInProgres: (inProgress) {
                return inProgress.copyWith(
                  order: inProgress.order.copyWith(
                    chatMessages: [
                      ...inProgress.order.chatMessages,
                      value.message
                    ],
                  ),
                );
              },
              orElse: () => throw Exception("Invalid state"),
            ),
          );
        },
      );
    });

  }

  onStarted({
    required OrderEntity order,
    required DriverLocation? driverLocation,
  }) =>
      add(
        TrackOrderEvent.onStarted(
          order: order,
          driverLocation: driverLocation,
        ),
      );

  cancelRide({
    required String? cancelReasonId,
    required String? cancelReasonNote,
  }) =>
      add(
        TrackOrderEvent.cancelRide(
            cancelReasonId: cancelReasonId, cancelReasonNote: cancelReasonNote),
      );

  void showChat() => add(
        const TrackOrderEvent.changePage(TrackOrderPage.chat()),
      );

  void hideChat() => add(
        const TrackOrderEvent.hideChat(),
      );

  void showPayment() => add(
        const TrackOrderEvent.changePage(TrackOrderPage.payment()),
      );

  void showOverview() => add(
        const TrackOrderEvent.changePage(TrackOrderPage.overview()),
      );

  @disposeMethod
  void dispose() {
    _expirationTimer?.cancel();
    _connectivitySubscription?.cancel();
    OngoingRideNotificationHelper.cancelNotification();
    close();
  }

  // @override
  // TrackOrderState? fromJson(Map<String, dynamic> json) {
  //   return TrackOrderState.fromJson(json);
  // }

  // @override
  // Map<String, dynamic>? toJson(TrackOrderState state) {
  //   return state.toJson();
  // }
}
