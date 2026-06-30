import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:collection/collection.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/entities/order.dart';
import 'package:uppi_motorista/core/entities/order_request.dart';
import 'package:uppi_motorista/core/entities/profile.dart';
import 'package:uppi_motorista/core/enums/driver_status.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:uppi_motorista/core/repositories/firebase_repository.dart';
import 'package:uppi_motorista/core/router/app_router.dart';
import 'package:uppi_motorista/features/home/domain/repositories/home_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:flutter_common/features/chat/chat.dart';
import 'package:generic_map/generic_map.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:flutter_common/core/entities/driver_location.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_common/core/blocs/connectivity_cubit.dart';

part 'home.event.dart';
part 'home.state.dart';
part 'home.freezed.dart';
part 'home.g.dart';

@lazySingleton
class HomeBloc extends HydratedBloc<HomeEvent, HomeState> {
  final HomeRepository _repository;
  final FirebaseRepository _firebaseRepository;
  Stream<List<OrderRequestEntity>>? orderRequests;
  Stream<OrderEntity>? order;

  StreamSubscription<ProfileEntity>? profileSubscription;
  final List<ChatMessageEntity> pendingMessages = [];
  StreamSubscription? _connectivitySubscription;
  StreamSubscription<OrderEntity>? _orderSubscription;
  OrderStatus? lastFinishedOrderStatus;

