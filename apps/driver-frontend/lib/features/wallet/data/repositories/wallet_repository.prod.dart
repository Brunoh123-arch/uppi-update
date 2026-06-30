import 'dart:async';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dartz/dartz.dart';
import 'package:uppi_motorista/core/datasources/firebase_datasource.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:flutter_common/core/entities/wallet_transaction.dart';
import 'package:flutter_common/core/entities/wallet_query_response.dart';
import 'package:flutter_common/core/enums/intent_result.dart';
import 'package:flutter_common/core/enums/payment_mode.dart';
import 'package:flutter_common/core/enums/gateway_link_method.dart';
import 'package:flutter_common/core/entities/payment_gateway.dart';
import 'package:injectable/injectable.dart';

import '../../domain/repositories/wallet_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@prod
@LazySingleton(as: WalletRepository)
class WalletRepositoryImpl implements WalletRepository {
  final FirebaseDatasource firebaseDatasource;
  final SupabaseClient supabaseClient;

  WalletRepositoryImpl(this.firebaseDatasource)
    : supabaseClient = Supabase.instance.client;

  @override
  Stream<Either<Failure, WalletQueryResponse>> startWalletSubscription() async* {
    yield await getWalletData();
  }

  @override
  Future<Either<Failure, WalletQueryResponse>> getWalletData() async {
    try {
      final uid = supabaseClient.auth.currentUser?.id;
      if (uid == null) throw Exception("User not authenticated");

      final profileData = await supabaseClient
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();

      final fullName = (profileData?['full_name'] as String?) ?? '';
      final parts = fullName.split(' ');
      final firstName = parts.isNotEmpty ? parts.first : '';
      final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      
      final walletData = await supabaseClient
          .from('wallets')
          .select('balance, pending_balance')
          .eq('user_id', uid)
          .maybeSingle();

      final rawBalance =
          (walletData?['balance'] as num?)?.toDouble() ?? 0.0;
      final balance = rawBalance < 0 ? 0.0 : rawBalance;
      final rawPendingBalance =
          (walletData?['pending_balance'] as num?)?.toDouble() ?? 0.0;
      final pendingBalance = rawPendingBalance < 0 ? 0.0 : rawPendingBalance;

      final paymentGatewaysResult = await supabaseClient
          .from('payment_gateways')
          .select()
          .eq('is_active', true);
      final gateways = (paymentGatewaysResult as List)
          .map(
            (e) => PaymentGatewayEntity(
              id: e['id']?.toString() ?? '',
              logoUrl: e['logo_url'] as String? ?? '',
              name: e['title'] as String? ?? '',
              linkMethod: GatewayLinkMethod.redirect,
            ),
          )
          .toList();

      final transactionsResult = await supabaseClient
          .from('wallet_transactions')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(50);

      final transactions = transactionsResult.map((d) {
        final action = (d['transaction_type'] ?? d['type'] ?? d['ref_type'])?.toString();
        final amount = (d['amount'] as num?)?.toDouble() ?? 0.0;
        return WalletTransactionEntity(
          id: d['id'].toString(),
          amount: amount,
          currency: 'BRL',
          dateTime: d['created_at'] != null
              ? DateTime.parse(d['created_at'].toString()).toLocal()
              : DateTime.now(),
          rechargeTransactionType: (action == 'topup' || action == 'recharge' || action == 'admin_adjustment')
              ? WalletRechargeTransactionType.inAppPayment
              : (action == 'ride_fare' && amount >= 0)
                  ? WalletRechargeTransactionType.orderFee
                  : (action == 'tip_incentive' || action == 'bounty' || action == 'gift')
                      ? WalletRechargeTransactionType.gift
                      : (amount >= 0)
                          ? WalletRechargeTransactionType.unknown
                          : null,
          deductTransactionType:
              (action == 'commission_fee' || action == 'commission' || (action == 'ride_fare' && amount < 0))
                  ? WalletDeductTransactionType.commisson
                  : (action == 'payout' || action == 'withdraw')
                      ? WalletDeductTransactionType.withdraw
                      : (amount < 0)
                          ? WalletDeductTransactionType.unknown
                          : null,
          description: d['description']?.toString(),
        );
      }).toList();

      String appCurrency = 'BRL'; // Fallback
      try {
        final configRow = await supabaseClient
            .from('app_settings')
            .select('value')
            .eq('key', 'currency')
            .maybeSingle();
        if (configRow != null && configRow['value'] != null) {
          appCurrency = configRow['value'].toString();
        }
      } catch (e, st) {
        Sentry.captureException(e, stackTrace: st);
      }

      return Right(
        WalletQueryResponse(
          firstName: firstName,
          lastName: lastName,
          currency: appCurrency,
          balance: balance,
          pendingBalance: pendingBalance,
          transactions: transactions,
          paymentGateways: gateways,
          savedPaymentMethods: [],
        ),
      );
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, IntentResult>> topUpWallet({
    required PaymentMode paymentMode,
    required String paymentGatewayId,
    required String currency,
    required double amount,
  }) async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) throw Exception("User not authenticated");

      final idToken = supabaseClient.auth.currentSession?.accessToken;

      if (idToken == null) throw Exception("Could not get auth token");

      final cloudFunctionUrl =
          '${dotenv.env['SUPABASE_URL']}/functions/v1/create-payment-preference';

      final response = await http.post(
        Uri.parse(cloudFunctionUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'amount': amount}),
      );

      final responseBody = response.body;

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(responseBody);
        if (data.containsKey('url')) {
          return Right(IntentResult.redirect(url: data['url']));
        }
      }

      return const Left(
        Failure.server(message: "Failed to initiate Mercado Pago checkout"),
      );
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> requestPayout({
    required double amount,
    required String payoutAccountId,
  }) async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) throw Exception("User not authenticated");

      await supabaseClient.functions.invoke('user-actions', body: {
        'action': 'insert',
        'table': 'payout_requests',
        'data': {
          'payout_account_id': payoutAccountId,
          'amount': amount,
        }
      });

      return const Right(null);
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }
}
