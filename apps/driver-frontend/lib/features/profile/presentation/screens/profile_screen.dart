import 'package:auto_route/auto_route.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
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
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:uppi_motorista/features/wallet/presentation/dialogs/pix_qrcode_dialog.dart';

import '../blocs/profile.dart';

@RoutePage(name: 'DriverProfileRoute')
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  DateTime? _commissionExemptUntil;
  bool _loadingExemption = false;

  @override
  void initState() {
    locator<ProfileBloc>().load();
    _loadExemption();
    super.initState();
  }

  Future<void> _loadExemption() async {
    final supabase = Supabase.instance.client;
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    if (mounted) setState(() => _loadingExemption = true);
    try {
      final res = await supabase
          .from('profiles')
          .select('commission_exempt_until')
          .eq('id', uid)
          .maybeSingle();
      if (res != null && res['commission_exempt_until'] != null) {
        if (mounted) {
          setState(() {
            _commissionExemptUntil = DateTime.parse(res['commission_exempt_until'].toString());
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingExemption = false);
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
                  final isExempt = _commissionExemptUntil != null &&
                      _commissionExemptUntil!.isAfter(DateTime.now());

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
                    child: SingleChildScrollView(
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
                          
                          // ── Card Premium Uppi Pro (Taxa Zero) ──
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            child: _loadingExemption
                                ? const Center(child: CircularProgressIndicator())
                                : Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: isExempt
                                          ? LinearGradient(
                                              colors: [
                                                ColorPalette.primary30,
                                                ColorPalette.primary50.withOpacity(0.9),
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            )
                                          : LinearGradient(
                                              colors: [
                                                ColorPalette.neutralVariant30,
                                                ColorPalette.neutralVariant50.withOpacity(0.95),
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (isExempt ? ColorPalette.primary50 : ColorPalette.neutralVariant50)
                                              .withOpacity(0.3),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              isExempt ? Ionicons.ribbon : Ionicons.flash,
                                              color: Colors.white,
                                              size: 24,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              isExempt ? 'Uppi Pro: Taxa Zero Ativa!' : 'Seja Uppi Pro - Taxa 0%',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                fontFamily: 'Outfit',
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          isExempt
                                              ? 'A plataforma não cobrará nenhuma comissão sobre as suas corridas até ${_commissionExemptUntil!.day.toString().padLeft(2, '0')}/${_commissionExemptUntil!.month.toString().padLeft(2, '0')}/${_commissionExemptUntil!.year}. Fique com 100% dos seus ganhos!'
                                              : 'Escolha um plano de Taxa Zero para as suas corridas e fique com 100% do seu faturamento. Sem comissões para a plataforma!',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.9),
                                            fontSize: 12,
                                            height: 1.35,
                                          ),
                                        ),
                                        if (!isExempt) ...[
                                          const SizedBox(height: 14),
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.white,
                                                foregroundColor: ColorPalette.primary30,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                padding: const EdgeInsets.symmetric(vertical: 14),
                                                elevation: 0,
                                              ),
                                              onPressed: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (context) => const PixQrCodeDialog(
                                                    amount: 19.90,
                                                    currency: 'BRL',
                                                  ),
                                                );
                                              },
                                              child: const Text(
                                                'Semanal — R\$ 19,90 (7 dias)',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          SizedBox(
                                            width: double.infinity,
                                            child: OutlinedButton(
                                              style: OutlinedButton.styleFrom(
                                                side: const BorderSide(color: Colors.white, width: 1.5),
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                padding: const EdgeInsets.symmetric(vertical: 14),
                                                elevation: 0,
                                              ),
                                              onPressed: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (context) => const PixQrCodeDialog(
                                                    amount: 69.90,
                                                    currency: 'BRL',
                                                  ),
                                                );
                                              },
                                              child: const Text(
                                                'Mensal — R\$ 69,90 (30 dias)',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
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
