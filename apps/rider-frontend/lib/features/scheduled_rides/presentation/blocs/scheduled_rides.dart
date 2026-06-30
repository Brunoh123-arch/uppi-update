import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/entities/order_compact.dart';
import 'package:rider_flutter/features/scheduled_rides/domain/repositories/scheduled_rides_repository.dart';

part 'scheduled_rides.state.dart';
part 'scheduled_rides.freezed.dart';

@lazySingleton
class ScheduledRidesBloc extends Cubit<ScheduledRidesState> {
  final ScheduledRidesRepository repository;
  StreamSubscription? _subscription;

  ScheduledRidesBloc(this.repository) : super(const ScheduledRidesState.initial());

  void load() {
    emit(const ScheduledRidesState.loading());
    _subscription?.cancel();
    _subscription = repository.startUpcomingRidesSubscription().listen((result) {
      result.fold(
        (failure) => emit(ScheduledRidesState.error(failure.errorMessage)),
        (orders) => orders.isEmpty
            ? emit(const ScheduledRidesState.empty())
            : emit(ScheduledRidesState.loaded(orders)),
      );
    });
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
