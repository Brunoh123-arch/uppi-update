import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/config/constants.dart';
import 'package:flutter_common/core/enums/map_provider_enum.prod.dart';
import 'package:flutter_common/core/utils/uppi_haptics.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:generic_map/generic_map.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

part 'settings.state.dart';
part 'settings.freezed.dart';
part 'settings.g.dart';

class SettingsCubit extends HydratedCubit<SettingsState> {
  SettingsCubit() : super(SettingsState.initial());

  @override
  String get id => 'uppi_settings_cubit';

  @override
  SettingsState? fromJson(Map<String, dynamic> json) {
    return SettingsState.fromJson(json);
  }

  @override
  Map<String, dynamic>? toJson(SettingsState state) {
    return state.toJson();
  }

  void changeLanguage(String locale) {
    UppiHaptics.selection();
    emit(state.copyWith(locale: locale));
  }

  void changeMapProvider(MapProviderEnum mapProvider) {
    UppiHaptics.selection();
    emit(state.copyWith(mapProvider: mapProvider));
  }

  void changeThemeMode(ThemeMode mode) {
    UppiHaptics.selection();
    final str = mode == ThemeMode.dark ? 'dark' : mode == ThemeMode.light ? 'light' : 'system';
    emit(state.copyWith(themeModeStr: str));
  }
}