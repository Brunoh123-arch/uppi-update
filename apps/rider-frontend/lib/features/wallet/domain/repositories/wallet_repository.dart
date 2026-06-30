import 'package:dartz/dartz.dart';
import 'package:rider_flutter/core/error/failure.dart';

import 'package:flutter_common/core/entities/wallet_query_response.dart';

abstract class WalletRepository {
  Future<Either<Failure, WalletQueryResponse>> getWalletData();

  Stream<Either<Failure, WalletQueryResponse>> startWalletSubscription();
}
