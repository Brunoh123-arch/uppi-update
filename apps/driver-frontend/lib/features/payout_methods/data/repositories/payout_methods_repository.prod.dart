import 'package:dartz/dartz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uppi_motorista/core/datasources/firebase_datasource.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:uppi_motorista/features/payout_methods/domain/entitites/payout_account.dart';
import 'package:uppi_motorista/features/payout_methods/domain/entitites/payout_account.input.dart';
import 'package:uppi_motorista/features/payout_methods/domain/entitites/payout_method.dart';
import 'package:flutter_common/core/enums/gateway_link_method.dart';
import 'package:injectable/injectable.dart';

import '../../domain/repositories/payout_methods_repository.dart';

@prod
@LazySingleton(as: PayoutMethodsRepository)
class PayoutMethodsRepositoryImpl implements PayoutMethodsRepository {
  final FirebaseDatasource firebaseDatasource;

  PayoutMethodsRepositoryImpl(this.firebaseDatasource);

  SupabaseClient get _supabase => Supabase.instance.client;

  PayoutAccountEntity _mapToEntity(Map<String, dynamic> row) {
    return PayoutAccountEntity(
      id: row['id']?.toString() ?? '',
      accountNumber: row['account_number']?.toString(),
      routingNumber: row['routing_number']?.toString(),
      accountHolderName: row['account_holder_name']?.toString(),
      bankName: row['bank_name']?.toString(),
      isDefault: row['is_default'] == true,
      accountHolderCountry: row['account_holder_country']?.toString(),
      accountHolderCity: row['account_holder_city']?.toString(),
      accountHolderState: row['account_holder_state']?.toString(),
      accountHolderAddress: row['account_holder_address']?.toString(),
      accountHolderDateOfBirth: null,
      accountHolderPhone: row['account_holder_phone']?.toString(),
      accountHolderZip: row['account_holder_zip']?.toString(),
    );
  }

  @override
  Stream<Either<Failure, List<PayoutAccountEntity>>> startPayoutAccountsSubscription() async* {
    yield await getPayoutAccounts();
  }

  @override
  Future<Either<Failure, List<PayoutAccountEntity>>> getPayoutAccounts() async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) {
        return const Left(Failure.server(message: 'Driver not authenticated'));
      }

      final data = await _supabase
          .from('payout_accounts')
          .select()
          .eq('driver_id', uid)
          .order('created_at', ascending: false);

      final accounts = (data as List)
          .map((row) => _mapToEntity(row as Map<String, dynamic>))
          .toList();
      return Right(accounts);
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deletePayoutMethod(String id) async {
    try {
      await firebaseDatasource.supabaseClient.functions.invoke(
        'user-actions',
        body: {
          'action': 'delete',
          'table': 'payout_accounts',
          'id': id,
        },
      );
      return const Right(null);
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, PayoutAccountEntity>> updateDefaultPayoutMethodStatus({
    required String payoutMethodId,
    required bool isDefault,
  }) async {
    try {
      final result = await firebaseDatasource.supabaseClient.functions.invoke(
        'user-actions',
        body: {
          'action': 'set_default_payout',
          'table': 'payout_accounts',
          'id': payoutMethodId,
        },
      );

      final updated = result.data['data'];
      return Right(_mapToEntity(updated as Map<String, dynamic>));
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<PayoutMethodEntity>>>
  getAvailablePayoutMethods() async {
    try {
      final data = await _supabase
          .from('payout_methods')
          .select()
          .eq('is_active', true);

      final methods = (data as List).map((row) => _mapMethod(row)).toList();

      return Right(methods);
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }

  /// Sem external_url configurada o cadastro é manual (formulário no app).
  PayoutMethodEntity _mapMethod(Map<String, dynamic> row) {
    final externalUrl = row['external_url']?.toString();
    return PayoutMethodEntity(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? 'Gateway',
      linkMethod: (externalUrl == null || externalUrl.isEmpty)
          ? GatewayLinkMethod.manual
          : GatewayLinkMethod.redirect,
      media: null,
    );
  }

  @override
  Stream<Either<Failure, List<PayoutMethodEntity>>>
  startAvailablePayoutMethodsSubscription() async* {
    yield await getAvailablePayoutMethods();
  }

  @override
  Future<Either<Failure, PayoutAccountEntity>> addPayoutMethod(
    PayoutAccountInput input,
  ) async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) {
        return const Left(Failure.server(message: 'Driver not authenticated'));
      }

      final result = await firebaseDatasource.supabaseClient.functions.invoke(
        'user-actions',
        body: {
          'action': 'insert',
          'table': 'payout_accounts',
          'data': {
            'driver_id': uid,
            'payout_method_id': input.payoutMethodId,
            'account_number': input.accountNumber,
            'routing_number': input.routingNumber,
            'account_holder_name': input.accountHolderName,
            'bank_name': input.bankName,
            'is_default': false,
          },
        },
      );

      final inserted = result.data['data'];
      return Right(_mapToEntity(inserted as Map<String, dynamic>));
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, String>> getLinkUrlForPayoutMethod(
    PayoutMethodEntity method,
  ) async {
    try {
      final data = await _supabase
          .from('payout_methods')
          .select('external_url')
          .eq('id', method.id)
          .maybeSingle();

      if (data == null) {
        return const Left(
          Failure.server(message: 'Método de saque não encontrado'),
        );
      }

      final url = data['external_url']?.toString();
      if (url == null || url.isEmpty) {
        return const Left(
          Failure.server(
            message: 'URL de cadastro não configurada pelo administrador',
          ),
        );
      }

      return Right(url);
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }
}
