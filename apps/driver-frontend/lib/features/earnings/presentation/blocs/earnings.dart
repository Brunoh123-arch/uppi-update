import 'dart:async';
import 'package:uppi_motorista/features/earnings/domain/entities/earnings_dataset.dart';
import 'package:uppi_motorista/features/earnings/domain/enums/earnings_timeframe.dart';
import 'package:uppi_motorista/features/earnings/domain/repositories/earnings_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

part 'earnings.state.dart';
part 'earnings.freezed.dart';

@lazySingleton
class EarningsBloc extends Cubit<EarningsState> {
  final EarningsRepository _repository;
  StreamSubscription? _subscription;

  EarningsBloc(this._repository) : super(EarningsState.initial());

  void load() {
    final isAlreadyLoaded = state.pageState.maybeMap(
      loaded: (_) => true,
      empty: (_) => true,
      orElse: () => false,
    );
    if (!isAlreadyLoaded) {
      emit(state.copyWith(pageState: const EarningsPageState.loading()));
    }

    _subscription?.cancel();
    _subscription = _repository
        .startEarningsSubscription(
      timeFrame: state.timeframe,
      startDate: state.startDate,
      endDate: state.endDate,
    )
        .listen((result) {
      result.fold(
        (failure) => emit(
          state.copyWith(
            pageState: EarningsPageState.error(errorMessage: failure.toString()),
          ),
        ),
        (dataset) => emit(
          state.copyWith(
            pageState: dataset.datapoints.isEmpty
                ? const EarningsPageState.empty()
                : EarningsPageState.loaded(dataset: dataset),
          ),
        ),
      );
    });
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }

  void setTimeFrame(EarningsTimeFrame timeFrame) {
    final range = _rangeFor(timeFrame, DateTime.now());
    emit(
      state.copyWith(
        timeframe: timeFrame,
        startDate: range.start,
        endDate: range.end,
      ),
    );
    load();
  }

  void previousTimeframe() {
    final anchor = state.timeframe == EarningsTimeFrame.monthly
        ? DateTime(state.startDate.year, state.startDate.month - 1, 1)
        : state.timeframe == EarningsTimeFrame.weekly
            ? state.startDate.subtract(const Duration(days: 7))
            : state.startDate.subtract(const Duration(days: 1));
    final range = _rangeFor(state.timeframe, anchor);
    emit(state.copyWith(startDate: range.start, endDate: range.end));
    load();
  }

  void nextTimeframe() {
    final anchor = state.timeframe == EarningsTimeFrame.monthly
        ? DateTime(state.startDate.year, state.startDate.month + 1, 1)
        : state.timeframe == EarningsTimeFrame.weekly
            ? state.startDate.add(const Duration(days: 7))
            : state.startDate.add(const Duration(days: 1));
    final range = _rangeFor(state.timeframe, anchor);
    emit(state.copyWith(startDate: range.start, endDate: range.end));
    load();
  }

  /// Calcula o intervalo [start, end] (sempre start <= end) para o filtro
  /// escolhido, ancorado numa data. Diário = o dia inteiro do `anchor`;
  /// Semanal = Segunda a Domingo da semana do `anchor`;
  /// Mensal = do 1º ao último instante do mês do `anchor`.
  ({DateTime start, DateTime end}) _rangeFor(
    EarningsTimeFrame timeFrame,
    DateTime anchor,
  ) {
    if (timeFrame == EarningsTimeFrame.monthly) {
      final start = DateTime(anchor.year, anchor.month, 1);
      // 1º dia do mês seguinte − 1ms = último instante do mês atual.
      final end = DateTime(anchor.year, anchor.month + 1, 1)
          .subtract(const Duration(milliseconds: 1));
      return (start: start, end: end);
    }
    if (timeFrame == EarningsTimeFrame.weekly) {
      final daysToSubtract = anchor.weekday - 1;
      final start = DateTime(anchor.year, anchor.month, anchor.day).subtract(Duration(days: daysToSubtract));
      final end = DateTime(start.year, start.month, start.day, 23, 59, 59, 999).add(const Duration(days: 6));
      return (start: start, end: end);
    }
    // Diário (e qualquer outro): o dia inteiro do anchor.
    final start = DateTime(anchor.year, anchor.month, anchor.day);
    final end = DateTime(anchor.year, anchor.month, anchor.day, 23, 59, 59, 999);
    return (start: start, end: end);
  }
}
