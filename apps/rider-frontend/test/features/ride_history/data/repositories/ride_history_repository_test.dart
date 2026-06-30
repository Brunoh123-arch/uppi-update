import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/error/failure.dart';
import 'package:rider_flutter/features/ride_history/data/repositories/ride_history_repository.prod.dart';

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
  late MockSupabaseQueryBuilder mockProfilesQB;
  late MockSupabaseQueryBuilder mockServicesQB;

  late RideHistoryRepositoryImpl repository;

  setUp(() {
    mockFirebaseDatasource = MockFirebaseDatasource();
    mockSupabaseClient = MockSupabaseClient();
    
    mockRidesQB = MockSupabaseQueryBuilder();
    mockProfilesQB = MockSupabaseQueryBuilder();
    mockServicesQB = MockSupabaseQueryBuilder();

    repository = RideHistoryRepositoryImpl(
      mockFirebaseDatasource,
      supabaseClient: mockSupabaseClient,
    );

    registerFallbackValue(const Offset(0, 0));
  });

  const tUid = 'test-uid';

  final tRidesResult = [
    {
      'id': 'ride-1',
      'status': 'completed',
      'created_at': '2026-06-17T10:00:00.000Z',
      'finished_at': '2026-06-17T10:15:00.000Z',
      'distance_meters': 5000,
      'duration_seconds': 900,
      'fare': 25.5,
      'driver_id': 'driver-1',
      'service_id': 'srv-1',
      'payment_method': 'wallet',
      'pickup_lat': -23.55052,
      'pickup_lng': -46.633308,
      'pickup_address': 'Origem A',
      'dropoff_lat': -23.55952,
      'dropoff_lng': -46.639308,
      'dropoff_address': 'Destino B',
    }
  ];

  final tProfilesResult = [
    {
      'id': 'driver-1',
      'rating': '4.8',
      'rating_count': 100,
      'full_name': 'Carlos Silva',
      'avatar_url': 'avatar.png',
      'vehicle_details': {
        'model': 'Toyota Corolla',
        'plate': 'ABC-1234',
        'color': 'Prata'
      }
    }
  ];

  final tServicesResult = [
    {
      'id': 'srv-1',
      'name': 'Uppi Black',
      'image_url': 'service_black.png'
    }
  ];

  void mockSuccessfulQueries() {
    when(() => mockFirebaseDatasource.uid).thenReturn(tUid);
    
    when(() => mockSupabaseClient.from('rides')).thenAnswer((_) => mockRidesQB);
    when(() => mockRidesQB.select()).thenAnswer((_) => FakePostgrestFilterBuilder<List<Map<String, dynamic>>>(tRidesResult));

    when(() => mockSupabaseClient.from('profiles')).thenAnswer((_) => mockProfilesQB);
    when(() => mockProfilesQB.select()).thenAnswer((_) => FakePostgrestFilterBuilder<List<Map<String, dynamic>>>(tProfilesResult));

    when(() => mockSupabaseClient.from('services')).thenAnswer((_) => mockServicesQB);
    when(() => mockServicesQB.select(any())).thenAnswer((_) => FakePostgrestFilterBuilder<List<Map<String, dynamic>>>(tServicesResult));
  }

  group('getRideHistory', () {
    test('should return List<OrderCompactEntity> mapped correctly on success', () async {
      // arrange
      mockSuccessfulQueries();

      // act
      final result = await repository.getRideHistory();

      // assert
      expect(result.isRight(), isTrue);
      final response = result.getOrElse(() => throw Exception('Failed to get ride history'));
      
      expect(response.length, 1);
      expect(response[0].id, 'ride-1');
      expect(response[0].fee, 25.5);
      expect(response[0].distanceBest, 5000);
      expect(response[0].durationBest, 900);
      expect(response[0].serviceName, 'Uppi Black');
      expect(response[0].serviceImageUrl, 'https://kqfmahrxjuqlvxngeurj.supabase.co/storage/v1/object/public/service-images/service_black.png');
      expect(response[0].driver, isNotNull);
      expect(response[0].driver?.firstName, 'Carlos Silva');
      expect(response[0].driver?.vehicleModel, 'Toyota Corolla');
    });

    test('should return Left(Failure.serverError) when not authenticated', () async {
      // arrange
      when(() => mockFirebaseDatasource.uid).thenReturn(null);

      // act
      final result = await repository.getRideHistory();

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
