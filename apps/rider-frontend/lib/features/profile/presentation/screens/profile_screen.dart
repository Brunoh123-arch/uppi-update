import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/buttons/app_text_button.dart';
import 'package:ionicons/ionicons.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/config/router/app_router.dart';
import 'package:flutter_common/core/theme/animation_duration.dart';
import 'package:rider_flutter/core/blocs/auth_bloc.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/app_menu_item.dart';
import 'package:flutter_common/features/support/support.dart';
import 'package:rider_flutter/features/profile/presentation/components/profile_header.dart';
import 'package:flutter_common/core/presentation/common_skeletons.dart';

import '../blocs/profile.dart';

@RoutePage()
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    locator<ProfileBloc>().load();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
        value: locator<ProfileBloc>(),
        child: BlocBuilder<ProfileBloc, ProfileState>(
          builder: (context, state) {
            return Container(
              color: context.theme.scaffoldBackgroundColor,
              child: AnimatedSwitcher(
                duration: AnimationDuration.pageStateTransitionMobile,
                child: state.map(
                  initial: (initial) => const SizedBox(),
                  loading: (loading) => const ProfileSkeleton(),
                  loaded: (loaded) {
                    return Container(
                      padding: context.responsive(
                        null,
                        xl: const EdgeInsets.only(
                            top: 104, left: 24, right: 24, bottom: 24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          context.responsive(
                            const SizedBox(),
                            xl: Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Text(
                                context.translate.profile,
                                style: context.headlineSmall,
                              ),
                            ),
                          ),
                          BlocBuilder<AuthBloc, AuthState>(
                            builder: (context, stateAuth) {
                              return ProfileHeader(
                                profile: stateAuth.maybeMap(
                                    orElse: () => throw Exception(),
                                    authenticated: (loggedIn) {
                                      return loggedIn.profile;
                                    }),
                                aggregationsInfo: loaded.data,
                              );
                            },
                          ),
                          const SizedBox(
                            height: 24,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppMenuItem(
                                  icon: Ionicons.person,
                                  title: context.translate.profileInfo,
                                  onPressed: () {
                                    context.router
                                        .push(const ProfileInfoRoute());
                                  },
                                ),
                                const SizedBox(height: 16),
                                AppMenuItem(
                                  icon: Ionicons.document_text,
                                  title: 'Meus Documentos',
                                  onPressed: () {
                                    context.router.push(const DocumentsRoute());
                                  },
                                ),
                                const SizedBox(height: 16),
                                AppMenuItem(
                                  icon: Ionicons.heart,
                                  title: context.translate.favoriteLocations,
                                  onPressed: () {
                                    context.router
                                        .push(const FavoriteLocationsRoute());
                                  },
                                ),
                                const SizedBox(height: 16),
                                AppMenuItem(
                                  icon: Ionicons.star,
                                  title: context.translate.favoriteDrivers,
                                  onPressed: () {
                                    context.router
                                        .push(const FavoriteDriversRoute());
                                  },
                                ),
                                const SizedBox(height: 16),
                                AppMenuItem(
                                  icon: Ionicons.help_circle,
                                  title: 'Perguntas Frequentes (FAQ)',
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const SharedFaqScreen(),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 16),
                                AppMenuItem(
                                  icon: Ionicons.help_buoy,
                                  title: 'Suporte',
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const SharedSupportScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          )
                        ],
                      ),
                    );
                  },
                  error: (error) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Ionicons.alert_circle_outline, size: 48, color: ColorPalette.error40),
                        const SizedBox(height: 12),
                        Text(error.message, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        AppTextButton(
                          onPressed: () => locator<ProfileBloc>().load(),
                          text: 'Tentar novamente',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ));
  }
}
