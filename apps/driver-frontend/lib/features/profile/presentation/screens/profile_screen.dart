import 'package:auto_route/auto_route.dart';
import 'package:uppi_motorista/core/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ionicons/ionicons.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:flutter_common/core/theme/animation_duration.dart';
import 'package:uppi_motorista/core/blocs/auth_bloc.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/app_menu_item.dart';
import 'package:flutter_common/features/support/support.dart';
import 'package:uppi_motorista/features/profile/presentation/components/profile_header.dart';
import 'package:flutter_common/core/presentation/common_skeletons.dart';

import '../blocs/profile.dart';

@RoutePage(name: 'DriverProfileRoute')
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
                        top: 104,
                        left: 24,
                        right: 24,
                        bottom: 24,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        context.responsive(
                          const SizedBox(),
                          xl: SafeArea(
                            bottom: false,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Text(
                                context.translate.profile,
                                style: context.headlineSmall,
                              ),
                            ),
                          ),
                        ),
                        BlocBuilder<AuthBloc, AuthState>(
                          builder: (context, stateAuth) {
                            return stateAuth.maybeMap(
                              orElse: () => const SizedBox(),
                              authenticated: (loggedIn) {
                                return ProfileHeader(
                                  profile: loggedIn.profile,
                                  aggregationsInfo: loaded.data,
                                );
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppMenuItem(
                                icon: Ionicons.person,
                                title: context.translate.profileInfo,
                                onPressed: () {
                                  context.router.push(
                                    const DriverProfileInfoRoute(),
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              AppMenuItem(
                                icon: Ionicons.document_text,
                                title: 'Meus Documentos',
                                onPressed: () {
                                  context.router.push(
                                    const DriverDocumentsRoute(),
                                  );
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
                        ),
                      ],
                    ),
                  );
                },
                error: (error) => Center(child: Text(error.message)),
              ),
            ),
          );
        },
      ),
    );
  }
}
