import 'package:dartz/dartz.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:uppi_motorista/features/payout_methods/domain/entitites/payout_account.input.dart';
import 'package:uppi_motorista/features/payout_methods/domain/entitites/payout_method.dart';

import '../entitites/payout_account.dart';

abstract class PayoutMethodsRepository {
  Future<Either<Failure, List<PayoutAccountEntity>>> getPayoutAccounts();
  Stream<Either<Failure, List<PayoutAccountEntity>>> startPayoutAccountsSubscription();

  Future<Either<Failure, List<PayoutMethodEntity>>> getAvailablePayoutMethods();

  Stream<Either<Failure, List<PayoutMethodEntity>>> startAvailablePayoutMethodsSubscription();

  Future<Either<Failure, PayoutAccountEntity>> updateDefaultPayoutMethodStatus({
    required String payoutMethodId,
    required bool isDefault,
  });

  Future<Either<Failure, void>> deletePayoutMethod(String id);

  Future<Either<Failure, PayoutAccountEntity>> addPayoutMethod(
    PayoutAccountInput input,
  );

  Future<Either<Failure, String>> getLinkUrlForPayoutMethod(
    PayoutMethodEntity method,
  );
}
