import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uppi_motorista/core/datasources/firebase_datasource.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:uppi_motorista/features/ride_history/data/repositories/ride_history_repository.prod.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:flutter_common/core/enums/payment_mode.dart';

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
  late MockSupabaseQueryBuilder mockRidesQB;
  late RideHistoryRepositoryImpl repository;

  setUp(() {
    mockFirebaseDatasource = MockFirebaseDatasource();
    mockSupabaseClient = MockSupabaseClient();
    mockRidesQB = MockSupabaseQueryBuilder();

    repository = RideHistoryRepositoryImpl(
      mockFirebaseDatasource,
      supabaseClient: mockSupabaseClient,
    );

    registerFallbackValue(const Offset(0, 0));
  });

  const tUid = 'test-driver-id';

  final tRidesResult = [
    {
      'id': 'ride-1',
      'status': 'completed',
      'created_at': '2026-06-17T10:00:00.000Z',
      'finished_at': '2026-06-17T10:15:00.000Z',
      'fare': 25.5,
      'actual_distance': 5000,
      'actual_duration': 900,
      'payment_method': 'cash',
      'currency': 'BRL',
      'service_type': 'Standard',
      'pickup_lat': -23.55052,
      'pickup_lng': -46.633308,
      'pickup_address': 'Origem A',
      'dropoff_lat': -23.55952,
      'dropoff_lng': -46.639308,
      'dropoff_address': 'Destino B',
    }
  ];

  void mockSuccessfulQueries() {
    when(() => mockFirebaseDatasource.uid).thenReturn(tUid);
    when(() => mockSupabaseClient.from('rides')).thenAnswer((_) => mockRidesQB);
    when(() => mockRidesQB.select()).thenAnswer((_) => FakePostgrestFilterBuilder<List<Map<String, dynamic>>>(tRidesResult));
  }

  group('getRideHistory', () {
    test('should return List<OrderEntity> mapped correctly on success', () async {
      // arrange
      mockSuccessfulQueries();

      // act
      final result = await repository.getRideHistory();

      // assert
      expect(result.isRight(), isTrue);
      final response = result.getOrElse(() => throw Exception('Failed to get ride history'));
      
      expect(response.length, 1);
      expect(response[0].id, 'ride-1');
      expect(response[0].costBest, 25.5);
      expect(response[0].status, OrderStatus.finished);
      expect(response[0].paymentMode, PaymentMode.cash);
      expect(response[0].serviceName, 'Standard');
      expect(response[0].currency, 'BRL');
      expect(response[0].distanceBest, 5000);
      expect(response[0].durationBest, 900);
    });

    test('should return Left(Failure.server) when exception is thrown', () async {
      // arrange
      when(() => mockFirebaseDatasource.uid).thenReturn(tUid);
      when(() => mockSupabaseClient.from(any())).thenThrow(Exception('Database error'));

      // act
      final result = await repository.getRideHistory();

      // assert
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<Failure>()),
        (_) => fail('Should have failed'),
      );
    });
  });

  group('startRideHistorySubscription', () {
    test('should yield ride list once and close', () async {
      // arrange
      mockSuccessfulQueries();

      // act
      final stream = repository.startRideHistorySubscription();
      final emits = await stream.toList();

      // assert
      expect(emits.length, 1);
      expect(emits.first.isRight(), isTrue);
    });
  });
}
