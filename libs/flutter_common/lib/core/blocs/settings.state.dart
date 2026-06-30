part of 'settings.dart';

@freezed
class SettingsState with _$SettingsState {
  const factory SettingsState({
    required String locale,
    MapProviderEnum? mapProvider,
    // Tema: 'system' | 'light' | 'dark'
    String? themeModeStr,
  }) = _SettingsState;

  factory SettingsState.initial() {
    final systemLocale = PlatformDispatcher.instance.locale.languageCode;
    const supported = ['pt', 'en', 'es'];
    final initialLocale = supported.contains(systemLocale) ? systemLocale : 'pt';
    return SettingsState(
      locale: initialLocale,
      mapProvider: MapProviderEnum.googleMaps,
    );
  }

  factory SettingsState.fromJson(Map<String, dynamic> json) =>
      _$SettingsStateFromJson(json);

  const SettingsState._();

  ThemeMode get themeMode {
    switch (themeModeStr) {
      case 'dark': return ThemeMode.dark;
      case 'light': return ThemeMode.light;
      default: return ThemeMode.system;
    }
  }

  MapProviderEnum get mapProviderEnum {
    if (mapProvider != null) return mapProvider!;
    return Constants.defaultMapProvider;
  }

  MapProvider get provider =>
      mapProviderEnum.providerObject;
}