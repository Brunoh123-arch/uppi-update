import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:flutter_common/core/theme/animation_duration.dart';
import 'package:flutter_common/core/entities/driver_location.dart';
import 'package:rider_flutter/core/blocs/location.dart';
import 'package:rider_flutter/core/entities/order.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:flutter_common/core/presentation/uppi_feedback.dart';
import 'package:rider_flutter/features/home/features/track_order/presentation/screens/chat_sheet.dart';
import 'package:rider_flutter/features/home/features/track_order/presentation/screens/pay_for_ride_sheet.dart';
import 'package:rider_flutter/features/home/presentation/blocs/home.dart';
import 'package:flutter_common/core/presentation/app_card_sheet.dart';
import 'package:flutter_common/core/presentation/common_skeletons.dart';

import '../blocs/track_order.dart';
import 'looking_for_driver_sheet.dart';
import 'order_in_progress_sheet.dart';

class TrackOrderSheet extends StatefulWidget {
  final OrderEntity order;
  final DriverLocation? driverLocation;

  const TrackOrderSheet({
    super.key,
    required this.order,

    required this.driverLocation,
  });

  @override
  State<TrackOrderSheet> createState() => _TrackOrderSheetState();
}

class _TrackOrderSheetState extends State<TrackOrderSheet> {
  OrderStatus? _lastStatus;
  static String? _lastNotifiedOrderId;
  static final Set<OrderStatus> _notifiedStatuses = {};

  @override
  void initState() {
    super.initState();
    _lastStatus = widget.order.status;
    locator<TrackOrderBloc>().onStarted(
      order: widget.order,
      driverLocation: widget.driverLocation,
    );
  }

  @override
  void didUpdateWidget(covariant TrackOrderSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.status != widget.order.status ||
        oldWidget.order.driver?.mobileNumber != widget.order.driver?.mobileNumber ||
        oldWidget.driverLocation != widget.driverLocation) {
      locator<TrackOrderBloc>().onStarted(
        order: widget.order,
        driverLocation: widget.driverLocation,
      );
    }
  }

  void _showStatusSnackBar(BuildContext context, OrderStatus? oldStatus, OrderEntity order) {
    if (_lastNotifiedOrderId != order.id) {
      _lastNotifiedOrderId = order.id;
      _notifiedStatuses.clear();
    }

    final newStatus = order.status;
    if (_notifiedStatuses.contains(newStatus)) {
      return;
    }
    _notifiedStatuses.add(newStatus);

    String? message;
    switch (newStatus) {
      case OrderStatus.driverAccepted:
        UppiFeedback.triggerLight(); // Acessibilidade: Alerta Háptico Leve
        // showDriverAcceptedToast(context, order);
        return; // Retorna para evitar a exibição de Snackbar padrão para aceitação
      case OrderStatus.arrived:
        UppiFeedback.triggerMedium(); // Acessibilidade: Alerta Háptico Médio
        message = "O motorista chegou ao local de embarque!";
        break;
      case OrderStatus.started:
        UppiFeedback.triggerSuccess(); // Acessibilidade: Alerta Háptico Forte
        message = "Corrida iniciada! Tenha uma excelente viagem.";
        break;
      case OrderStatus.finished:
      case OrderStatus.waitingForReview:
        message = "Corrida finalizada! Obrigado por viajar com a Uppi.";
        break;
      case OrderStatus.riderCanceled:
      case OrderStatus.driverCanceled:
        message = "A corrida foi cancelada.";
        break;
      default:
        break;
    }

    if (message != null) {
      context.showSnackBar(message: message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(
          value: locator<TrackOrderBloc>(),
        ),
      ],
      child: BlocConsumer<TrackOrderBloc, TrackOrderState>(
        listener: (context, state) {
          if (state.error != null) {
            context.showSnackBar(message: state.error!);
          }
          state.mapOrNull(
            orderInProgres: (inProgress) {
              final newStatus = inProgress.order.status;
              if (_lastStatus != newStatus) {
                _showStatusSnackBar(context, _lastStatus, inProgress.order);
                _lastStatus = newStatus;
              }
              switch (inProgress.order.status.viewMode) {
                case OrderStatusViewMode.looking:
                case OrderStatusViewMode.inProgress:
                case OrderStatusViewMode.waitingForPayment:
                  locator<HomeCubit>().showInProgress(
                    order: inProgress.order,
                    driverLocation: inProgress.driverLocation,
                  );
                  break;

                case OrderStatusViewMode.review:
                  locator.resetLazySingleton<TrackOrderBloc>();
                  locator<HomeCubit>().showRate(
                    order: inProgress.order,
                  );
                  break;
                default:
                  break;
              }
            },
            done: (value) {
              locator.resetLazySingleton<TrackOrderBloc>();
              locator<HomeCubit>().initializeWelcome(
                pickupPoint: locator<LocationCubit>().state.place,
              );
            },
          );
        },
        builder: (context, state) {
          return AnimatedSwitcher(
            duration: AnimationDuration.pageStateTransitionMobile,
            child: state.map(
              initial: (initial) => AppCardSheet(
                child: const TransitionCardSkeleton(),
              ),
              orderInProgres: (inProgress) =>
                  switch (inProgress.order.status.viewMode) {
                OrderStatusViewMode.looking => const LookingForDriverSheet(),
                OrderStatusViewMode.inProgress => AnimatedSwitcher(
                    duration: AnimationDuration.pageStateTransitionMobile,
                    child: inProgress.page.when(
                      overview: () => OrderInProgressSheet(
                        order: inProgress.order,
                      ),
                      chat: () => ChatSheet(
                        order: inProgress.order,
                      ),
                      payment: () => PayForRideSheet(
                        order: inProgress.order,
                      ),
                    ),
                  ),
                OrderStatusViewMode.waitingForPayment => PayForRideSheet(
                    order: inProgress.order,
                  ),
                OrderStatusViewMode.review => AppCardSheet(
                    child: const TransitionCardSkeleton(),
                  ),
                OrderStatusViewMode.finished => AppCardSheet(
                    child: const TransitionCardSkeleton(),
                  ),
              },
              done: (done) => AppCardSheet(
                child: const TransitionCardSkeleton(),
              ),
            ),
          );
        },
      ),
    );
  }
}
