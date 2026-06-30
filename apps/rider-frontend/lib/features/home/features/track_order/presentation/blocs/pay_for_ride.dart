import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/entities/payment_method_union.dart';
import 'package:flutter_common/core/enums/payment_mode.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/error/failure.dart';
import 'package:rider_flutter/core/repositories/wallet_repository.dart';
import 'package:rider_flutter/features/home/features/track_order/domain/repositories/track_order_repository.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

part 'pay_for_ride.state.dart';
part 'pay_for_ride.freezed.dart';

@lazySingleton
class PayForRideCubit extends Cubit<PayForRideState> {
  final TrackOrderRepository _repository;
  final WalletRepository _walletRepository;
  StreamSubscription? _subscription;

  PayForRideCubit(this._repository, this._walletRepository)
      : super(const PayForRideInitial());

  void load({
    required PaymentMethodUnion? selectedPaymentMethod,
    required bool cashEnabled,
    required bool walletCreditSufficient,
  }) {
    _subscription?.cancel();
    _subscription =
        _repository.startPaymentMethodsSubscription().listen((result) {
      result.fold(
        (failure) => emit(PayForRideState.error(failure: failure)),
        (paymentMethods) => emit(
          PayForRideState.loaded(
            selectedPaymentMethod: selectedPaymentMethod ??
                (walletCreditSufficient
                    ? const PaymentMethodUnion.wallet()
                    : const PaymentMethodUnion.cash()),
            paymentMethods: [
              if (walletCreditSufficient) const PaymentMethodUnion.wallet(),
              ...paymentMethods,
              if (cashEnabled) const PaymentMethodUnion.cash(),
            ],
          ),
        ),
      );
    });
  }

  void changePaymentMethod({
    required PaymentMethodUnion selectedPaymentMethod,
  }) {
    emit(
      state.maybeMap(
        orElse: () => throw Exception('Invalid State'),
        loaded: (value) => value.copyWith(
          selectedPaymentMethod: selectedPaymentMethod,
        ),
      ),
    );
  }

  void pay({
    required String orderId,
    required String currency,
    required double amount,
  }) async {
    final loadedState = state.maybeMap(
      orElse: () => throw Exception('Invalid State'),
      loaded: (value) => value,
    );
    final paymentMode = loadedState.selectedPaymentMethod.paymentMode;
    if (paymentMode == PaymentMode.cash) {
      emit(
        loadedState.copyWith(
          paymentStatus: const PayForRidePaymentStatus.success(),
        ),
      );
      return;
    }
    
    if (paymentMode == PaymentMode.wallet) {
      // Chama a Edge Function para finalizar a corrida com pagamento online (Carteira)
      try {
        emit(loadedState.copyWith(paymentStatus: const PayForRidePaymentStatus.loading()));
        final response = await Supabase.instance.client.functions.invoke(
          'finish-order',
          body: {
            'orderId': orderId,
            'cashAmount': 0, // Online/Wallet usa 0 cash
          },
        );
        
        if (response.status == 200) {
          emit(loadedState.copyWith(paymentStatus: const PayForRidePaymentStatus.success()));
        } else {
          emit(loadedState.copyWith(paymentStatus: PayForRidePaymentStatus.error(failure: Failure(message: "Erro na função: \${response.data}"))));
        }
      } catch (e) {
         emit(loadedState.copyWith(paymentStatus: PayForRidePaymentStatus.error(failure: Failure(message: e.toString()))));
      }
      return;
    }
    final topUpWallet = await _walletRepository.topUpWallet(
      paymentMode: paymentMode,
      paymentGatewayId: loadedState.selectedPaymentMethod.id ?? "0",
      currency: currency,
      amount: amount,
    );
    topUpWallet.fold(
      (l) => emit(
        loadedState.copyWith(
          paymentStatus: PayForRidePaymentStatus.error(
            failure: l,
          ),
        ),
      ),
      (r) {
        PayForRidePaymentStatus status = r.map(
          redirect: (value) => PayForRidePaymentStatus.redirect(
            url: value.url,
          ),
          success: (_) => const PayForRidePaymentStatus.success(),
          failure: (failure) => PayForRidePaymentStatus.error(
            failure: Failure(message: failure.errorMessage),
          ),
        );
        emit(
          loadedState.copyWith(
            paymentStatus: status,
          ),
        );
      },
    );
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
