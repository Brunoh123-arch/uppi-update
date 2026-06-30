import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/error/failure.dart';
import 'package:rider_flutter/features/wallet/data/repositories/wallet_repository.prod.dart';

class MockFirebaseDatasource extends Mock implements FirebaseDatasource {}
class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

class FakePostgrestFilterBuilder<T> extends Fake
    implements PostgrestFilterBuilder<T>, PostgrestTransformBuilder<T> {
  final dynamic value;
  FakePostgrestFilterBuilder(this.value);

  @override
  PostgrestFilterBuilder<T> eq(String column, Object value) => this;

  @override
  PostgrestFilterBuilder<T> inFilter(String column, List values) => this;

  @override
  PostgrestFilterBuilder<T> order(String column, {bool ascending = true, bool nullsFirst = false, String? referencedTable}) => this;

  @override
  PostgrestFilterBuilder<T> limit(int count, {String? referencedTable}) => this;

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() {
    return FakePostgrestFilterBuilder<Map<String, dynamic>?>(value as Map<String, dynamic>?);
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) {
    return Future.value(onValue(value as T));
  }
}

void main() {
  late MockFirebaseDatasource mockFirebaseDatasource;
  late MockSupabaseClient mockSupabaseClient;
  
  late MockSupabaseQueryBuilder mockProfilesQB;
  late MockSupabaseQueryBuilder mockTransactionsQB;
  late MockSupabaseQueryBuilder mockWalletsQB;
  late MockSupabaseQueryBuilder mockAppSettingsQB;
  late MockSupabaseQueryBuilder mockGatewaysQB;
  late MockSupabaseQueryBuilder mockMethodsQB;

  late WalletRepositoryImpl repository;

  setUp(() {
    mockFirebaseDatasource = MockFirebaseDatasource();
    mockSupabaseClient = MockSupabaseClient();
    
    mockProfilesQB = MockSupabaseQueryBuilder();
    mockTransactionsQB = MockSupabaseQueryBuilder();
    mockWalletsQB = MockSupabaseQueryBuilder();
    mockAppSettingsQB = MockSupabaseQueryBuilder();
    mockGatewaysQB = MockSupabaseQueryBuilder();
    mockMethodsQB = MockSupabaseQueryBuilder();

    repository = WalletRepositoryImpl(
      mockFirebaseDatasource,
      supabaseClient: mockSupabaseClient,
    );

    registerFallbackValue(const Offset(0, 0));
  });

  const tUid = 'test-uid';

  final tProfileData = {
    'id': tUid,
    'full_name': 'João Silva',
  };

  final tTransactionsResult = [
    {
      'id': 'tx-1',
      'amount': 50.0,
      'created_at': '2026-06-17T10:00:00.000Z',
      'transaction_type': 'topup',
    },
    {
      'id': 'tx-2',
      'amount': -20.0,
      'created_at': '2026-06-17T10:30:00.000Z',
      'transaction_type': 'ride_fare',
    }
  ];

  final tWalletData = {
    'balance': 150.0,
    'pending_balance': 10.0,
  };

  final tAppSettingsData = {
    'value': 'BRL',
  };

  final tGatewaysResult = [
    {
      'id': 'gw-1',
      'title': 'Stripe',
      'logo_url': 'stripe.png',
      'link_method': 'redirect',
      'is_active': true,
    }
  ];

  final tMethodsResult = [
    {
      'id': 'pm-1',
      'last_four': '4321',
      'is_enabled': true,
      'is_default': true,
      'card_holder_name': 'João S',
      'expiry_date': '2030-05-31',
    }
  ];

  void mockSuccessfulQueries() {
    when(() => mockFirebaseDatasource.uid).thenReturn(tUid);
    
    when(() => mockSupabaseClient.from('profiles')).thenAnswer((_) => mockProfilesQB);
    when(() => mockProfilesQB.select()).thenAnswer((_) => FakePostgrestFilterBuilder<List<Map<String, dynamic>>>(tProfileData));

    when(() => mockSupabaseClient.from('wallet_transactions')).thenAnswer((_) => mockTransactionsQB);
    when(() => mockTransactionsQB.select()).thenAnswer((_) => FakePostgrestFilterBuilder<List<Map<String, dynamic>>>(tTransactionsResult));

    when(() => mockSupabaseClient.from('wallets')).thenAnswer((_) => mockWalletsQB);
    when(() => mockWalletsQB.select(any())).thenAnswer((_) => FakePostgrestFilterBuilder<List<Map<String, dynamic>>>(tWalletData));

    when(() => mockSupabaseClient.from('app_settings')).thenAnswer((_) => mockAppSettingsQB);
    when(() => mockAppSettingsQB.select(any())).thenAnswer((_) => FakePostgrestFilterBuilder<List<Map<String, dynamic>>>(tAppSettingsData));

    when(() => mockSupabaseClient.from('payment_gateways')).thenAnswer((_) => mockGatewaysQB);
    when(() => mockGatewaysQB.select()).thenAnswer((_) => FakePostgrestFilterBuilder<List<Map<String, dynamic>>>(tGatewaysResult));

    when(() => mockSupabaseClient.from('payment_methods')).thenAnswer((_) => mockMethodsQB);
    when(() => mockMethodsQB.select()).thenAnswer((_) => FakePostgrestFilterBuilder<List<Map<String, dynamic>>>(tMethodsResult));
  }

  group('getWalletData', () {
    test('should return WalletQueryResponse mapped correctly on success', () async {
      // arrange
      mockSuccessfulQueries();

      // act
      final result = await repository.getWalletData();

      // assert
      expect(result.isRight(), isTrue);
      final response = result.getOrElse(() => throw Exception('Failed to get wallet data'));
      
      expect(response.firstName, 'João');
      expect(response.lastName, 'Silva');
      expect(response.balance, 150.0);
      expect(response.pendingBalance, 10.0);
      expect(response.currency, 'BRL');
      
      expect(response.transactions.length, 2);
      expect(response.transactions[0].id, 'tx-1');
      expect(response.transactions[0].amount, 50.0);
      expect(response.transactions[1].id, 'tx-2');
      expect(response.transactions[1].amount, -20.0);

      expect(response.paymentGateways.length, 1);
      expect(response.paymentGateways[0].id, 'gw-1');
      expect(response.paymentGateways[0].name, 'Stripe');

      expect(response.savedPaymentMethods.length, 1);
      expect(response.savedPaymentMethods[0].id, 'pm-1');
      expect(response.savedPaymentMethods[0].last4Digits, '4321');
    });

    test('should return Left(Failure.serverError) when not authenticated', () async {
      // arrange
      when(() => mockFirebaseDatasource.uid).thenReturn(null);

      // act
      final result = await repository.getWalletData();

      // assert
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<Failure>()),
        (_) => fail('Should have failed'),
      );
    });

    test('should return Left(Failure.serverError) when exception is thrown', () async {
      // arrange
      when(() => mockFirebaseDatasource.uid).thenReturn(tUid);
      when(() => mockSupabaseClient.from(any())).thenThrow(Exception('Database error'));

      // act
      final result = await repository.getWalletData();

      // assert
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<Failure>()),
        (_) => fail('Should have failed'),
      );
    });
  });

  group('startWalletSubscription', () {
    test('should yield wallet response once and close', () async {
      // arrange
      mockSuccessfulQueries();

      // act
      final stream = repository.startWalletSubscription();
      final emits = await stream.toList();

      // assert
      expect(emits.length, 1);
      expect(emits.first.isRight(), isTrue);
    });
  });
}
