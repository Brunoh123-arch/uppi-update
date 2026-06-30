import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rider_flutter/features/auth/presentation/blocs/onboarding_cubit.dart';

class MockStorage extends Mock implements Storage {}

void main() {
  late Storage storage;

  setUp(() {
    storage = MockStorage();
    when(() => storage.read(any())).thenReturn(null);
    when(() => storage.write(any(), any<dynamic>())).thenAnswer((_) async {});
    when(() => storage.delete(any())).thenAnswer((_) async {});
    when(() => storage.clear()).thenAnswer((_) async {});
    HydratedBloc.storage = storage;
  });

  group('OnboardingCubit', () {
    test('initial state is 0', () {
      expect(OnboardingCubit().state, 0);
    });

    blocTest<OnboardingCubit, int>(
      'emits [1] when nextPage is called',
      build: () => OnboardingCubit(),
      act: (cubit) => cubit.nextPage(),
      expect: () => [1],
    );

    blocTest<OnboardingCubit, int>(
      'emits [2] when skip is called',
      build: () => OnboardingCubit(),
      act: (cubit) => cubit.skip(),
      expect: () => [2],
    );

    blocTest<OnboardingCubit, int>(
      'emits [0] when reset is called with seed 2',
      build: () => OnboardingCubit(),
      seed: () => 2,
      act: (cubit) => cubit.reset(),
      expect: () => [0],
    );

    test('isDone extension works correctly', () {
      final cubit = OnboardingCubit();
      expect(cubit.isDone, false);
      cubit.skip();
      expect(cubit.isDone, true);
    });
  });
}
