import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/uppi_feedback.dart';
import 'package:flutter_common/core/presentation/shimmer_placeholder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_common/features/lgpd/presentation/lgpd_data_rights_screen.dart';
import 'package:ionicons/ionicons.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/config/router/app_router.dart';
import 'package:rider_flutter/core/blocs/auth_bloc.dart';
import 'package:rider_flutter/core/blocs/app_mode_cubit.dart';
import 'package:flutter_common/core/blocs/settings.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/app_menu_item.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:flutter_common/core/presentation/responsive_dialog/app_top_bar.dart';
import 'package:rider_flutter/features/profile/presentation/dialogs/delete_account_dialog.dart';
import 'package:uppi_motorista/config/locator/locator.dart' as driver_locator;
import 'package:uppi_motorista/core/datasources/location_datasource.dart' as driver_location;
import 'package:wakelock_plus/wakelock_plus.dart';

@RoutePage()
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.theme.scaffoldBackgroundColor,
      padding: EdgeInsets.symmetric(
        horizontal: context.responsive(16, xl: 24),
        vertical: context.responsive(16, xl: 24),
      ),
      child: SafeArea(
        child: _isLoading ? const _SettingsSkeleton() : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            context.responsive(const SizedBox(), xl: const SizedBox(height: 80)),
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
                          color: context.theme.colorScheme.outline.withValues(alpha: 0.3),
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
                          Divider(height: 1, color: context.theme.colorScheme.outline.withValues(alpha: 0.2)),
                          _ThemeTile(
                            icon: Ionicons.moon_outline,
                            label: context.translate.themeModeDark,
                            selected: settings.themeMode == ThemeMode.dark,
                            onTap: () => locator<SettingsCubit>().changeThemeMode(ThemeMode.dark),
                          ),
                          Divider(height: 1, color: context.theme.colorScheme.outline.withValues(alpha: 0.2)),
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

            // ── Desempenho & Bateria (Fase 27) ────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "DESEMPENHO & BATERIA",
                  style: context.labelSmall?.copyWith(
                    color: ColorPalette.neutralVariant50,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                const _BatterySaverTile(),
                const SizedBox(height: 24),
              ],
            ),

            // ── Segurança (PIN de Embarque) ──────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "SEGURANÇA",
                  style: context.labelSmall?.copyWith(
                    color: ColorPalette.neutralVariant50,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                const _BoardingPinSettingsTile(),
                const SizedBox(height: 24),
              ],
            ),

            // ── Idioma ──────────────────────────────────────────────
            BlocBuilder<SettingsCubit, SettingsState>(
              bloc: locator<SettingsCubit>(),
              builder: (context, settings) {
                final langLabel = _languageLabel(settings.locale);
                return AppMenuItem(
                  icon: Ionicons.globe_outline,
                  title: context.translate.language,
                  subtitle: langLabel,
                  onPressed: () {
                    context.router.push(const LanguageSettingsRoute());
                  },
                );
              },
            ),
            const SizedBox(height: 16),

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

            BlocBuilder<AuthBloc, AuthState>(
              bloc: locator<AuthBloc>(),
              builder: (context, state) {
                if (!state.isAuthenticated) return const SizedBox();
                return Column(
                  children: [
                    const Divider(height: 32),
                    Text(
                      context.translate.account,
                      style: context.labelLarge?.copyWith(
                        color: ColorPalette.neutralVariant50,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppMenuItem(
                      icon: Ionicons.log_out_outline,
                      title: context.translate.logout,
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(context.translate.logout),
                            content: Text(
                              context.translate.logoutConfirmMessage,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: Text(context.translate.cancel),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  locator<AuthBloc>().onLoggedOut();
                                  locator<AppModeCubit>().reset();
                                  context.router.replaceAll([const RoleSelectionRoute()]);
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: ColorPalette.error40,
                                ),
                                child: Text(context.translate.logout),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    AppMenuItem(
                      icon: Ionicons.trash_outline,
                      title: context.translate.deleteAccount,
                      onPressed: () {
                        showDialog(
                          context: context,
                          useSafeArea: false,
                          builder: (context) => const DeleteAccountDialog(),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Tile individual de seleção de tema
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
            Icon(icon,
              size: 20,
              color: selected
                  ? context.theme.colorScheme.primary
                  : context.theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
    UppiPerformance.batterySaverMode = value;

    // Atualiza o datasource do motorista, se ativo/inicializado
    try {
      if (driver_locator.locator.isRegistered<driver_location.LocationDatasource>()) {
        driver_locator.locator<driver_location.LocationDatasource>().updateBatterySaverMode(value);
      }
    } catch (_) {}

    // Atualiza o Wakelock se estiver no modo motorista
    try {
      if (locator<AppModeCubit>().state == AppMode.driver) {
        if (value) {
          await WakelockPlus.disable();
        } else {
          await WakelockPlus.enable();
        }
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
          color: context.theme.colorScheme.outline.withValues(alpha: 0.3),
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

String _languageLabel(String code) {
  switch (code) {
    case 'pt':
      return 'Português';
    case 'en':
      return 'English';
    case 'es':
      return 'Español';
    case 'fr':
      return 'Français';
    case 'de':
      return 'Deutsch';
    case 'it':
      return 'Italiano';
    case 'ar':
      return 'العربية';
    case 'ja':
      return '日本語';
    case 'ko':
      return '한국어';
    case 'zh':
      return '中文';
    case 'ru':
      return 'Русский';
    default:
      return code.toUpperCase();
  }
}

/// Tile do PIN de Embarque (Boarding PIN)
class _BoardingPinSettingsTile extends StatefulWidget {
  const _BoardingPinSettingsTile();

  @override
  State<_BoardingPinSettingsTile> createState() => _BoardingPinSettingsTileState();
}

class _BoardingPinSettingsTileState extends State<_BoardingPinSettingsTile> {
  bool _isPinEnabled = false;
  bool _isLoading = true;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _loadPinSetting();
  }

  Future<void> _loadPinSetting() async {
    try {
      _uid = Supabase.instance.client.auth.currentUser?.id;
      if (_uid != null) {
        final data = await Supabase.instance.client
            .from('profiles')
            .select('boarding_pin_enabled')
            .eq('id', _uid!)
            .maybeSingle();
        if (data != null && mounted) {
          setState(() {
            _isPinEnabled = data['boarding_pin_enabled'] == true;
            _isLoading = false;
          });
        } else {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _togglePinSetting(bool value) async {
    if (_uid == null) return;
    HapticFeedback.lightImpact();
    // Atualiza estado local de forma otimista
    setState(() {
      _isPinEnabled = value;
    });

    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'boarding_pin_enabled': value})
          .eq('id', _uid!);
    } catch (_) {
      // Reverte em caso de falha de rede
      if (mounted) {
        setState(() {
          _isPinEnabled = !value;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 56,
        child: Center(
          child: CircularProgressIndicator.adaptive(),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(
            Ionicons.shield_outline,
            size: 20,
            color: ColorPalette.primary40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "PIN de Embarque de Segurança",
                  style: context.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Exige um código de 4 dígitos para iniciar todas as suas corridas",
                  style: context.bodySmall?.copyWith(
                    color: ColorPalette.neutralVariant50,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isPinEnabled,
            onChanged: _togglePinSetting,
            activeThumbColor: ColorPalette.primary40,
          ),
        ],
      ),
    );
  }
}

class _SettingsSkeleton extends StatelessWidget {
  const _SettingsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        context.responsive(const SizedBox(), xl: const SizedBox(height: 80)),
        const SizedBox(height: 24),
        const ShimmerPlaceholder(width: 150, height: 28),
        const SizedBox(height: 32),
        const ShimmerPlaceholder(width: 100, height: 14),
        const SizedBox(height: 12),
        Container(
          height: 160,
          decoration: BoxDecoration(
            color: ColorPalette.neutralVariant99,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.theme.colorScheme.outline.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: const [
                    ShimmerPlaceholder(width: 24, height: 24, borderRadius: BorderRadius.all(Radius.circular(12))),
                    SizedBox(width: 12),
                    ShimmerPlaceholder(width: 180, height: 16),
                  ],
                ),
              ),
              Divider(height: 1, color: context.theme.colorScheme.outline.withValues(alpha: 0.2)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: const [
                    ShimmerPlaceholder(width: 24, height: 24, borderRadius: BorderRadius.all(Radius.circular(12))),
                    SizedBox(width: 12),
                    ShimmerPlaceholder(width: 180, height: 16),
                  ],
                ),
              ),
              Divider(height: 1, color: context.theme.colorScheme.outline.withValues(alpha: 0.2)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: const [
                    ShimmerPlaceholder(width: 24, height: 24, borderRadius: BorderRadius.all(Radius.circular(12))),
                    SizedBox(width: 12),
                    ShimmerPlaceholder(width: 180, height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const ShimmerPlaceholder(width: 180, height: 14),
        const SizedBox(height: 12),
        Container(
          height: 70,
          decoration: BoxDecoration(
            color: ColorPalette.neutralVariant99,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.theme.colorScheme.outline.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: const [
                ShimmerPlaceholder(width: 24, height: 24, borderRadius: BorderRadius.all(Radius.circular(12))),
                SizedBox(width: 12),
                ShimmerPlaceholder(width: 180, height: 16),
                Spacer(),
                ShimmerPlaceholder(width: 40, height: 24, borderRadius: BorderRadius.all(Radius.circular(12))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
