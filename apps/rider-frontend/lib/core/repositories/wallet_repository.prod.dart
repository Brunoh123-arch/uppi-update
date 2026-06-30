import 'package:dartz/dartz.dart';
import 'package:flutter_common/core/enums/intent_result.dart';
import 'package:flutter_common/core/enums/payment_mode.dart';
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/error/failure.dart';

import 'wallet_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@prod
@LazySingleton(as: WalletRepository)
class WalletRepositoryImpl implements WalletRepository {
  final FirebaseDatasource firebaseDatasource;
  final SupabaseClient supabaseClient;

  WalletRepositoryImpl(this.firebaseDatasource)
      : supabaseClient = Supabase.instance.client;

  @override
  Future<Either<Failure, IntentResult>> topUpWallet({
    required PaymentMode paymentMode,
    required String paymentGatewayId,
    required String currency,
    required double amount,
  }) async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) return Left(Failure.serverError('Not authenticated'));

      // Recarregar saldo via Edge Function (evita manipulação de saldo no cliente)
      final response = await supabaseClient.functions.invoke(
        'admin-recharge-wallet',
        body: {
          'userId': uid,
          'amount': amount,
          'gatewayId': paymentGatewayId,
          'description': 'Recarga via ${paymentMode.toString()}',
        },
      );

      if (response.status != 200) {
        return Left(Failure.serverError('Falha ao processar recarga'));
      }

      return const Right(IntentResult.success());
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }
}
