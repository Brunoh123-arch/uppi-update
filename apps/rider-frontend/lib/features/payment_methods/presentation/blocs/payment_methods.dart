import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:flutter_common/core/entities/payment_gateway.dart';
import 'package:flutter_common/core/entities/saved_payment_method.dart';

import '../../domain/repositories/payment_methods_repository.dart';

part 'payment_methods.state.dart';
part 'payment_methods.freezed.dart';

@lazySingleton
class PaymentMethodsBloc extends Cubit<PaymentMethodsState> {
  final PaymentMethodsRepository _repository;
  StreamSubscription? _subscription;

  PaymentMethodsBloc(this._repository)
      : super(const PaymentMethodsState.initial());

  void load() {
    emit(const PaymentMethodsState.loading());
    _subscription?.cancel();
    _subscription =
        _repository.startSavedPaymentMethodsSubscription().listen((result) {
      result.fold(
        (failure) => emit(PaymentMethodsState.error(failure.errorMessage)),
        (data) => emit(PaymentMethodsState.loaded(data)),
      );
    });
  }

  void markAsDefault({
    required SavedPaymentMethodEntity paymentMethod,
    required bool isDefault,
  }) async {
    final result = await _repository.markAsDefault(
        paymentMethod: paymentMethod, isDefault: isDefault);
    result.fold(
      (failure) => emit(PaymentMethodsState.error(failure.errorMessage)),
      // Stream listener will auto-update the UI with the new list
      (_) {},
    );
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
