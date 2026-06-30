import 'package:dartz/dartz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/error/failure.dart';

import '../../domain/repositories/redeem_gift_card_repository.dart';

@prod
@LazySingleton(as: RedeemGiftCardRepository)
class RedeemGiftCardRepositoryImpl implements RedeemGiftCardRepository {
  final FirebaseDatasource firebaseDatasource;

  RedeemGiftCardRepositoryImpl(this.firebaseDatasource);

  @override
  Future<Either<Failure, (double, String)>> redeemGiftCard(
      {required String code}) async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) {
        return Left(Failure.serverError('User not authenticated'));
      }

      final response = await Supabase.instance.client.functions.invoke(
        'redeem-gift-card',
        body: {'code': code},
      );

      final data = response.data;
      if (data['success'] == true) {
        final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
        final currency = data['currency']?.toString() ?? 'BRL';
        return Right((amount, currency));
      } else {
        return Left(Failure.serverError('Erro ao resgatar o vale-presente'));
      }
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }
}