  void initConnectivityListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = locator<ConnectivityCubit>().stream.listen((connState) {
      if (connState.isConnected) {
        retryPendingMessages();
      }
    });
  }

  Future<void> sendChatMessage(String messageText) async {
    final isConnected = locator<ConnectivityCubit>().state.isConnected;
    final order = state.driverStatus.maybeMap(
      onTrip: (inProgress) => inProgress.order,
      orElse: () => null,
    );
    if (order == null) return;

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

    final res = await _repository.sendMessage(orderId: order.id, message: messageText);
    res.fold(
      (l) {
        pendingMessages.add(tempMsg);
        _forceRebuild();
      },
      (r) {
        add(HomeEvent.messageSent(message: r));
      },
    );
  }

  Future<void> retryMessage(ChatMessageEntity msg) async {
    final isConnected = locator<ConnectivityCubit>().state.isConnected;
    if (!isConnected) return;

    final order = state.driverStatus.maybeMap(
      onTrip: (inProgress) => inProgress.order,
      orElse: () => null,
    );
    if (order == null) return;

    final res = await _repository.sendMessage(orderId: order.id, message: msg.message);
    res.fold(
      (l) {},
      (r) {
        pendingMessages.removeWhere((m) => m.id == msg.id);
        add(HomeEvent.messageSent(message: r));
      },
    );
  }

  Future<void> retryPendingMessages() async {
    if (pendingMessages.isEmpty) return;
    final isConnected = locator<ConnectivityCubit>().state.isConnected;
    if (!isConnected) return;

    final order = state.driverStatus.maybeMap(
      onTrip: (inProgress) => inProgress.order,
      orElse: () => null,
    );
    if (order == null) return;

    final messagesToRetry = List<ChatMessageEntity>.from(pendingMessages);
    for (final msg in messagesToRetry) {
      final res = await _repository.sendMessage(orderId: order.id, message: msg.message);
      res.fold(
        (l) {},
        (r) {
          pendingMessages.removeWhere((m) => m.id == msg.id);
          add(HomeEvent.messageSent(message: r));
        },
      );
    }
    _forceRebuild();
  }

  void _forceRebuild() {
    emit(state.copyWith());
  }

  HomeBloc(this._repository, this._firebaseRepository)
    : super(const HomeState()) {
    initConnectivityListener();
    on<HomeEvent>((event, emit) async {
      switch (event) {
        case _OnStarted(:final location):
          profileSubscription?.cancel();
          profileSubscription = _repository.startProfileSubscription().listen((profile) {
            if (profile != ProfileEntity.emptyProfile) {
              final currentStatus = state.driverStatus;
              bool shouldRefresh = false;

              if (currentStatus is AccessDeniedDriverStatus && profile.status == const DriverStatus.offline()) {
                shouldRefresh = true;
              } else if (currentStatus is! AccessDeniedDriverStatus && profile.status == const DriverStatus.blocked()) {
                shouldRefresh = true;
              }

              if (shouldRefresh) {
                add(HomeEvent.onStarted(location: state.driverLocation));
              }
            }
          });
          
          final profile = await _repository.getProfile();
          _firebaseRepository.retrieveAndUpdateFcmToken();
          final homeState = await mapProfileToHomeState(profile: profile);
          emit(homeState.copyWith(driverLocation: location));
          await homeState.driverStatus.mapOrNull(
            online: (value) async {
              await _startOrderRequestsSubscription(emit);
            },
            onTrip: (value) async {
              _startOrderUpdateSubscription(value.order);
            },
          );

          break;

        case _OnStatusChanged(:final status):
          emit(state.copyWith(error: null));
          final profile = await _repository.updateStatus(status: status);
          final homeState = await mapProfileToHomeState(profile: profile);
          emit(homeState);
          await homeState.driverStatus.mapOrNull(
            online: (value) async {
              await _startOrderRequestsSubscription(emit);
            },
            offline: (value) async {
              orderRequests = null;
              _repository.stopGettingOrderRequestUpdates();
            },
          );
          break;

        case _OnLocationUpdated(:final location, :final lastLocationUpdate):
          // Atualiza o marcador (chevron) IMEDIATAMENTE a partir do GPS local.
          // Antes, o marcador só se movia se a chamada ao servidor desse certo —
          // então qualquer falha/lentidão de rede congelava o chevron (parecia
          // travado/hardcoded). Agora o marcador acompanha o GPS mesmo offline.
          emit(
            state.copyWith(
              driverLocation: location,
              lastLocationUpdate: lastLocationUpdate,
            ),
          );
          // Envia a localização ao servidor em segundo plano; uma falha aqui
          // não afeta mais o movimento do marcador no mapa.
          unawaited(_repository.updateDriverLocation(location: location));
          break;

        case _OnAcceptOrder(:final request):
          final order = await _repository.acceptOrderRequest(
            requestId: request.id,
          );
          await order.fold(
            (l) async {
              emit(
                state.copyWith(
                  error: l,
                  driverStatus: state.driverStatus.maybeMap(
                    orElse: () => state.driverStatus,
                    online: (online) => online.copyWith(
                      orderRequests: online.orderRequests
                          .where((r) => r.id != request.id)
                          .toList(),
                    ),
                  ),
                ),
              );
            },
            (r) async {
              orderRequests = null;
              _repository.stopGettingOrderRequestUpdates();
              emit(
                state.copyWith(
                  driverStatus: HomeStateDriverStatus.onTrip(order: r),
                ),
              );
              _startOrderUpdateSubscription(r);
            },
          );
          break;

        case _OnRejectOrder(:final request):
          final result = await _repository.rejectOrderRequest(
            requestId: request.id,
          );
          result.fold(
            (l) => null,
            (r) {
              emit(
                state.copyWith(
                  driverStatus: state.driverStatus.maybeMap(
                    orElse: () => state.driverStatus,
                    online: (online) {
                      final updatedList = online.orderRequests
                          .where((r) => r.id != request.id)
                          .toList();
                      final nextRequest = updatedList.isNotEmpty ? updatedList.first : null;
                      return online.copyWith(
                        orderRequests: updatedList,
                        currentOrderRequest: nextRequest,
                      );
                    },
                  ),
                ),
              );
            },
          );
          break;

        case _OnCancelOrder(:final orderId, :final reasonId, :final reasonNote):
          final order = await _repository.cancelOrder(
            orderId: orderId,
            reasonId: reasonId,
            reasonNote: reasonNote,
          );
          final newState = _orderToHomeState(order);
          emit(newState);

          break;

        case _OnArrivedToPickupPoint(:final orderId):
          final order = await _repository.arrivedToPickup(orderId: orderId);
          final newState = _orderToHomeState(order);
          emit(newState);

          break;

        case _OnTripStarted(:final orderId, :final boardingPin):
          final order = await _repository.startTrip(orderId: orderId, boardingPin: boardingPin);
          final newState = _orderToHomeState(order);
          emit(newState);

          break;

        case _OnArrivedToDestination(:final order, :final destinationArrivedTo):
          final newOrder = await _repository.arrivedToDestination(
            order: order,
            destinationArrivedTo: destinationArrivedTo,
          );
          final newState = _orderToHomeState(newOrder);
          emit(newState);
          break;

        case _OnShowChat():
          emit(
            state.copyWith(
              driverStatus: state.driverStatus.maybeMap(
                orElse: () => throw Exception('Invalid state'),
                onTrip: (onTrip) =>
                    onTrip.copyWith(page: const OnTripPage.chat()),
              ),
            ),
          );
          break;

        case _ReviewSubmitted(:final rating, :final review, :final orderId):
          if (rating == null) {
            onStarted();
          } else {
            await _repository.submitReview(
              orderId: orderId,
              rating: rating,
              review: review,
            );
            onStarted();
          }
          break;

        case _PaidInCash(:final orderId, :final amount, :final tollAmount, :final actualDistance):
          await _repository.paidInCash(
            orderId: orderId,
            amount: amount,
            tollAmount: tollAmount,
            actualDistance: actualDistance,
          );
          emit(
            state.copyWith(
              driverStatus: state.driverStatus.maybeMap(
                orElse: () => const HomeStateDriverStatus.initial(),
                onTrip: (onTrip) =>
                    onTrip.copyWith(page: const OnTripPage.rate()),
              ),
            ),
          );
          break;

        case _OnSummaryConfirmed():
          emit(
            state.copyWith(
              driverStatus: state.driverStatus.maybeMap(
                orElse: () => throw Exception('Invalid state'),
                onTrip: (onTrip) =>
                    onTrip.copyWith(page: const OnTripPage.rate()),
              ),
            ),
          );
          break;

        case _OnOrderRequestPageChanged(:final request):
          emit(
            state.copyWith(
              driverStatus: state.driverStatus.maybeMap(
                orElse: () => throw Exception('Invalid state'),
                online: (online) =>
                    online.copyWith(currentOrderRequest: request),
              ),
            ),
          );
          break;

        case _MessageSent(:final message):
          emit(
            state.copyWith(
              driverStatus: state.driverStatus.maybeMap(
                onTrip: (inProgress) {
                  return inProgress.copyWith(
                    order: inProgress.order.copyWith(
                      chatMessages: [...inProgress.order.chatMessages, message],
                    ),
                  );
                },
                orElse: () => state.driverStatus,
              ),
            ),
          );
        case _OnOrderUpdated(:final order):
          final newState = _orderToHomeState(Right(order));
          emit(newState);
          break;
        case _OnHideChat():
          await state.driverStatus.maybeMap(
            onTrip: (inProgress) async {
              final result = await _repository.updateLastSeenMessagesAt(
                orderId: inProgress.order.id,
              );
              result.fold(
                (l) async => emit(state.copyWith(error: l)),
                (r) async => emit(
                  state.copyWith(
                    driverStatus: state.driverStatus.maybeMap(
                      onTrip: (inProgress) => inProgress.copyWith(
                        page: inProgress.order.status.viewMode ==
                                OrderStatusViewMode.waitingForPayment
                            ? const OnTripPage.payment()
                            : const OnTripPage.overview(),
                        order: inProgress.order.copyWith(
                          lastSeenMessagesAt: DateTime.now(),
                        ),
                      ),
                      orElse: () => state.driverStatus,
                    ),
                  ),
                ),
              );
            },
            orElse: () async {},
          );
          break;
      }
    });
  }

  void onStarted({DriverLocation? driverLocation}) =>
      add(HomeEvent.onStarted(location: driverLocation));

  void onStatusChanged(DriverStatus status) =>
      add(HomeEvent.onStatusChanged(status: status));

  void onLocationUpdated({
    required DriverLocation location,
    bool? forceUpdate,
  }) => add(
    HomeEvent.onLocationUpdated(
      location: location,
      lastLocationUpdate: forceUpdate == true ? DateTime.now() : null,
    ),
  );

  void onAcceptOrder(OrderRequestEntity request) =>
      add(HomeEvent.onAcceptOrder(request: request));

  // void onRadiusChanged(int radius) => add(HomeEvent.onRadiusChanged(radius: radius));

  HomeState _orderToHomeState(Either<Failure, OrderEntity> order) {
    return order.fold(
      (l) => state.copyWith(
        driverStatus: state.driverStatus.maybeMap(
          orElse: () => throw Exception('Invalid state'),
          onTrip: (onTrip) => onTrip.copyWith(error: l),
        ),
      ),
      (r) {
        if (r.status.viewMode == OrderStatusViewMode.finished) {
          lastFinishedOrderStatus = r.status;
        } else {
          lastFinishedOrderStatus = null;
        }
        switch (r.status.viewMode) {
          case (OrderStatusViewMode.waitingForPayment):
            return state.copyWith(
              error: null,
              driverStatus: HomeStateDriverStatus.onTrip(
                order: r,
                page: const OnTripPage.payment(),
              ),
            );

          case (OrderStatusViewMode.review):
            return state.copyWith(
              error: null,
              driverStatus: HomeStateDriverStatus.onTrip(
                order: r,
                page: const OnTripPage.rate(),
              ),
            );

          case (OrderStatusViewMode.finished):
            _stopOrderUpdateSubscription();
            return state.copyWith(
              error: null,
              driverStatus: const HomeStateDriverStatus.online(orderRequests: []),
            );

          case (OrderStatusViewMode.inProgress):
            return state.copyWith(
              error: null,
              driverStatus: HomeStateDriverStatus.onTrip(
                order: r,
                page: state.driverStatus.maybeMap(
                  orElse: () => const OnTripPage.overview(),
                  onTrip: (onTrip) => onTrip.page,
                ),
              ),
            );

          case OrderStatusViewMode.looking:
            _stopOrderUpdateSubscription();
            return state.copyWith(
              error: null,
              driverStatus: const HomeStateDriverStatus.online(orderRequests: []),
            );
        }
      },
    );
  }

  Future<HomeState> mapProfileToHomeState({
    required Either<Failure, ProfileEntity> profile,
  }) async {
    return profile.fold(
      (l) async {
        // Fallback para offline quando getProfile falha,
        // para que o botão Online/Offline sempre apareça.
        final fallbackStatus = state.driverStatus.maybeMap(
          orElse: () => const HomeStateDriverStatus.offline(),
          online: (v) => v,
          offline: (v) => v,
          onTrip: (v) => v,
        );
        return state.copyWith(error: l, driverStatus: fallbackStatus);
      },
      (r) async {
        if (r.orders.isNotEmpty) {
          final newState = _orderToHomeState(Right(r.orders.first));
          _startOrderUpdateSubscription(r.orders.first);
          return newState;
        }
        return r.status.map(
          pendingSubmission: (pendingSubmission) async {
            locator<AppRouter>().replaceAll([const DriverAuthRoute()]);
            return state.copyWith(
              driverStatus: const HomeStateDriverStatus.accessDenied(),
            );
          },
          pendingApproval: (pendingApproval) async => state.copyWith(
            driverStatus: const HomeStateDriverStatus.accessDenied(),
          ),
          online: (online) async {
            _stopOrderUpdateSubscription();
            return state.copyWith(
              driverStatus: HomeStateDriverStatus.online(
                orderRequests: state.driverStatus.maybeMap(
                  orElse: () => [],
                  online: (online) => online.orderRequests,
                ),
              ),
            );
          },
          offline: (offline) async {
            orderRequests = null;
            _repository.stopGettingOrderRequestUpdates();
            _stopOrderUpdateSubscription();
            return state.copyWith(
              driverStatus: const HomeStateDriverStatus.offline(),
            );
          },
          onTrip: (onTrip) async {
            if (r.orders.isEmpty) {
              return state.copyWith(
                driverStatus: const HomeStateDriverStatus.online(orderRequests: []),
              );
            }
            final newState = _orderToHomeState(Right(r.orders.first));
            return newState;
          },
          blocked: (blocked) async => state.copyWith(
            driverStatus: const HomeStateDriverStatus.accessDenied(),
          ),
          softReject: (softReject) async => state.copyWith(
            driverStatus: const HomeStateDriverStatus.accessDenied(),
          ),
          hardReject: (hardReject) async => state.copyWith(
            driverStatus: const HomeStateDriverStatus.accessDenied(),
          ),
        );
      },
    );
  }

  void _startOrderUpdateSubscription(OrderEntity orderEntity) {
    _orderSubscription?.cancel();
    _orderSubscription = _repository
        .startOrderUpdatedSubscription(orderEntity: orderEntity)
        .listen((data) {
      add(HomeEvent.onOrderUpdated(order: data));
    });
  }

  void _stopOrderUpdateSubscription() {
    _orderSubscription?.cancel();
    _orderSubscription = null;
  }

  Future<void> _startOrderRequestsSubscription(Emitter emit) async {
    if (orderRequests == null) {
      orderRequests = _repository.startGettingOrderRequestUpdates();
      return await emit.forEach(
        orderRequests!,
        onData: (data) {
          return state.copyWith(
            driverStatus: state.driverStatus.maybeMap(
              orElse: () => throw Exception('Invalid state'),
              online: (online) {
                final current = online.currentOrderRequest;
                final next = current == null
                    ? (data.isNotEmpty ? data.first : null)
                    : (data.firstWhereOrNull((r) => r.id == current.id) ??
                        (data.isNotEmpty ? data.first : null));
                return online.copyWith(
                  orderRequests: data,
                  currentOrderRequest: next,
                );
              },
            ),
          );
        },
      );
    }
  }

  @override
  Future<void> close() {
    _connectivitySubscription?.cancel();
    profileSubscription?.cancel();
    _orderSubscription?.cancel();
    return super.close();
  }

  @override
  HomeState? fromJson(Map<String, dynamic> json) => HomeState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(HomeState state) {
    try {
      final json = state.toJson();

      // UPPI BRASIL AUTO-LIMPEZA OCULTA:
      // Removemos dados de tempo real altamente voláteis e pesados (GPS/pedidos)
      // para evitar que o HydratedBloc bombardeie o SQLite com escritas pesadas e síncronas.
      // Isso elimina 100% o lag e engasgos (stuttering) causados por I/O na thread do UI.
      json['driverLocation'] = null;
      json['lastLocationUpdate'] = null;
      json['error'] = null;

      final statusMap = json['driverStatus'] as Map<String, dynamic>?;
      if (statusMap != null) {
        statusMap['orderRequests'] = [];
        statusMap['currentOrderRequest'] = null;
        statusMap['driverLocation'] = null;
        statusMap['error'] = null;
      }
      return json;
    } catch (_) {
      return state.toJson();
    }
  }
}
