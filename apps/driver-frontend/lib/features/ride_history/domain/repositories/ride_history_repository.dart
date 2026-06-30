import 'package:dartz/dartz.dart';
import 'package:uppi_motorista/core/entities/order.dart';
import 'package:uppi_motorista/core/error/failure.dart';

abstract class RideHistoryRepository {
  Future<Either<Failure, List<OrderEntity>>> getRideHistory();

  Stream<Either<Failure, List<OrderEntity>>> startRideHistorySubscription();

  Future<Either<Failure, bool>> reportIssue({
    required String orderId,
    required String subject,
    required String issue,
  });
}
