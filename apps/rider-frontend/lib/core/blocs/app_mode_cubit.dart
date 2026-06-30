import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_common/core/presentation/uppi_feedback.dart';

enum AppMode { none, rider, driver }

@singleton
class AppModeCubit extends HydratedCubit<AppMode> {
  AppModeCubit() : super(AppMode.none);

  void selectRider() {
    WakelockPlus.disable();
    emit(AppMode.rider);
  }

  void selectDriver() {
    if (!UppiPerformance.batterySaverMode) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
    emit(AppMode.driver);
  }

  void reset() {
    WakelockPlus.disable();
    emit(AppMode.none);
  }

  void updateWakelockState() {
    if (state == AppMode.driver && !UppiPerformance.batterySaverMode) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  @override
  AppMode? fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String?;
    if (modeName == 'rider') return AppMode.rider;
    if (modeName == 'driver') return AppMode.driver;
    return AppMode.none;
  }

  @override
  Map<String, dynamic>? toJson(AppMode state) => {'mode': state.name};
}
