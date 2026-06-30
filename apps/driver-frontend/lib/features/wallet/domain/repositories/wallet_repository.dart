import 'package:dartz/dartz.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:flutter_common/core/enums/intent_result.dart';
import 'package:flutter_common/core/enums/payment_mode.dart';

import 'package:flutter_common/core/entities/wallet_query_response.dart';

abstract class WalletRepository {
  Future<Either<Failure, WalletQueryResponse>> getWalletData();

  Stream<Either<Failure, WalletQueryResponse>> startWalletSubscription();

  Future<Either<Failure, IntentResult>> topUpWallet({
    required PaymentMode paymentMode,
    required String paymentGatewayId,
    required String currency,
    required double amount,
  });

  Future<Either<Failure, void>> requestPayout({
    required double amount,
    required String payoutAccountId,
  });
}
