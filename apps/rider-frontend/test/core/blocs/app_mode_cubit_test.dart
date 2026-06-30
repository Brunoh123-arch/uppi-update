import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rider_flutter/core/blocs/app_mode_cubit.dart';

class MockStorage extends Mock implements Storage {}

void main() {
  late Storage storage;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final channelName in [
      'wakelock',
      'wakelock_plus',
      'dev.fluttercommunity.plus/wakelock',
    ]) {
      final channel = MethodChannel(channelName);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        return null;
      });
    }

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (ByteData? message) async {
        return StandardMessageCodec().encodeMessage(<Object?>[null]);
      },
    );
  });

  setUp(() {
    storage = MockStorage();
    when(() => storage.read(any())).thenReturn(null);
    when(() => storage.write(any(), any<dynamic>())).thenAnswer((_) async {});
    when(() => storage.delete(any())).thenAnswer((_) async {});
    when(() => storage.clear()).thenAnswer((_) async {});
    HydratedBloc.storage = storage;
  });

  group('AppModeCubit', () {
    test('initial state is AppMode.none', () {
      expect(AppModeCubit().state, AppMode.none);
    });

    blocTest<AppModeCubit, AppMode>(
      'emits [AppMode.rider] when selectRider is called',
      build: () => AppModeCubit(),
      act: (cubit) => cubit.selectRider(),
      expect: () => [AppMode.rider],
    );

    blocTest<AppModeCubit, AppMode>(
      'emits [AppMode.driver] when selectDriver is called',
      build: () => AppModeCubit(),
      act: (cubit) => cubit.selectDriver(),
      expect: () => [AppMode.driver],
    );

    blocTest<AppModeCubit, AppMode>(
      'emits [AppMode.none] when reset is called from rider mode',
      build: () => AppModeCubit(),
      seed: () => AppMode.rider,
      act: (cubit) => cubit.reset(),
      expect: () => [AppMode.none],
    );

    blocTest<AppModeCubit, AppMode>(
      'emits [AppMode.none] when reset is called from driver mode',
      build: () => AppModeCubit(),
      seed: () => AppMode.driver,
      act: (cubit) => cubit.reset(),
      expect: () => [AppMode.none],
    );

    blocTest<AppModeCubit, AppMode>(
      'can switch from rider to driver mode',
      build: () => AppModeCubit(),
      act: (cubit) {
        cubit.selectRider();
        cubit.selectDriver();
      },
      expect: () => [AppMode.rider, AppMode.driver],
    );

    test('serializes to JSON correctly', () {
      final cubit = AppModeCubit();
      cubit.selectRider();
      final json = cubit.toJson(cubit.state);
      expect(json, {'mode': 'rider'});
    });

    test('deserializes from JSON correctly', () {
      final cubit = AppModeCubit();
      final state = cubit.fromJson({'mode': 'driver'});
      expect(state, AppMode.driver);
    });

    test('deserializes unknown mode to AppMode.none', () {
      final cubit = AppModeCubit();
      final state = cubit.fromJson({'mode': 'invalid_mode'});
      expect(state, AppMode.none);
    });

    test('deserializes null mode to AppMode.none', () {
      final cubit = AppModeCubit();
      final state = cubit.fromJson({});
      expect(state, AppMode.none);
    });
  });
}
