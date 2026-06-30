import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:flutter_common/features/ride_history/presentation/dialogs/report_issue_form_dialog.dart';
import 'package:flutter_common/core/utils/friendly_error.dart';
import '../blocs/report_issue.dart';
import 'report_issue_success_dialog.dart';

class ReportIssueFormDialog extends StatelessWidget {
  final String orderId;

  const ReportIssueFormDialog({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    return SharedReportIssueFormDialog(
      orderId: orderId,
      subjectHint: 'Ex: Passageiro não pagou',
      onSubmit: (orderId, subject, issue) async {
        Navigator.of(context).pop();
        locator<ReportIssueCubit>().reportIssue(
          orderId: orderId,
          subject: subject,
          issue: issue,
        );
      },
      wrapWithListener: (context, child) => BlocProvider.value(
        value: locator<ReportIssueCubit>(),
        child: BlocListener<ReportIssueCubit, ReportIssueState>(
          listener: (context, state) {
            state.mapOrNull(
              error: (value) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(friendlyErrorMessage(value.errorMessage))),
                );
              },
              success: (value) {
                showDialog(
                  context: context,
                  useSafeArea: false,
                  builder: (context) => const ReportIssueSuccessDialog(),
                );
              },
            );
          },
          child: child,
        ),
      ),
    );
  }
}
