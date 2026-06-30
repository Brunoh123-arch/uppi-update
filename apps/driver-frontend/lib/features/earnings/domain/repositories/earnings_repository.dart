import 'package:dartz/dartz.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:uppi_motorista/features/earnings/domain/entities/earnings_dataset.dart';
import 'package:uppi_motorista/features/earnings/domain/enums/earnings_timeframe.dart';

abstract class EarningsRepository {
  Future<Either<Failure, EarningsDataset>> getEarningsDataset({
    required EarningsTimeFrame timeFrame,
    required DateTime startDate,
    required DateTime endDate,
  });

  Stream<Either<Failure, EarningsDataset>> startEarningsSubscription({
    required EarningsTimeFrame timeFrame,
    required DateTime startDate,
    required DateTime endDate,
  });

}
