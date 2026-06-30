import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:dartz/dartz.dart' hide State;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/blocs/auth_bloc.dart';
import 'package:uppi_motorista/core/blocs/route.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/avatars/app_avatar.dart';
import 'package:uppi_motorista/core/router/nav_item.dart';
import 'package:uppi_motorista/gen/assets.gen.dart';
import 'package:flutter_common/core/presentation/menu/app_drawer_item.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ionicons/ionicons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_common/config/constants.dart';
import 'package:flutter_common/features/gamification/challenges_screen.dart';
import 'package:flutter_common/features/support/support.dart';
import 'package:flutter_common/features/legal/legal.dart';
import 'package:auto_route/auto_route.dart' as import_auto_route;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class AppDrawer extends StatefulWidget {
  final bool showHeader;

  const AppDrawer({super.key, this.showHeader = true});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  ChallengeData? _topChallenge;
  DateTime? _challengeLoadedAt;

  @override
  void initState() {
    super.initState();
    _loadTopChallenge();
  }

  Future<void> _loadTopChallenge() async {
    // Cache de 10 minutos — drawer abre frequentemente
    if (_challengeLoadedAt != null &&
        DateTime.now().difference(_challengeLoadedAt!).inMinutes < 10) {
      return;
    }

    try {
      final idToken = Supabase.instance.client.auth.currentSession?.accessToken;
      if (idToken == null) throw Exception("Could not get auth token");

      final response = await http.post(
        Uri.parse('${dotenv.env['SUPABASE_URL']}/functions/v1/get-active-challenges'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'data': {}}),
      );
      final responseBody = response.body;
      final responseJson = jsonDecode(responseBody);
      final data = responseJson['result'] as Map<String, dynamic>? ?? {};

      final raw = data['challenges'] as List<dynamic>? ?? [];

      if (mounted) {
        setState(() {
          _topChallenge = raw.isNotEmpty
              ? ChallengeData.fromMap(raw.first)
              : null;
          _challengeLoadedAt = DateTime.now();
        });
      }
    } catch (_) {
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: locator<AuthBloc>()),
        BlocProvider.value(value: locator<RouteCubit>()),
      ],
      child: Container(
        width: 320,
        decoration: const BoxDecoration(
          color: ColorPalette.neutralVariant99,
          borderRadius: BorderRadius.horizontal(right: Radius.circular(30)),
        ),
        child: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            return Column(
              children: [
                if (widget.showHeader)
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(30),
                      ),
                      image: DecorationImage(
                        image: Assets.images.drawerTopBackground.provider(),
                        fit: BoxFit.cover,
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      right: false,
                      child: Container(
                        decoration: BoxDecoration(
                          color: ColorPalette.primary95,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Transform.scale(
                              scale: 1.3,
                              child: AppAvatar(
                                avatar: state.map(
                                  authenticated: (authenticated) =>
                                      authenticated.avatar,
                                  unauthenticated: (unauthenticated) => none(),
                                ),
                                defaultAvatarPath: Assets.avatars.a1.path,
                              ),
                            ),
                            const SizedBox(width: 32),
                            Expanded(
                              child: state.map(
                                unauthenticated: (_) => const SizedBox(),
                                authenticated: (authenticated) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        authenticated.profile.fullName,
                                        style: context.labelMedium,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      Text(
                                        authenticated
                                            .profile
                                            .mobileNumberFormatted,
                                        style: context.bodySmall,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      child: BlocBuilder<RouteCubit, NavItem>(
                        builder: (context, stateRoute) {
                          return Column(
                            children: [
                              context.responsive(
                                const SizedBox(),
                                xl: AppDrawerItem(
                                  icon: NavItem.home.icon,
                                  title: NavItem.home.name(context),
                                  isSelected: stateRoute == NavItem.home,
                                  onPressed: () =>
                                      NavItem.home.onPressed(context),
                                ),
                              ),
                              ...(state.isAuthenticated
                                      ? signedInNavItems.where(
                                          (element) => context.responsive(
                                            true,
                                            xl:
                                                element !=
                                                NavItem.announcements,
                                          ),
                                        )
                                      : signedOutNavItems)
                                  .map(
                                    (e) => AppDrawerItem(
                                      icon: e.icon,
                                      title: e.name(context),
                                      isSelected: stateRoute == e,
                                      onPressed: () => e.onPressed(context),
                                    ),
                                  ),

                              // ── Desafio ativo em destaque (com cache) ──
                              if (_topChallenge != null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 8,
                                    bottom: 4,
                                  ),
                                  child: ChallengeMiniCard(
                                    challenge: _topChallenge!,
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const ChallengesScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                ),

                              const Divider(height: 32, color: Colors.black12),

                              AppDrawerItem(
                                icon: Ionicons.help_circle_outline,
                                title: 'Perguntas Frequentes (FAQ)',
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const SharedFaqScreen(),
                                    ),
                                  );
                                },
                              ),
                              AppDrawerItem(
                                icon: Ionicons.help_buoy_outline,
                                title: 'Suporte',
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const SharedSupportScreen(),
                                    ),
                                  );
                                },
                              ),
                              AppDrawerItem(
                                icon: Ionicons.share_social_outline,
                                title: 'Indicar o Uppi',
                                onPressed: () {
                                  Share.share(
                                    '💰 Ganhe dinheiro dirigindo com o Uppi! Comissões justas, pagamento rápido e total liberdade. Cadastre-se: ${Constants.playStoreDriverUrl}',
                                  );
                                },
                              ),
                              AppDrawerItem(
                                icon: Ionicons.document_text_outline,
                                title: 'Termos e Privacidade',
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const SharedLegalScreen(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppDrawerItem(
                          icon: Ionicons.person_outline,
                          title: 'Alternar para Passageiro',
                          onPressed: () {
                            Constants.onSwitchToPassenger?.call();
                            import_auto_route.AutoRouter.of(
                              context,
                            ).replaceNamed('/');
                          },
                        ),
                        AppDrawerItem(
                          icon: NavItem.logout.icon,
                          title: NavItem.logout.name(context),
                          onPressed: () => NavItem.logout.onPressed(context),
                        ),
                        const SizedBox(height: 16),
                        FutureBuilder<PackageInfo>(
                          future: PackageInfo.fromPlatform(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              return Text(
                                'Uppi v${snapshot.data!.version} (${snapshot.data!.buildNumber})',
                                textAlign: TextAlign.center,
                                style: context.bodySmall?.copyWith(
                                  color: Colors.grey,
                                ),
                              );
                            }
                            return const SizedBox();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
