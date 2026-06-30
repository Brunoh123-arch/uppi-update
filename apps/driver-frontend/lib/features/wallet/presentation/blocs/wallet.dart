import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_common/core/entities/wallet_query_response.dart';
import '../../domain/repositories/wallet_repository.dart';
import 'package:uppi_motorista/core/error/failure.dart';

part 'wallet.state.dart';
part 'wallet.freezed.dart';

@lazySingleton
class WalletBloc extends Cubit<WalletState> {
  final WalletRepository walletRepository;
  StreamSubscription? _subscription;

  WalletBloc(this.walletRepository) : super(const WalletState.initial());

  void load() {
    final isAlreadyLoaded = state.maybeMap(
      loaded: (_) => true,
      orElse: () => false,
    );
    if (!isAlreadyLoaded) {
      emit(const WalletState.loading());
    }
    _subscription?.cancel();
    _subscription = walletRepository.startWalletSubscription().listen((result) {
      result.fold(
        (failure) => emit(WalletState.error(failure.errorMessage)),
        (data) => emit(WalletState.loaded(data)),
      );
    });
  }

  Future<Either<Failure, void>> requestPayout({
    required double amount,
    required String payoutAccountId,
  }) async {
    final result = await walletRepository.requestPayout(
      amount: amount,
      payoutAccountId: payoutAccountId,
    );
    result.fold(
      (failure) {},
      (_) => load(),
    );
    return result;
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
