import 'dart:async';
import 'package:uppi_motorista/features/home/domain/repositories/home_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/entities/cancel_reason.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:uppi_motorista/core/error/failure.dart';

part 'cancel_reason.state.dart';
part 'cancel_reason.freezed.dart';

@lazySingleton
class CancelReasonCubit extends Cubit<CancelReasonState> {
  final HomeRepository _repository;
  StreamSubscription? _subscription;

  CancelReasonCubit(this._repository)
    : super(const CancelReasonState.initial());

  void onStarted() {
    emit(const CancelReasonState.loading());
    _subscription?.cancel();
    _subscription = _repository.startCancelReasonsSubscription().listen((result) {
      result.fold(
        (failure) => emit(CancelReasonState.error(failure.errorMessage)),
        (data) => emit(CancelReasonState.loaded(data)),
      );
    });
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
