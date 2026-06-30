import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:flutter_common/core/blocs/settings.dart';
import 'package:flutter_common/features/settings/presentation/screens/language_settings_screen.dart';

@RoutePage()
class LanguageSettingsScreen extends StatelessWidget {
  const LanguageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        return SharedLanguageSettingsScreen(
          selectedLanguageCode: state.locale,
          onLanguageChanged: (languageCode) =>
              locator<SettingsCubit>().changeLanguage(languageCode),
        );
      },
    );
  }
}
