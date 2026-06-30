import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';

/// Diálogo de sucesso exibido após o envio de um reporte de problema.
/// Usado pelos apps rider e driver.
class SharedReportIssueSuccessDialog extends StatelessWidget {
  const SharedReportIssueSuccessDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AppResponsiveDialog(
      header: (
        Ionicons.document_text,
        context.t.reportSubmitted,
        context.t.reportSubmittedDescription,
      ),
      primaryButton: AppPrimaryButton(
        child: Text(context.t.ok),
        onPressed: () => context.router.maybePop(),
      ),
      type: context.responsive(DialogType.bottomSheet, xl: DialogType.dialog),
      child: const SizedBox(height: 100),
    );
  }
}
