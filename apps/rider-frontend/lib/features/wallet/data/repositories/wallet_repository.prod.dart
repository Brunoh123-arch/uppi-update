import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/error/failure.dart';
import 'package:flutter_common/core/entities/wallet_transaction.dart';
import 'package:flutter_common/core/entities/wallet_query_response.dart';
import 'package:flutter_common/core/entities/payment_gateway.dart';
import 'package:flutter_common/core/entities/saved_payment_method.dart';
import 'package:flutter_common/core/enums/card_type.dart';
import 'package:flutter_common/core/enums/gateway_link_method.dart';

import '../../domain/repositories/wallet_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@prod
@LazySingleton(as: WalletRepository)
class WalletRepositoryImpl implements WalletRepository {
  final FirebaseDatasource firebaseDatasource;
  final SupabaseClient supabaseClient;

  WalletRepositoryImpl(
    this.firebaseDatasource, {
    SupabaseClient? supabaseClient,
  }) : supabaseClient = supabaseClient ?? Supabase.instance.client;

  @override
  Stream<Either<Failure, WalletQueryResponse>> startWalletSubscription() async* {
    yield await getWalletData();
  }

  @override
  Future<Either<Failure, WalletQueryResponse>> getWalletData() async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) {
        return Left(Failure.serverError('User not authenticated'));
      }

      final profileData = await supabaseClient
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();

      // Buscar transações reais
      final transactionsResult = await supabaseClient
          .from('wallet_transactions')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(50);

      final transactions = transactionsResult.map((tData) {
        final amount = (tData['amount'] as num?)?.toDouble() ?? 0.0;
        final type = (tData['transaction_type'] ?? tData['type'] ?? tData['ref_type']) as String?;

        return WalletTransactionEntity(
          id: tData['id'].toString(),
          amount: amount,
          currency: 'BRL',
          dateTime: tData['created_at'] != null
              ? DateTime.parse(tData['created_at'].toString()).toLocal()
              : DateTime.now(),
          rechargeTransactionType:
              amount >= 0 ? _parseRechargeType(type) : null,
          deductTransactionType: amount < 0 ? _parseDeductType(type) : null,
          description: tData['description']?.toString(),
        );
      }).toList();

      final fullName = (profileData?['full_name'] as String?) ?? '';
      final parts = fullName.split(' ');
      final firstName = parts.isNotEmpty ? parts.first : '';
      final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

      // Buscar saldo da wallet na tabela dedicada
      final walletData = await supabaseClient
          .from('wallets')
          .select('balance, pending_balance')
          .eq('user_id', uid)
          .maybeSingle();
      final balance = (walletData?['balance'] as num?)?.toDouble() ?? 0.0;
      final pendingBalance = (walletData?['pending_balance'] as num?)?.toDouble() ?? 0.0;

      // Buscar a moeda oficial configurada no Admin
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
      } catch (_) {}

      // Buscar gateways de pagamento
      final gatewaysData = await supabaseClient
          .from('payment_gateways')
          .select()
          .eq('is_active', true);
          
      final paymentGateways = gatewaysData.map((data) {
        final linkMethodStr = data['link_method']?.toString() ?? 'redirect';
        final linkMethod = GatewayLinkMethod.values.firstWhere(
          (e) => e.name == linkMethodStr,
          orElse: () => GatewayLinkMethod.redirect,
        );
        return PaymentGatewayEntity(
          id: data['id'].toString(),
          name: data['title']?.toString() ?? data['name']?.toString() ?? 'Gateway',
          logoUrl: data['logo_url']?.toString() ?? '',
          linkMethod: linkMethod,
        );
      }).toList();

      // Buscar métodos de pagamento salvos
      final savedMethodsData = await supabaseClient
          .from('payment_methods')
          .select()
          .eq('user_id', uid)
          .eq('is_enabled', true);
          
      final savedPaymentMethods = savedMethodsData.map((data) {
        return SavedPaymentMethodEntity(
          id: data['id'].toString(),
          cardType: CardType.unknown, // Default until parsing is needed
          last4Digits: data['last_four']?.toString() ?? '0000',
          isEnabled: data['is_enabled'] as bool? ?? true,
          isDefault: data['is_default'] as bool? ?? false,
          cardHolderName: data['card_holder_name']?.toString() ?? '',
          expiryDate: data['expiry_date'] != null ? DateTime.tryParse(data['expiry_date'].toString()) : null,
        );
      }).toList();

      return Right(WalletQueryResponse(
        firstName: firstName,
        lastName: lastName,
        currency: appCurrency,
        balance: balance,
        pendingBalance: pendingBalance,
        transactions: transactions,
        paymentGateways: paymentGateways,
        savedPaymentMethods: savedPaymentMethods,
      ));
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  WalletRechargeTransactionType _parseRechargeType(String? type) {
    if (type == 'gift_card' || type == 'cashback') return WalletRechargeTransactionType.gift;
    if (type == 'topup' ||
        type == 'recharge' ||
        type == 'admin_adjustment' ||
        type == 'deposit') {
      return WalletRechargeTransactionType.inAppPayment;
    }
    return WalletRechargeTransactionType.correction;
  }

  WalletDeductTransactionType _parseDeductType(String? type) {
    if (type == 'withdraw' || type == 'payout') {
      return WalletDeductTransactionType.withdraw;
    }
    if (type == 'cancellation_fee') {
      return WalletDeductTransactionType.cancellationFee;
    }
    if (type == 'ride_payment' ||
        type == 'ride_fare' ||
        type == 'commission_fee' ||
        type == 'commission') {
      return WalletDeductTransactionType.orderFee;
    }
    return WalletDeductTransactionType.correction;
  }
}
