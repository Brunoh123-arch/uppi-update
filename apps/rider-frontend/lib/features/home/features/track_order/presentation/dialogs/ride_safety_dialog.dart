import 'package:flutter/material.dart';
import 'package:flutter_common/core/presentation/buttons/app_list_button.dart';
import 'package:intl/intl.dart';
import 'package:ionicons/ionicons.dart';
import 'package:rider_flutter/core/entities/order.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/buttons/app_bordered_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/features/safety/share_trip_widget.dart';
import 'package:rider_flutter/features/ride_history/presentation/dialogs/report_issue_form_dialog.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'package:flutter_common/features/safety/presentation/dialogs/emergency_contacts_dialog.dart';
import 'send_sos_dialog.dart';

class RideSafetyDialog extends StatelessWidget {
  final OrderEntity order;

  const RideSafetyDialog({
    super.key,
    required this.order,
  });

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
          // ── Compartilhar Rota com Pessoas de Confiança (Fase 17) ──
          AppListButton(
            icon: Ionicons.paper_plane_outline,
            iconColor: ColorPalette.primary30,
            title: 'Compartilhar Rota com Confiança',
            subtitle: 'Enviar link de rastreamento para seus contatos salvos',
            onPressed: () async {
              try {
                final prefs = await SharedPreferences.getInstance();
                final String? contactsJson = prefs.getString('emergency_contacts');
                if (contactsJson == null || contactsJson.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Nenhum contato de confiança cadastrado. Cadastre no botão abaixo.'),
                        backgroundColor: ColorPalette.error40,
                      ),
                    );
                  }
                  return;
                }
                final List<dynamic> decoded = jsonDecode(contactsJson);
                if (decoded.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Nenhum contato de confiança cadastrado. Cadastre no botão abaixo.'),
                        backgroundColor: ColorPalette.error40,
                      ),
                    );
                  }
                  return;
                }

                // Mensagem de segurança no azul oficial do Uppi
                final text = 'Olá! Estou viajando no Uppi e compartilhei minha rota com você para segurança. Acompanhe meu trajeto em tempo real: https://uppi.app/track/${order.id} 🚗💨';
                await Share.share(text);
              } catch (_) {}
            },
          ),
          const Divider(height: 24),
          // ── Link de rastreamento em tempo real (novo) ──
          ShareTripButton(orderId: order.id),
          const Divider(height: 24),
          ShareTripWhatsAppButton(orderId: order.id),
          const Divider(height: 24),
          // ── Compartilhamento de texto básico (existente) ──
          AppListButton(
            icon: Ionicons.share_social,
            title: context.translate.shareTripInformation,
            subtitle: context.translate.shareTripInformationDescription,
            onPressed: () {
              var text = context.translate.share_trip_text_locations(
                order.waypoints.last.address,
                order.waypoints.first.address,
              );
              if (order.driver != null) {
                text += context.translate.share_trip_text_driver(
                  order.driver!.firstName ?? "",
                  order.driver!.lastName ?? "",
                  order.driver!.mobileNumber,
                );
              }
              if (order.startedAt != null) {
                text += context.translate.share_trip_started_time(
                  DateFormat('HH:mm a').format(order.startedAt!),
                  ((order.duration / 60) + order.waitTime).ceil(),
                );
              } else {
                text += context.translate.share_trip_not_arrived_time(
                  ((order.duration / 60) + order.waitTime).ceil(),
                );
              }
              Share.share(text);
            },
          ),
          const Divider(height: 24),
          // ── Contatos de emergência (novo) ──
          AppListButton(
            icon: Ionicons.people,
            iconColor: ColorPalette.primary30,
            title: 'Contatos de emergência',
            subtitle: 'Gerenciar quem é notificado no SOS',
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
          AppListButton(
            icon: Ionicons.shield,
            title: context.translate.sos,
            subtitle: context.translate.sosDescription,
            onPressed: () {
              Navigator.of(context).pop();
              showDialog(
                context: context,
                useSafeArea: false,
                builder: (_) => SendSOSDialog(
                  orderId: order.id,
                ),
              );
            },
          ),
          const Divider(height: 24),
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
