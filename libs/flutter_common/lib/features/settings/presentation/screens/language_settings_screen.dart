import 'package:flutter/material.dart';
import 'package:flutter_common/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_top_bar.dart';
import 'package:flutter_common/features/select_language_dialog/select_language_dialog.dart';

/// Tela compartilhada de configurações de idioma.
class SharedLanguageSettingsScreen extends StatelessWidget {
  final String selectedLanguageCode;
  final void Function(String languageCode) onLanguageChanged;

  const SharedLanguageSettingsScreen({
    super.key,
    required this.selectedLanguageCode,
    required this.onLanguageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.theme.scaffoldBackgroundColor,
      padding: EdgeInsets.symmetric(
        horizontal: context.responsive(16, xl: 24),
        vertical: context.responsive(16, xl: 24),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            context.responsive(
              const SizedBox(),
              xl: const SizedBox(height: 80),
            ),
            AppTopBar(title: context.t.lanugageSettings),
            const SizedBox(height: 16),
            Expanded(
              child: LanguageList(
                selectedLanguageCode: selectedLanguageCode,
                onPressed: (language) => onLanguageChanged(language.code),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
