import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:flutter_common/core/entities/payment_gateway.dart';
import 'package:flutter_common/core/entities/saved_payment_method.dart';
import 'package:flutter_common/core/enums/card_type.dart';
import 'package:flutter_common/core/enums/gateway_link_method.dart';
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/error/failure.dart';

import '../../domain/repositories/payment_methods_repository.dart';

@prod
@LazySingleton(as: PaymentMethodsRepository)
class PaymentMethodsRepositoryImpl implements PaymentMethodsRepository {
  final FirebaseDatasource firebaseDatasource;

  PaymentMethodsRepositoryImpl(this.firebaseDatasource);

  CardType _parseCardType(String? type) {
    switch (type?.toLowerCase()) {
      case 'visa':
        return CardType.visa;
      case 'mastercard':
        return CardType.mastercard;
      case 'amex':
        return CardType.amex;
      case 'discover':
        return CardType.discover;
      default:
        return CardType.unknown;
    }
  }

  @override
  Future<
          Either<Failure,
              (List<SavedPaymentMethodEntity>, List<PaymentGatewayEntity>)>>
      getSavedPaymentMethods() async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) {
        return Left(Failure.serverError('User not authenticated'));
      }

      // Buscar métodos de pagamento do Supabase
      final methodsResult = await firebaseDatasource.supabaseClient
          .from('payment_methods')
          .select()
          .eq('user_id', uid);

      final methods = (methodsResult as List).map((data) {
        return SavedPaymentMethodEntity(
          id: data['id']?.toString() ?? '',
          cardType: _parseCardType(data['card_type'] as String?),
          last4Digits: data['last_four'] as String? ?? '0000',
          cardHolderName: data['title'] as String?,
          expiryDate: data['expiry_date'] != null
              ? DateTime.tryParse(data['expiry_date'] as String)
              : null,
          isDefault: data['is_default'] as bool? ?? false,
          isEnabled: data['is_enabled'] as bool? ?? true,
        );
      }).toList();

      // Buscar gateways de pagamento ativos
      final gatewaysResult = await firebaseDatasource.supabaseClient
          .from('payment_gateways')
          .select()
          .eq('is_active', true);

      final gateways = (gatewaysResult as List).map((data) {
        final linkMethodStr =
            data['external_url'] != null ? 'redirect' : 'redirect';
        final linkMethod = GatewayLinkMethod.values.firstWhere(
          (e) => e.name == linkMethodStr,
          orElse: () => GatewayLinkMethod.redirect,
        );
        return PaymentGatewayEntity(
          id: data['id']?.toString() ?? '',
          name:
              data['name'] as String? ?? data['title'] as String? ?? 'Gateway',
          logoUrl: data['logo_url'] as String?,
          linkMethod: linkMethod,
        );
      }).toList();

      return Right((methods, gateways));
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  @override
  Stream<
          Either<Failure,
              (List<SavedPaymentMethodEntity>, List<PaymentGatewayEntity>)>>
      startSavedPaymentMethodsSubscription() async* {
    yield await getSavedPaymentMethods();
  }

  @override
  Future<Either<Failure, String>> getExternalUrl({
    required String paymentGatewayId,
    double? amount,
  }) async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) {
        return Left(Failure.serverError('User not authenticated'));
      }

      final response = await firebaseDatasource.supabaseClient.functions.invoke(
        'create-payment-preference',
        body: {'amount': amount ?? 50.00},
      );

      if (response.status == 200) {
        final data = response.data;
        if (data is Map) {
          final url = data['url'] as String?;
          if (url != null && url.isNotEmpty) {
            return Right(url);
          }
        }
        return Left(
            Failure.serverError('Mercado Pago não retornou URL válida'));
      }

      return Left(Failure.serverError(
          'Cloud Function error (MP): HTTP ${response.status}'));
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<SavedPaymentMethodEntity>>> markAsDefault({
    required SavedPaymentMethodEntity paymentMethod,
    required bool isDefault,
  }) async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) {
        return Left(Failure.serverError('User not authenticated'));
      }

      if (isDefault) {
        await firebaseDatasource.supabaseClient.functions.invoke(
          'user-actions',
          body: {
            'action': 'set_default_payment',
            'table': 'payment_methods',
            'id': paymentMethod.id,
          },
        );
      }

      // Re-buscar a lista atualizada
      final updatedResult = await firebaseDatasource.supabaseClient
          .from('payment_methods')
          .select()
          .eq('user_id', uid);

      final updatedMethods = (updatedResult as List).map((data) {
        return SavedPaymentMethodEntity(
          id: data['id']?.toString() ?? '',
          cardType: _parseCardType(data['card_type'] as String?),
          last4Digits: data['last_four'] as String? ?? '0000',
          cardHolderName: data['title'] as String?,
          expiryDate: data['expiry_date'] != null
              ? DateTime.tryParse(data['expiry_date'] as String)
              : null,
          isDefault: data['is_default'] as bool? ?? false,
          isEnabled: data['is_enabled'] as bool? ?? true,
        );
      }).toList();

      return Right<Failure, List<SavedPaymentMethodEntity>>(updatedMethods);
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }
}
