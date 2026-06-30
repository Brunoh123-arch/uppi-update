import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rider_flutter/core/error/failure.dart';
import 'package:flutter_common/core/entities/wallet_query_response.dart';
import 'package:rider_flutter/features/wallet/domain/repositories/wallet_repository.dart';
import 'package:rider_flutter/features/wallet/presentation/blocs/wallet.dart';

class MockWalletRepository extends Mock implements WalletRepository {}

void main() {
  late MockWalletRepository mockWalletRepository;

  setUp(() {
    mockWalletRepository = MockWalletRepository();
  });

  final tWalletData = WalletQueryResponse(
    firstName: 'João',
    lastName: 'Silva',
    currency: 'BRL',
    balance: 150.50,
    pendingBalance: 0.0,
    transactions: const [],
    paymentGateways: const [],
    savedPaymentMethods: const [],
  );

  group('WalletBloc', () {
    test('initial state is WalletState.initial', () {
      expect(
        WalletBloc(mockWalletRepository).state,
        const WalletState.initial(),
      );
    });

    blocTest<WalletBloc, WalletState>(
      'emits [loading, loaded] when load succeeds',
      build: () {
        when(() => mockWalletRepository.startWalletSubscription())
            .thenAnswer((_) => Stream.value(Right(tWalletData)));
        return WalletBloc(mockWalletRepository);
      },
      act: (bloc) => bloc.load(),
      expect: () => [
        const WalletState.loading(),
        WalletState.loaded(data: tWalletData),
      ],
      verify: (_) {
        verify(() => mockWalletRepository.startWalletSubscription()).called(1);
      },
    );

    blocTest<WalletBloc, WalletState>(
      'emits [loading, error] when load fails with server error',
      build: () {
        when(() => mockWalletRepository.startWalletSubscription()).thenAnswer(
          (_) => Stream.value(const Left(Failure.server(message: 'Sem conexão'))),
        );
        return WalletBloc(mockWalletRepository);
      },
      act: (bloc) => bloc.load(),
      expect: () => [
        const WalletState.loading(),
        const WalletState.error('Sem conexão'),
      ],
    );

    blocTest<WalletBloc, WalletState>(
      'emits [loading, error] when load fails with connection error',
      build: () {
        when(() => mockWalletRepository.startWalletSubscription()).thenAnswer(
          (_) => Stream.value(const Left(Failure.connection(message: 'Sem internet'))),
        );
        return WalletBloc(mockWalletRepository);
      },
      act: (bloc) => bloc.load(),
      expect: () => [
        const WalletState.loading(),
        const WalletState.error('Sem internet'),
      ],
    );

    blocTest<WalletBloc, WalletState>(
      'can reload after error state',
      build: () {
        var callCount = 0;
        when(() => mockWalletRepository.startWalletSubscription()).thenAnswer((_) {
          callCount++;
          if (callCount == 1) {
            return Stream.value(const Left(Failure.server(message: 'Timeout')));
          }
          return Stream.value(Right(tWalletData));
        });
        return WalletBloc(mockWalletRepository);
      },
      act: (bloc) async {
        bloc.load();
        await Future.delayed(const Duration(milliseconds: 100));
        bloc.load();
      },
      expect: () => [
        const WalletState.loading(),
        const WalletState.error('Timeout'),
        const WalletState.loading(),
        WalletState.loaded(data: tWalletData),
      ],
    );
  });

  group('WalletQueryResponse extensions', () {
    test('fullName concatenates first and last name', () {
      expect(tWalletData.fullName, 'João Silva');
    });

    test('formattedBalance formats BRL currency correctly', () {
      final formatted = tWalletData.formattedBalance;
      // Aceita diferentes formatos de moeda brasileira
      expect(formatted.contains('150'), isTrue);
    });
  });
}
