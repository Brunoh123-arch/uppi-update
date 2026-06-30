import 'package:uppi_motorista/core/entities/order.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/features/ride_history/presentation/dialogs/report_issue_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/presentation/buttons/app_list_button.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/presentation/buttons/app_bordered_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';

import 'package:flutter_common/features/safety/presentation/dialogs/emergency_contacts_dialog.dart';
import 'send_sos_dialog.dart';

class RideSafetyDialog extends StatelessWidget {
  final OrderEntity order;

  const RideSafetyDialog({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    return AppResponsiveDialog(
      type: context.responsive(DialogType.bottomSheet, xl: DialogType.dialog),
      header: (Ionicons.shield, context.translate.rideSafety, null),
      primaryButton: AppBorderedButton(
        onPressed: () {
          Navigator.of(context).pop();
        },
        title: context.translate.goBackToRide,
      ),
      child: Column(
        children: [
          // ── Contatos de emergência do motorista ──
          AppListButton(
            icon: Ionicons.people,
            iconColor: ColorPalette.primary30,
            title: context.translate.emergencyContacts,
            subtitle: context.translate.emergencyContactsSubtitle,
            onPressed: () {
              Navigator.of(context).pop();
              showDialog(
                context: context,
                useSafeArea: false,
                builder: (_) => const EmergencyContactsDialog(),
              );
            },
          ),
          const Divider(height: 24),

          // ── SOS ──
          AppListButton(
            icon: Ionicons.shield,
            title: context.translate.sos,
            subtitle: context.translate.sosDescription,
            onPressed: () {
              Navigator.of(context).pop();
              showDialog(
                context: context,
                useSafeArea: false,
                builder: (_) => SendSOSDialog(orderId: order.id),
              );
            },
          ),
          const Divider(height: 24),

          // ── Reportar problema ──
          AppListButton(
            icon: Ionicons.warning,
            title: context.translate.reportAnIssue,
            subtitle: context.translate.reportAnIssueMidTripDescription,
            onPressed: () {
              Navigator.of(context).pop();
              showDialog(
                context: context,
                useSafeArea: false,
                builder: (context) {
                  return ReportIssueFormDialog(orderId: order.id);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
