import 'dart:async';
import 'package:collection/collection.dart';
import 'package:uppi_motorista/features/payout_methods/domain/repositories/payout_methods_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../domain/entitites/payout_account.dart';
import 'package:uppi_motorista/core/error/failure.dart';

part 'payout_accounts.state.dart';
part 'payout_accounts.freezed.dart';

@lazySingleton
class PayoutAccountsBloc extends Cubit<PayoutAccountsState> {
  final PayoutMethodsRepository _repository;
  StreamSubscription? _subscription;

  PayoutAccountsBloc(this._repository)
    : super(const PayoutAccountsState.initial());

  void load() {
    emit(const PayoutAccountsState.loading());
    _subscription?.cancel();
    _subscription = _repository.startPayoutAccountsSubscription().listen((result) {
      result.fold(
        (failure) => emit(PayoutAccountsState.error(failure.errorMessage)),
        (methods) {
          if (methods.isEmpty) {
            emit(const PayoutAccountsState.empty());
          } else {
            emit(PayoutAccountsState.loaded(linkedMethods: methods));
          }
        },
      );
    });
  }

  void updatePayoutMethodDefaultStatus({
    required String payoutMethodId,
    required bool isDefault,
  }) async {
    final result = await _repository.updateDefaultPayoutMethodStatus(
      payoutMethodId: payoutMethodId,
      isDefault: isDefault,
    );
    result.fold(
      (failure) => emit(PayoutAccountsState.error(failure.errorMessage)),
      // Se tiver sucesso, o stream (listen) automaticamente fará o update da tela!
      (account) {}, 
    );
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
