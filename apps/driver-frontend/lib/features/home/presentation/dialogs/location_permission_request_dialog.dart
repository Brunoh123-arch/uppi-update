// ignore_for_file: use_build_context_synchronously

import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/datasources/location_datasource.dart';
import 'package:uppi_motorista/core/enums/location_permission.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter/cupertino.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/buttons/app_bordered_button.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:ionicons/ionicons.dart';

class LocationPermissionRequestDialog extends StatefulWidget {
  const LocationPermissionRequestDialog({super.key});

  @override
  State<LocationPermissionRequestDialog> createState() =>
      _LocationPermissionRequestDialogState();
}

class _LocationPermissionRequestDialogState
    extends State<LocationPermissionRequestDialog> with WidgetsBindingObserver {
  bool _backgroundConsent = true; // Habilitado por padrão como recomendado
  bool _isPopped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkCurrentStatuses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkCurrentStatuses();
    }
  }

  void _safePop([dynamic result]) {
    if (!_isPopped && mounted) {
      _isPopped = true;
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _checkCurrentStatuses() async {
    final locationDatasource = locator<LocationDatasource>();
    final permission = await locationDatasource.getLocationPermissionStatus();
    final serviceEnabled = await locationDatasource.isLocationServiceEnabled();
    if ((permission == LocationPermission.always || permission == LocationPermission.whileInUse) && serviceEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _safePop(true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppResponsiveDialog(
      type: context.responsive(DialogType.bottomSheet, xl: DialogType.dialog),
      header: (
        Ionicons.location,
        context.translate.locationPermission,
        "A permissão de localização é necessária para receber corridas próximas a você e para que o passageiro acompanhe sua rota.",
      ),
      primaryButton: AppPrimaryButton(
        onPressed: () async {
          final locationDatasource = locator<LocationDatasource>();

          // Etapa 1: Solicitar permissão comum de primeiro plano (whileInUse)
          var permission = await locationDatasource.requestLocationPermission();

          if (permission == LocationPermission.deniedForever) {
            await locationDatasource.openAppSettings();
            return;
          }
          if (permission == LocationPermission.denied) {
            return;
          }

          // Etapa 2: Se o usuário deseja trabalhar em segundo plano (Modo Completo)
          if (_backgroundConsent) {
            if (permission == LocationPermission.whileInUse) {
              // Solicita a permissão de segundo plano via permission_handler,
              // que leva o usuário direto para a tela de permissão de localização do Android
              final bgStatus = await Permission.locationAlways.request();
              if (bgStatus.isGranted) {
                permission = LocationPermission.always;
              }
            }

            // A. Notificações Push (Vital para receber FCM de chamadas)
            try {
              await Permission.notification.request();
            } catch (_) {}

            // B. Ignorar Otimização de Bateria (Impede que o Android encerre o app)
            try {
              if (await Permission.ignoreBatteryOptimizations.isDenied) {
                await Permission.ignoreBatteryOptimizations.request();
              }
            } catch (_) {}

            // C. Sobreposição de Outros Apps (Permite mostrar pop-up por cima do Waze/Maps)
            try {
              if (await Permission.systemAlertWindow.isDenied) {
                await Permission.systemAlertWindow.request();
              }
            } catch (_) {}

            // D. Câmera (Necessária para validação facial e onboarding)
            try {
              if (await Permission.camera.isDenied) {
                await Permission.camera.request();
              }
            } catch (_) {}
          } else {
            // Se ele prefere apenas primeiro plano, ainda assim pedimos Notificações por ser vital
            try {
              await Permission.notification.request();
            } catch (_) {}
          }

          // Verifica se o GPS está ativo. Se não estiver, solicita ativação.
          final serviceEnabled = await locationDatasource.isLocationServiceEnabled();
          if (!serviceEnabled) {
            final serviceActivated = await locationDatasource.requestLocationService();
            if (!serviceActivated) {
              return;
            }
          }

          // Fecha com sucesso, pois temos ao menos a permissão de primeiro plano e o GPS ativo
          _safePop(true);
        },
        child: Text(context.translate.allow),
      ),
      secondaryButton: AppBorderedButton(
        onPressed: () {
          _safePop(false);
        },
        title: context.translate.cancel,
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ColorPalette.neutralVariant95,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ColorPalette.neutralVariant90,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Ionicons.notifications_circle,
                  color: ColorPalette.primary40,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Trabalhar em segundo plano?",
                    style: context.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Deseja receber novas solicitações de corridas mesmo quando o aplicativo estiver minimizado ou com a tela apagada?\n\nAo ativar, solicitaremos de forma transparente as permissões recomendadas de Notificações, Sobreposição de Tela (exibir chamadas por cima do GPS/Waze) e de Bateria para que o Uppi nunca pare de funcionar na rua.",
              style: context.bodySmall?.copyWith(
                color: ColorPalette.neutral40,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _backgroundConsent ? "Sim (Recomendado)" : "Não (Apenas primeiro plano)",
                  style: context.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _backgroundConsent
                        ? ColorPalette.semanticgreen60
                        : ColorPalette.neutral50,
                  ),
                ),
                CupertinoSwitch(
                  value: _backgroundConsent,
                  activeTrackColor: ColorPalette.primary40,
                  onChanged: (value) {
                    setState(() {
                      _backgroundConsent = value;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
