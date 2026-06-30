import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:rider_flutter/config/env.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/blocs/auth_bloc.dart';
import 'package:rider_flutter/core/blocs/route.dart';
import 'package:rider_flutter/core/entities/profile.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/avatars/app_avatar.dart';
import 'package:rider_flutter/config/router/nav_item.dart';
import 'package:rider_flutter/gen/assets.gen.dart';
import 'package:flutter_common/core/presentation/menu/app_drawer_item.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ionicons/ionicons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:auto_route/auto_route.dart';
import 'package:rider_flutter/config/router/app_router.dart';
import 'package:flutter_common/config/constants.dart';
import 'package:flutter_common/features/support/support.dart';
import 'package:flutter_common/features/legal/legal.dart';

class AppDrawer extends StatelessWidget {
  final bool showHeader;

  const AppDrawer({
    super.key,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(
          value: locator<AuthBloc>(),
        ),
        BlocProvider.value(
          value: locator<RouteCubit>(),
        ),
      ],
      child: Container(
        width: 320,
        decoration: const BoxDecoration(
          color: ColorPalette.neutralVariant99,
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(30),
          ),
        ),
        child: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            return Column(
              children: [
                if (showHeader)
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
                                defaultAvatarPath: Env.defaultAvatar,
                              ),
                            ),
                            const SizedBox(width: 32),
                            state.map(
                                unauthenticated: (_) => const SizedBox(),
                                authenticated: (authenticated) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        authenticated.profile.fullName,
                                        style: context.labelMedium,
                                      ),
                                      Text(
                                        authenticated
                                            .profile.mobileNumberFormatted,
                                        style: context.bodySmall,
                                      )
                                    ],
                                  );
                                }),
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
                                            xl: element !=
                                                NavItem.announcements,
                                          ),
                                        )
                                      : signedOutNavItems)
                                  .map(
                                (e) => AppDrawerItem(
                                  icon: e.icon,
                                  title: e.name(context),
                                  isSelected: stateRoute == e,
                                  onPressed: () {
                                    if (!context.responsive(false, xl: true)) {
                                      Navigator.of(context).pop();
                                    }
                                    e.onPressed(context);
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
                                      '🚗 Experimente o Uppi! Peça corridas com segurança, preço justo e motoristas avaliados. Baixe grátis: ${Constants.playStoreUrl}');
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
                BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
                  return state.maybeMap(
                    orElse: () => const SizedBox(),
                    authenticated: (authenticated) {
                      return SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppDrawerItem(
                                icon: Ionicons.car_sport_outline,
                                title: 'Alternar para Motorista',
                                onPressed: () {
                                  context.router
                                      .replaceAll([const RoleSelectionRoute()]);
                                },
                              ),
                              AppDrawerItem(
                                icon: NavItem.logout.icon,
                                title: NavItem.logout.name(context),
                                onPressed: () =>
                                    NavItem.logout.onPressed(context),
                              ),
                              const SizedBox(height: 16),
                              FutureBuilder<PackageInfo>(
                                future: PackageInfo.fromPlatform(),
                                builder: (context, snapshot) {
                                  if (snapshot.hasData) {
                                    return Text(
                                      'Uppi v${snapshot.data!.version} (${snapshot.data!.buildNumber})',
                                      textAlign: TextAlign.center,
                                      style: context.bodySmall
                                          ?.copyWith(color: Colors.grey),
                                    );
                                  }
                                  return const SizedBox();
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}
