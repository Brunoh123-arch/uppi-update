import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:uppi_motorista/features/ride_history/domain/repositories/ride_history_repository.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:uppi_motorista/core/entities/order.dart';

part 'ride_history.state.dart';
part 'ride_history.freezed.dart';

@lazySingleton
class RideHistoryBloc extends Cubit<RideHistoryState> {
  final RideHistoryRepository _repository;
  StreamSubscription? _subscription;

  RideHistoryBloc(this._repository) : super(const RideHistoryState.initial());

  void load() {
    final isAlreadyLoaded = state.maybeMap(
      loaded: (_) => true,
      empty: (_) => true,
      orElse: () => false,
    );
    if (!isAlreadyLoaded) {
      emit(const RideHistoryState.loading());
    }
    _subscription?.cancel();
    _subscription = _repository.startRideHistorySubscription().listen((result) {
      result.fold(
        (failure) => emit(RideHistoryState.error(failure.errorMessage)),
        (orders) => orders.isEmpty
            ? emit(const RideHistoryState.empty())
            : emit(RideHistoryState.loaded(orders)),
      );
    });
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
