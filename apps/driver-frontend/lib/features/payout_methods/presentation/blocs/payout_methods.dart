import 'dart:async';
import 'package:uppi_motorista/features/payout_methods/domain/entitites/payout_method.dart';
import 'package:uppi_motorista/features/payout_methods/domain/repositories/payout_methods_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:uppi_motorista/core/error/failure.dart';

part 'payout_methods.state.dart';
part 'payout_methods.freezed.dart';

@LazySingleton()
class PayoutMethodsBloc extends Cubit<PayoutMethodsState> {
  final PayoutMethodsRepository _repository;
  StreamSubscription? _subscription;

  PayoutMethodsBloc(this._repository)
    : super(const PayoutMethodsState.initial()) {
    load();
  }

  void load() {
    final isAlreadyLoaded = state.maybeMap(
      loaded: (_) => true,
      empty: (_) => true,
      orElse: () => false,
    );
    if (!isAlreadyLoaded) {
      emit(const PayoutMethodsState.loading());
    }
    _subscription?.cancel();
    _subscription =
        _repository.startAvailablePayoutMethodsSubscription().listen((result) {
      result.fold(
        (failure) => emit(PayoutMethodsState.error(failure.errorMessage)),
        (methods) {
          if (methods.isEmpty) {
            emit(const PayoutMethodsState.empty());
          } else {
            emit(PayoutMethodsState.loaded(methods));
          }
        },
      );
    });
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
