import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/buttons/app_back_button.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:ionicons/ionicons.dart';

/// Cabeçalho de seção reutilizado dentro do formulário.
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ColorPalette.primary30.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: ColorPalette.primary30),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: context.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: ColorPalette.neutralVariant30,
            ),
          ),
        ],
      ),
    );
  }
}

/// Card com sombra e borda usado nos campos do formulário.
class _FormCard extends StatelessWidget {
  final Widget child;

  const _FormCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: ColorPalette.neutralVariant50.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: ColorPalette.neutralVariant50.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: ColorPalette.neutralVariant50.withValues(alpha: 0.1),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }
}

/// Diálogo de formulário para reportar um problema em uma corrida.
///
/// [orderId]: ID da corrida.
/// [onSubmit]: chamado com (orderId, subject, issue) quando o formulário é enviado.
/// [listenBloc]: widget pai que envolve o formulário com um BlocListener para
///   tratar estados de sucesso/erro — o host app injeta seu próprio cubit.
/// [subjectHint]: dica contextual para o campo de assunto.
///   Ex: `"Motorista não chegou"` para rider ou `"Passageiro não pagou"` para driver.
class SharedReportIssueFormDialog extends StatefulWidget {
  final String orderId;
  final String? subjectHint;
  final Future<void> Function(String orderId, String subject, String issue)
      onSubmit;
  final Widget Function(BuildContext context, Widget child) wrapWithListener;

  const SharedReportIssueFormDialog({
    super.key,
    required this.orderId,
    required this.onSubmit,
    required this.wrapWithListener,
    this.subjectHint,
  });

  @override
  State<SharedReportIssueFormDialog> createState() =>
      _SharedReportIssueFormDialogState();
}

class _SharedReportIssueFormDialogState
    extends State<SharedReportIssueFormDialog> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  String subject = '';
  String issueContent = '';
  String? errorText;

  @override
  Widget build(BuildContext context) {
    return widget.wrapWithListener(
      context,
      AppResponsiveDialog(
        type: context.responsive(
          DialogType.fullScreen,
          xl: DialogType.dialog,
        ),
        primaryButton: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: AppPrimaryButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              formKey.currentState!.save();
              widget.onSubmit(
                widget.orderId,
                subject,
                issueContent,
              );
            },
            color: PrimaryButtonColor.error,
            child: Text(context.t.reportThisIssue),
          ),
        ),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppBackButton(onPressed: () => context.router.maybePop()),
              const SizedBox(height: 16),
              Text(
                context.t.reportAnIssue,
                style: context.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.t.reportAnIssueMidTripDescription,
                style: context.bodyMedium?.copyWith(
                  color: ColorPalette.neutralVariant50,
                ),
              ),
              const SizedBox(height: 24),
              _FormCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(
                      icon: Ionicons.list_outline,
                      title: context.t.issueSubjectPlaceholder,
                    ),
                    TextFormField(
                      validator: (value) => value?.isEmpty == true
                          ? context.t.fieldIsRequired
                          : null,
                      initialValue: subject,
                      onChanged: (value) => setState(() => subject = value),
                      decoration: InputDecoration(
                        errorText: errorText,
                        labelText: context.t.issueSubjectPlaceholder,
                        hintText: widget.subjectHint,
                        prefixIcon: const Icon(Ionicons.alert_circle_outline),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SectionHeader(
                      icon: Ionicons.document_text_outline,
                      title: context.t.issueContentPlaceholder,
                    ),
                    TextFormField(
                      minLines: 3,
                      maxLines: 6,
                      initialValue: issueContent,
                      onChanged: (value) =>
                          setState(() => issueContent = value),
                      validator: (value) => value?.isEmpty == true
                          ? context.t.fieldIsRequired
                          : null,
                      decoration: InputDecoration(
                        labelText: context.t.issueContentPlaceholder,
                        hintText: context.t.issueContentPlaceholder,
                        alignLabelWithHint: true,
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(bottom: 60),
                          child: Icon(Ionicons.create_outline),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
