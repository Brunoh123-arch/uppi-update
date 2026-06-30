import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';

/// Vertical timeline showing the 3 verification steps post-registration.
/// Inspired by inDrive's verification timeline but in Uppi's iOS blue style.
class VerificationTimeline extends StatelessWidget {
  final int completedSteps;

  const VerificationTimeline({
    super.key,
    this.completedSteps = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Acompanhe seu cadastro',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: ColorPalette.neutral20,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Veja o status da sua verificação',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: ColorPalette.neutral50,
          ),
        ),
        const SizedBox(height: 32),
        _TimelineStep(
          index: 1,
          isCompleted: completedSteps >= 1,
          isActive: completedSteps == 1,
          isLast: false,
          icon: Icons.description_outlined,
          title: 'Documentos enviados',
          subtitle: 'Temos todas as informações necessárias para verificar você',
        ),
        _TimelineStep(
          index: 2,
          isCompleted: completedSteps >= 2,
          isActive: completedSteps == 2,
          isLast: false,
          icon: Icons.verified_user_outlined,
          title: 'Verificação em andamento',
          subtitle: 'Você estará pronto para aceitar viagens logo após a verificação',
        ),
        _TimelineStep(
          index: 3,
          isCompleted: completedSteps >= 3,
          isActive: completedSteps == 3,
          isLast: true,
          icon: Icons.directions_car_outlined,
          title: 'Aguarde o resultado',
          subtitle: 'Nós o notificaremos em até 24 horas',
        ),
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final int index;
  final bool isCompleted;
  final bool isActive;
  final bool isLast;
  final IconData icon;
  final String title;
  final String subtitle;

  const _TimelineStep({
    required this.index,
    required this.isCompleted,
    required this.isActive,
    required this.isLast,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator column
          SizedBox(
            width: 48,
            child: Column(
              children: [
                // Circle indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCompleted
                        ? ColorPalette.primary50
                        : isActive
                            ? ColorPalette.primary95
                            : ColorPalette.neutral95,
                    border: isActive
                        ? Border.all(color: ColorPalette.primary50, width: 2)
                        : null,
                    boxShadow: isCompleted
                        ? [
                            BoxShadow(
                              color: ColorPalette.primary50.withOpacity(0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 22,
                          )
                        : Icon(
                            icon,
                            color: isActive
                                ? ColorPalette.primary50
                                : ColorPalette.neutral60,
                            size: 22,
                          ),
                  ),
                ),

                // Connecting line
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2.5,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: isCompleted
                            ? ColorPalette.primary50
                            : ColorPalette.neutral90,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isCompleted || isActive
                          ? ColorPalette.neutral20
                          : ColorPalette.neutral50,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: ColorPalette.neutral60,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
