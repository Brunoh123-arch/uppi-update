import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/presentation/buttons/app_bordered_button.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ionicons/ionicons.dart';

class BackgroundLocationPermissionDeniedDialog extends StatelessWidget {
  const BackgroundLocationPermissionDeniedDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AppResponsiveDialog(
      type: context.responsive(DialogType.bottomSheet, xl: DialogType.dialog),
      header: (
        Ionicons.location,
        "Localização em Segundo Plano",
        "Para receber novas solicitações de corridas mesmo com o aplicativo minimizado ou com a tela apagada, é necessário autorizar a localização em segundo plano nas configurações do celular.\n\nPor favor, mude a permissão de localização do Uppi para 'Permitir o tempo todo'.",
      ),
      primaryButton: AppPrimaryButton(
        onPressed: () async {
          Navigator.of(context).pop();
          // Solicita diretamente a permissão em segundo plano.
          // No Android 10+, se a permissão de primeiro plano já estiver concedida,
          // isso redireciona o usuário DIRETAMENTE para a tela de "Permissões de Localização" do sistema.
          final status = await Permission.locationAlways.request();
          if (status.isPermanentlyDenied || status.isDenied) {
            // Se estiver permanentemente negado ou recusado, abre a tela de configurações gerais do app como fallback.
            await openAppSettings();
          }
        },
        child: const Text("Abrir Configurações"),
      ),
      secondaryButton: AppBorderedButton(
        onPressed: () {
          Navigator.of(context).pop();
        },
        title: context.translate.cancel,
      ),
      child: const SizedBox.shrink(),
    );
  }
}
