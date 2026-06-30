import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_common/core/entities/wallet_query_response.dart';
import '../../domain/repositories/wallet_repository.dart';

part 'wallet.state.dart';
part 'wallet.freezed.dart';

@lazySingleton
class WalletBloc extends Cubit<WalletState> {
  final WalletRepository walletRepository;
  StreamSubscription? _subscription;

  WalletBloc(this.walletRepository) : super(const WalletState.initial());

  void load() {
    emit(const WalletState.loading());
    _subscription?.cancel();
    _subscription = walletRepository.startWalletSubscription().listen((result) {
      result.fold(
        (failure) => emit(
          WalletState.error(
            failure.errorMessage,
          ),
        ),
        (data) => emit(
          WalletState.loaded(
            data: data,
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
}
