import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/error/failure.dart';
import 'package:flutter_common/core/enums/card_type.dart';
import 'package:rider_flutter/features/payment_methods/data/repositories/payment_methods_repository.prod.dart';

class MockFirebaseDatasource extends Mock implements FirebaseDatasource {}
class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockFunctionsClient extends Mock implements FunctionsClient {}
class MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

class FakePostgrestFilterBuilder<T> extends Fake
    implements PostgrestFilterBuilder<T>, PostgrestTransformBuilder<T> {
  final T value;
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
    return Future.value(onValue(value));
  }
}

void main() {
  late MockFirebaseDatasource mockFirebaseDatasource;
  late MockSupabaseClient mockSupabaseClient;
  late MockFunctionsClient mockFunctionsClient;
  late MockSupabaseQueryBuilder mockMethodsQueryBuilder;
  late MockSupabaseQueryBuilder mockGatewaysQueryBuilder;
  late PaymentMethodsRepositoryImpl repository;

  setUp(() {
    mockFirebaseDatasource = MockFirebaseDatasource();
    mockSupabaseClient = MockSupabaseClient();
    mockFunctionsClient = MockFunctionsClient();
    mockMethodsQueryBuilder = MockSupabaseQueryBuilder();
    mockGatewaysQueryBuilder = MockSupabaseQueryBuilder();

    repository = PaymentMethodsRepositoryImpl(mockFirebaseDatasource);

    when(() => mockFirebaseDatasource.supabaseClient).thenReturn(mockSupabaseClient);
    when(() => mockSupabaseClient.functions).thenReturn(mockFunctionsClient);
  });

  const tUid = 'test-uid';

  final tMethodsResult = [
    {
      'id': '1',
      'card_type': 'visa',
      'last_four': '1234',
      'title': 'My Visa',
      'expiry_date': '2030-12-31T23:59:59Z',
      'is_default': true,
      'is_enabled': true,
    }
  ];

  final tGatewaysResult = [
    {
      'id': 'gw-1',
      'name': 'Stripe',
      'logo_url': 'logo.png',
      'external_url': 'http://external.url',
    }
  ];

  group('getSavedPaymentMethods', () {
    test('should return list of saved methods and gateways on success', () async {
      // arrange
      when(() => mockFirebaseDatasource.uid).thenReturn(tUid);
      when(() => mockSupabaseClient.from('payment_methods')).thenAnswer((_) => mockMethodsQueryBuilder);
      when(() => mockMethodsQueryBuilder.select()).thenAnswer((_) => FakePostgrestFilterBuilder(tMethodsResult));

      when(() => mockSupabaseClient.from('payment_gateways')).thenAnswer((_) => mockGatewaysQueryBuilder);
      when(() => mockGatewaysQueryBuilder.select()).thenAnswer((_) => FakePostgrestFilterBuilder(tGatewaysResult));

      // act
      final result = await repository.getSavedPaymentMethods();

      // assert
      expect(result.isRight(), isTrue);
      final (methods, gateways) = result.getOrElse(() => throw Exception('Failed'));
      expect(methods.length, 1);
      expect(methods.first.id, '1');
      expect(methods.first.cardType, CardType.visa);
      expect(methods.first.last4Digits, '1234');
      expect(methods.first.isDefault, isTrue);

      expect(gateways.length, 1);
      expect(gateways.first.id, 'gw-1');
      expect(gateways.first.name, 'Stripe');
    });

    test('should return server failure when exception is thrown', () async {
      // arrange
      when(() => mockFirebaseDatasource.uid).thenReturn(tUid);
      when(() => mockSupabaseClient.from(any())).thenThrow(Exception('Database error'));

      // act
      final result = await repository.getSavedPaymentMethods();

      // assert
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<Failure>()),
        (_) => fail('Should have failed'),
      );
    });
  });

  group('startSavedPaymentMethodsSubscription', () {
    test('should emit payment methods once via Future and complete', () async {
      // arrange
      when(() => mockFirebaseDatasource.uid).thenReturn(tUid);
      when(() => mockSupabaseClient.from('payment_methods')).thenAnswer((_) => mockMethodsQueryBuilder);
      when(() => mockMethodsQueryBuilder.select()).thenAnswer((_) => FakePostgrestFilterBuilder(tMethodsResult));

      when(() => mockSupabaseClient.from('payment_gateways')).thenAnswer((_) => mockGatewaysQueryBuilder);
      when(() => mockGatewaysQueryBuilder.select()).thenAnswer((_) => FakePostgrestFilterBuilder(tGatewaysResult));

      // act
      final stream = repository.startSavedPaymentMethodsSubscription();
      final emits = await stream.toList();

      // assert
      expect(emits.length, 1);
      final (methods, gateways) = emits.first.getOrElse(() => throw Exception('Failed'));
      expect(methods.length, 1);
      expect(gateways.length, 1);
    });
  });

  group('getExternalUrl', () {
    test('should return redirect URL from edge function', () async {
      // arrange
      when(() => mockFirebaseDatasource.uid).thenReturn(tUid);
      when(() => mockFunctionsClient.invoke(
            'create-payment-preference',
            body: {'amount': 50.00},
          )).thenAnswer((_) async => FunctionResponse(
            status: 200,
            data: {'url': 'https://mercado-pago.com/checkout'},
          ));

      // act
      final result = await repository.getExternalUrl(paymentGatewayId: 'gw-1');

      // assert
      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => ''), 'https://mercado-pago.com/checkout');
    });
  });
}
