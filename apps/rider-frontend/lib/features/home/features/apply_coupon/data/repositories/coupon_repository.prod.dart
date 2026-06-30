import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/error/failure.dart';
import 'package:rider_flutter/features/home/features/apply_coupon/domain/repositories/coupon_repository.dart';

@prod
@LazySingleton(as: CouponRepository)
class CouponRepositoryImpl implements CouponRepository {
  final FirebaseDatasource firebaseDatasource;

  CouponRepositoryImpl(this.firebaseDatasource);

  @override
  Future<Either<Failure, bool>> checkCouponValidity(String code) async {
    try {
      final result = await firebaseDatasource.supabaseClient
          .from('coupons')
          .select('id')
          .eq('code', code)
          .eq('is_active', true)
          .limit(1)
          .maybeSingle();
      return Right(result != null);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }
}
