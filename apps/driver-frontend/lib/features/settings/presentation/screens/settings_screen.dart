import 'package:auto_route/auto_route.dart';
import 'package:uppi_motorista/config/env.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/features/lgpd/presentation/lgpd_data_rights_screen.dart';
import 'package:ionicons/ionicons.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:flutter_common/core/blocs/settings.dart';
import 'package:uppi_motorista/core/router/app_router.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/app_menu_item.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_top_bar.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:uppi_motorista/features/profile/presentation/dialogs/delete_account_dialog.dart';
import 'package:flutter_common/core/presentation/uppi_feedback.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:uppi_motorista/core/datasources/location_datasource.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

@RoutePage(name: 'DriverSettingsRoute')
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
            AppTopBar(title: context.translate.settings),
            const SizedBox(height: 24),

            // ── Tema ──────────────────────────────────────────────
            BlocBuilder<SettingsCubit, SettingsState>(
              bloc: locator<SettingsCubit>(),
              builder: (context, settings) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.translate.appearance.toUpperCase(),
                      style: context.labelSmall?.copyWith(
                        color: ColorPalette.neutralVariant50,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: context.theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: context.theme.colorScheme.outline.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          _ThemeTile(
                            icon: Ionicons.sunny_outline,
                            label: context.translate.themeModeLight,
                            selected: settings.themeMode == ThemeMode.light,
                            onTap: () => locator<SettingsCubit>().changeThemeMode(ThemeMode.light),
                          ),
                          Divider(height: 1, color: context.theme.colorScheme.outline.withOpacity(0.2)),
                          _ThemeTile(
                            icon: Ionicons.moon_outline,
                            label: context.translate.themeModeDark,
                            selected: settings.themeMode == ThemeMode.dark,
                            onTap: () => locator<SettingsCubit>().changeThemeMode(ThemeMode.dark),
                          ),
                          Divider(height: 1, color: context.theme.colorScheme.outline.withOpacity(0.2)),
                          _ThemeTile(
                            icon: Ionicons.phone_portrait_outline,
                            label: context.translate.themeModeSystem,
                            selected: settings.themeMode == ThemeMode.system,
                            onTap: () => locator<SettingsCubit>().changeThemeMode(ThemeMode.system),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),

            // ── Economia de Bateria ──────────────────────────────
            const _BatterySaverTile(),
            const SizedBox(height: 24),

            // ── LGPD — Privacidade e Dados ───────────────────────
            AppMenuItem(
              icon: Ionicons.shield_checkmark_outline,
              title: context.translate.privacyPolicy,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LgpdDataRightsScreen(
                      onDeleteAccountRequested: () {
                        Navigator.of(context).pop();
                        showDialog(
                          context: context,
                          useSafeArea: false,
                          builder: (_) => const DeleteAccountDialog(),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            if (Env.isDemoMode) ...[
              AppMenuItem(
                icon: Ionicons.map,
                title: context.translate.mapSettings,
                onPressed: () {
                  context.router.push(const DriverMapSettingsRoute());
                },
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected
                  ? context.theme.colorScheme.primary
                  : context.theme.colorScheme.onSurface.withOpacity(0.6),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: context.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected
                      ? context.theme.colorScheme.primary
                      : context.theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (selected)
              Icon(
                Ionicons.checkmark_circle,
                color: context.theme.colorScheme.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

/// Tile de Economia de Bateria (Fase 27)
class _BatterySaverTile extends StatefulWidget {
  const _BatterySaverTile();

  @override
  State<_BatterySaverTile> createState() => _BatterySaverTileState();
}

class _BatterySaverTileState extends State<_BatterySaverTile> {
  bool _isSaverEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSaverMode();
  }

  Future<void> _loadSaverMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isSaverEnabled = prefs.getBool('battery_saver_mode') ?? false;
      });
    }
  }

  Future<void> _toggleSaverMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('battery_saver_mode', value);
    try {
      locator<LocationDatasource>().updateBatterySaverMode(value);
    } catch (e) {
      debugPrint('[SETTINGS] Erro ao atualizar BatterySaverMode no LocationDatasource: $e');
      UppiPerformance.batterySaverMode = value;
    }

    try {
      if (value) {
        await WakelockPlus.disable();
      } else {
        await WakelockPlus.enable();
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isSaverEnabled = value;
      });
    }
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.theme.colorScheme.outline.withOpacity(0.3),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(
            Ionicons.battery_charging_outline,
            size: 20,
            color: ColorPalette.primary40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Modo Economia de Bateria",
                  style: context.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Suaviza animações e economiza bateria em viagens longas",
                  style: context.bodySmall?.copyWith(
                    color: ColorPalette.neutralVariant50,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isSaverEnabled,
            onChanged: _toggleSaverMode,
            activeThumbColor: ColorPalette.primary40,
          ),
        ],
      ),
    );
  }
}
