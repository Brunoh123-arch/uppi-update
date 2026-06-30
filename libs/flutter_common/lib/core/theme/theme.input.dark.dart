part of 'theme.dart';

InputDecorationTheme inputThemeDark(String fontPrimary, String fontSecondary) =>
    inputTheme(fontPrimary, fontSecondary).copyWith(
      fillColor: darkColorScheme.surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: darkColorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: darkColorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: darkColorScheme.primary),
      ),
      hintStyle: textThemeDark(fontPrimary, fontSecondary).bodyLarge?.copyWith(
        color: darkColorScheme.onSurfaceVariant,
      ),
    );
