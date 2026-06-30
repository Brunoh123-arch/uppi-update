import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rider_flutter/config/router/app_router.dart';
import 'package:rider_flutter/core/blocs/app_mode_cubit.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/features/auth/presentation/blocs/onboarding_cubit.dart';
import 'package:uppi_motorista/config/locator/locator.dart' as driver_locator;
import 'package:uppi_motorista/core/blocs/auth_bloc.dart' as driver_auth
    show AuthBloc;

@RoutePage()
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _isLoading = false;

  void _selectRole(int index) async {
    if (_isLoading) return;
    debugPrint("UPPI BRASIL [RoleSelectionScreen] _selectRole selecionado: index=$index");
    setState(() {
      _isLoading = true;
    });

    try {
      if (index == 0) {
        debugPrint("UPPI BRASIL [RoleSelectionScreen] Selecionando modo Passageiro (Rider)");
        context.read<AppModeCubit>().selectRider();
        final isDone = locator<OnboardingCubit>().isDone;
        debugPrint("UPPI BRASIL [RoleSelectionScreen] Onboarding concluído? $isDone");
        if (isDone) {
          debugPrint("UPPI BRASIL [RoleSelectionScreen] Direcionando para NavigationRoute");
          context.router.replaceAll([const NavigationRoute()]);
        } else {
          debugPrint("UPPI BRASIL [RoleSelectionScreen] Direcionando para AuthRoute");
          context.router.push(const AuthRoute());
        }
      } else if (index == 1) {
        debugPrint("UPPI BRASIL [RoleSelectionScreen] Selecionando modo Motorista (Driver)");
        context.read<AppModeCubit>().selectDriver();
        // Força a instanciação do AuthBloc para rodar o construtor e iniciar o auto-restore
        final authBloc = driver_locator.locator<driver_auth.AuthBloc>();
        debugPrint("UPPI BRASIL [RoleSelectionScreen] Aguardando sessionRestored do Driver...");
        // Aguarda o AuthBloc do motorista terminar de restaurar a sessão com timeout de 3s
        await authBloc.sessionRestored.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            debugPrint("UPPI BRASIL [RoleSelectionScreen] Timeout ao aguardar sessionRestored do Driver");
            return false;
          },
        );
        if (!mounted) return;

        final isDriverAuth = authBloc.state.isAuthenticated;
        debugPrint("UPPI BRASIL [RoleSelectionScreen] Driver autenticado? $isDriverAuth");
        if (isDriverAuth) {
          debugPrint("UPPI BRASIL [RoleSelectionScreen] Direcionando para DriverNavigationRoute");
          context.router.replaceAll([const DriverNavigationRoute()]);
        } else {
          debugPrint("UPPI BRASIL [RoleSelectionScreen] Direcionando para DriverAuthRoute");
          context.router.push(const DriverAuthRoute());
        }
      }
    } catch (e) {
      debugPrint("UPPI BRASIL [RoleSelectionScreen] Erro ao selecionar perfil: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("UPPI BRASIL [RoleSelectionScreen] build chamado");
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/select_role.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              debugPrint("UPPI BRASIL [RoleSelectionScreen] Erro ao carregar select_role.png: $error");
              return Container(color: const Color(0xFF0A0A1A));
            },
          ),
          // Cliques na tela dividida (retrocompatibilidade caso a imagem tenha desenhos de botão)
          Row(
            children: [
              // Lado esquerdo: Motorista (Driver)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _selectRole(1),
                  child: const SizedBox.expand(),
                ),
              ),
              // Lado direito: Passageiro (Passenger)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _selectRole(0),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
          // Gradiente inferior para garantir contraste dos botões visíveis
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 260,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Botões premium visíveis no rodapé para uma UX excelente e intuitiva
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                  child: Text(
                    "Como você deseja utilizar o Uppi?",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      shadows: [
                        Shadow(
                          offset: const Offset(0, 2),
                          blurRadius: 4,
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                  child: Row(
                    children: [
                      // Botão Motorista (Driver)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _selectRole(1),
                          icon: const Icon(Icons.drive_eta_rounded, size: 20),
                          label: const Text(
                            "Motorista",
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6C63FF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Botão Passageiro (Passenger)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _selectRole(0),
                          icon: const Icon(Icons.person_rounded, size: 20),
                          label: const Text(
                            "Passageiro",
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF6C63FF),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
