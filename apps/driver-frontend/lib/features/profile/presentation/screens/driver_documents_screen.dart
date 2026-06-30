import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/blocs/auth_bloc.dart';
import 'package:uppi_motorista/core/datasources/upload_datasource.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uppi_motorista/core/datasources/firebase_datasource.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/entities/media.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_top_bar.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:flutter_common/core/presentation/upload_image_field.dart';

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

class _FormCard extends StatelessWidget {
  final Widget child;

  const _FormCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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

@RoutePage(name: 'DriverDocumentsRoute')
class DriverDocumentsScreen extends StatefulWidget {
  const DriverDocumentsScreen({super.key});

  @override
  State<DriverDocumentsScreen> createState() => _DriverDocumentsScreenState();
}

class _DriverDocumentsScreenState extends State<DriverDocumentsScreen> {
  final GlobalKey<FormState> formKey = GlobalKey();
  List<MediaEntity?> documents = [null, null, null];
  bool isLoading = false;
  bool hasAgreedToPolicy = false;

  @override
  void initState() {
    super.initState();
    final authState = locator<AuthBloc>().state;
    authState.mapOrNull(
      authenticated: (authenticated) {
        final profileDocs = authenticated.profile.documents ?? [];
        for (int i = 0; i < profileDocs.length && i < 3; i++) {
          documents[i] = profileDocs[i];
        }
      },
    );
  }

  void _onSave() async {
    if (documents[0] == null || documents[1] == null) {
      context.showSnackBar(message: context.translate.fieldIsRequired);
      return;
    }

    setState(() => isLoading = true);

    try {
      final uid = locator<FirebaseDatasource>().uid;
      if (uid == null) {
        if (mounted) {
          context.showSnackBar(message: 'Motorista não autenticado.');
        }
        return;
      }

      final docsData = documents
          .where((e) => e != null)
          .map((e) => {'id': e!.id, 'address': e.address})
          .toList();

      await Supabase.instance.client.functions.invoke(
        'sync-profile',
        body: {
          'documents': docsData,
          'status': 'pending_approval', // Requer reaprovação do admin
        },
      );

      locator<AuthBloc>().requestUserInfo();

      if (mounted) {
        context.showSnackBar(
          message: context.translate.documentsSuccess,
        );
        context.router.maybePop();
      }
    } catch (e) {
      if (mounted) context.showSnackBar(message: 'Erro ao enviar documentos.');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.responsive(16, xl: 24),
            vertical: context.responsive(16, xl: 24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTopBar(
                title: context.translate.driverDocumentsTitle,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          context.translate.driverDocumentsSub,
                          style: context.bodyMedium?.copyWith(
                            color: ColorPalette.neutralVariant50,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: ColorPalette.primary99,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: ColorPalette.primary95),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Ionicons.document_text,
                                color: ColorPalette.primary40,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  context.translate.attentionDocsText,
                                  style: context.bodySmall?.copyWith(
                                    color: ColorPalette.primary40,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        _FormCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionHeader(
                                icon: Ionicons.document_text_outline,
                                title: context.translate.driverDocumentsTitle,
                              ),
                              const SizedBox(height: 24),
                              
                              // ── Slot 1: CNH ─────────────────────────────
                              _DocumentSlot(
                                label: context.translate.cnhLabel,
                                icon: Ionicons.id_card_outline,
                                value: documents[0],
                                fileUploader: locator<UploadDatasource>().uploadDocument,
                                onChanged: (newValue) async {
                                  if (newValue != null) {
                                    final oldDoc = documents[0];
                                    if (oldDoc != null && oldDoc.id.isNotEmpty) {
                                      await locator<UploadDatasource>().deleteDocument(oldDoc.id);
                                    }
                                    setState(() {
                                      documents[0] = newValue;
                                    });
                                  }
                                },
                              ),
                              const Divider(height: 40),

                              // ── Slot 2: CRLV ────────────────────────────
                              _DocumentSlot(
                                label: context.translate.crlvLabel,
                                icon: Ionicons.car_outline,
                                value: documents[1],
                                fileUploader: locator<UploadDatasource>().uploadDocument,
                                onChanged: (newValue) async {
                                  if (newValue != null) {
                                    final oldDoc = documents[1];
                                    if (oldDoc != null && oldDoc.id.isNotEmpty) {
                                      await locator<UploadDatasource>().deleteDocument(oldDoc.id);
                                    }
                                    setState(() {
                                      documents[1] = newValue;
                                    });
                                  }
                                },
                              ),
                              const Divider(height: 40),

                              // ── Slot 3: Comprovante de Residência ────────
                              _DocumentSlot(
                                label: context.translate.residenceLabel,
                                icon: Ionicons.home_outline,
                                value: documents[2],
                                fileUploader: locator<UploadDatasource>().uploadDocument,
                                onChanged: (newValue) async {
                                  if (newValue != null) {
                                    final oldDoc = documents[2];
                                    if (oldDoc != null && oldDoc.id.isNotEmpty) {
                                      await locator<UploadDatasource>().deleteDocument(oldDoc.id);
                                    }
                                    setState(() {
                                      documents[2] = newValue;
                                    });
                                  }
                                },
                              ),
                              const Divider(height: 40),
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    hasAgreedToPolicy = !hasAgreedToPolicy;
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: Checkbox(
                                          value: hasAgreedToPolicy,
                                          activeColor: ColorPalette.primary40,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          onChanged: (val) {
                                            setState(() {
                                              hasAgreedToPolicy = val ?? false;
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          context.translate.responsibilityAgreementClean,
                                          style: context.bodySmall?.copyWith(
                                            color: ColorPalette.neutralVariant40,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
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
              ),
              AppPrimaryButton(
                onPressed: (isLoading || !hasAgreedToPolicy) ? null : _onSave,
                isDisabled: isLoading || !hasAgreedToPolicy,
                child: isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(context.translate.confirm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentSlot extends StatelessWidget {
  final String label;
  final IconData icon;
  final MediaEntity? value;
  final Future<MediaEntity> Function(String) fileUploader;
  final void Function(MediaEntity?) onChanged;

  const _DocumentSlot({
    required this.label,
    required this.icon,
    required this.value,
    required this.fileUploader,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: ColorPalette.neutralVariant40),
            const SizedBox(width: 8),
            Text(
              label,
              style: context.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: ColorPalette.neutralVariant30,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 140,
          child: UploadImageField(
            initialValue: value,
            shape: BoxShape.rectangle,
            borderRadius: 12,
            onChanged: onChanged,
            uploadButtonText: context.translate.uploadImage,
            fileUploader: fileUploader,
          ),
        ),
      ],
    );
  }
}
