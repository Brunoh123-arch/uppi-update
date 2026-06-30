import 'package:dartz/dartz.dart';
import 'package:uppi_motorista/core/error/failure.dart';

abstract class RedeemGiftCardRepository {
  Future<Either<Failure, (double, String)>> redeemGiftCard({
    required String code,
  });
}
