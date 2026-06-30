import 'package:dartz/dartz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uppi_motorista/core/datasources/firebase_datasource.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:injectable/injectable.dart';

import '../../domain/repositories/redeem_gift_card_repository.dart';

@prod
@LazySingleton(as: RedeemGiftCardRepository)
class RedeemGiftCardRepositoryImpl implements RedeemGiftCardRepository {
  final FirebaseDatasource firebaseDatasource;

  RedeemGiftCardRepositoryImpl(this.firebaseDatasource);

  @override
  Future<Either<Failure, (double, String)>> redeemGiftCard({
    required String code,
  }) async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) throw Exception('User not authenticated');

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
        throw Exception('Erro ao resgatar o vale-presente');
      }
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }
}
