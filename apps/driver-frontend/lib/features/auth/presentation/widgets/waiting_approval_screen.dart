import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:ionicons/ionicons.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/features/home/presentation/blocs/home.dart';
import 'package:flutter_common/config/constants.dart';
import 'package:auto_route/auto_route.dart' as import_auto_route;
import 'package:uppi_motorista/core/blocs/auth_bloc.dart';
import 'package:uppi_motorista/core/enums/driver_status.dart';
import 'package:uppi_motorista/core/router/app_router.dart';

class WaitingApprovalScreen extends StatefulWidget {
  const WaitingApprovalScreen({super.key});

  @override
  State<WaitingApprovalScreen> createState() => _WaitingApprovalScreenState();
}

class _WaitingApprovalScreenState extends State<WaitingApprovalScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _verificarStatus() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });

    // Dispara a recarga do perfil do motorista para checar se já foi aprovado
    locator<HomeBloc>().onStarted();

    // Pequeno feedback visual de carregamento
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    final authState = locator<AuthBloc>().state;
    final driverStatus = authState.mapOrNull(
      authenticated: (a) => a.profile.status,
    );

    final isSoftReject = driverStatus is SoftRejectState;

    final title = isSoftReject ? 'Documentos Recusados' : 'Cadastro em Análise';
    final subtitle = isSoftReject
        ? 'Alguns dos seus documentos não foram aprovados pelo administrador.\nPor favor, envie novamente os documentos corretos para análise.'
        : 'Seus documentos foram enviados com sucesso.\nNossa equipe está analisando os dados para liberar seu acesso às corridas.\n\nIsso costuma levar menos de 24 horas!';
    final iconData = isSoftReject ? Ionicons.alert_circle_outline : Ionicons.time_outline;

    final primaryGradientColor = isSoftReject ? ColorPalette.error40 : ColorPalette.primary50;
    final secondaryGradientColor = isSoftReject ? ColorPalette.error50 : ColorPalette.primary60;
    final glowColor = isSoftReject ? ColorPalette.error40 : ColorPalette.primary50;
    final circleBgColor = isSoftReject ? ColorPalette.error40.withOpacity(0.08) : ColorPalette.primary50.withOpacity(0.08);
    final circleBorderColor = isSoftReject ? ColorPalette.error40.withOpacity(0.15) : ColorPalette.primary50.withOpacity(0.15);

    return Scaffold(
      backgroundColor: isDarkMode ? ColorPalette.neutral10 : ColorPalette.neutral100,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Animated Glowing Clock/Time Icon
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: circleBgColor,
                    border: Border.all(
                      color: circleBorderColor,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            primaryGradientColor,
                            secondaryGradientColor,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: glowColor.withOpacity(0.25),
                            blurRadius: 20,
                            spreadRadius: 2,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        iconData,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 48),

              // Title
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDarkMode ? Colors.white : ColorPalette.neutral20,
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: 16),

              // Subtitle/Text explaining pending review
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: isDarkMode ? ColorPalette.neutral90 : ColorPalette.neutral50,
                    height: 1.5,
                  ),
                ),
              ),

              const Spacer(flex: 3),

              // Action Buttons
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Primary status checker button
                  ElevatedButton(
                    onPressed: isSoftReject
                        ? () => import_auto_route.AutoRouter.of(context).push(const DriverDocumentsRoute())
                        : (_isRefreshing ? null : _verificarStatus),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGradientColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: primaryGradientColor.withOpacity(0.6),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isRefreshing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            isSoftReject ? 'Corrigir Documentos' : 'Verificar Status',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                  ),

                  const SizedBox(height: 12),

                  // 2. Switch back to Passenger mode
                  OutlinedButton(
                    onPressed: () {
                      Constants.onSwitchToPassenger?.call();
                      import_auto_route.AutoRouter.of(context).replaceNamed('/');
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ColorPalette.primary50,
                      side: const BorderSide(color: ColorPalette.primary50, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Alternar para Passageiro',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
