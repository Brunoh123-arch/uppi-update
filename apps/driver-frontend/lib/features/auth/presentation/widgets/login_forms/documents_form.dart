import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/entities/media.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/upload_image_field.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/datasources/upload_datasource.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/features/auth/presentation/blocs/login.dart';
import 'package:uppi_motorista/features/profile/presentation/screens/face_verification_flow.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';

class DocumentsForm extends StatefulWidget {
  final LoginState state;

  const DocumentsForm({super.key, required this.state});

  @override
  State<DocumentsForm> createState() => _DocumentsFormState();
}

class _DocumentsFormState extends State<DocumentsForm> {
  final _formKey = GlobalKey<FormState>();
  
  MediaEntity? _profilePicture;
  MediaEntity? _cnh;
  MediaEntity? _crlv;
  MediaEntity? _rg;

  @override
  void initState() {
    super.initState();
    _profilePicture = widget.state.profileFullEntity?.profilePicture;
    final docs = widget.state.profileFullEntity?.documents ?? [];
    if (docs.isNotEmpty) {
      _cnh = docs[0];
    }
    if (docs.length > 1) {
      _crlv = docs[1];
    }
    if (docs.length > 2) {
      _rg = docs[2];
    }
  }

  Future<String?> _pickSelfieWithMask() async {
    final result = await Navigator.of(context).push<FaceVerificationResult>(
      MaterialPageRoute(
        builder: (context) => const FaceVerificationFlow(
          title: 'Foto de Perfil',
          isSimpleSelfie: true,
        ),
        fullscreenDialog: true,
      ),
    );

    if (result != null && result.passed) {
      try {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(
          '${tempDir.path}/selfie_onboarding_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await tempFile.writeAsBytes(result.imageBytes);
        return tempFile.path;
      } catch (e) {
        debugPrint('Erro ao gravar selfie temporária: $e');
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final loginBloc = locator<LoginBloc>();
    final uploadDatasource = locator<UploadDatasource>();

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
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
                            'Envie fotos nítidas dos seus documentos para que nosso time possa aprovar o seu cadastro rapidamente.',
                            style: context.bodySmall?.copyWith(
                              color: ColorPalette.primary40,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // 1. Foto de Perfil
                  Text(
                    'Sua Foto de Perfil (Selfie)',
                    style: context.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ColorPalette.neutralVariant30,
                    ),
                  ),
                  const SizedBox(height: 8),
                  UploadImageField(
                    initialValue: _profilePicture,
                    shape: BoxShape.circle,
                    uploadButtonText: 'Tirar/Enviar Foto',
                    fileUploader: uploadDatasource.uploadProfilePicture,
                    customPicker: _pickSelfieWithMask,
                    onChanged: (newValue) {
                      setState(() {
                        _profilePicture = newValue;
                      });
                      loginBloc.onProfilePhotoChanged(newValue);
                    },
                    validator: (value) => _profilePicture == null
                        ? 'A foto de perfil é obrigatória'
                        : null,
                  ),
                  
                  const Divider(height: 40),
                  
                  // 2. CNH
                  Text(
                    'CNH (Carteira Nacional de Habilitação)',
                    style: context.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ColorPalette.neutralVariant30,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: UploadImageField(
                      initialValue: _cnh,
                      shape: BoxShape.rectangle,
                      borderRadius: 12,
                      uploadButtonText: 'Enviar CNH',
                      fileUploader: uploadDatasource.uploadDocument,
                      onChanged: (newValue) {
                        setState(() {
                          _cnh = newValue;
                        });
                        _updateDocumentsList(loginBloc);
                      },
                      validator: (value) => _cnh == null
                          ? 'A foto da CNH é obrigatória'
                          : null,
                    ),
                  ),
                  
                  const Divider(height: 40),
                  
                  // 3. CRLV
                  Text(
                    'CRLV (Documento do Veículo)',
                    style: context.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ColorPalette.neutralVariant30,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: UploadImageField(
                      initialValue: _crlv,
                      shape: BoxShape.rectangle,
                      borderRadius: 12,
                      uploadButtonText: 'Enviar CRLV',
                      fileUploader: uploadDatasource.uploadDocument,
                      onChanged: (newValue) {
                        setState(() {
                          _crlv = newValue;
                        });
                        _updateDocumentsList(loginBloc);
                      },
                      validator: (value) => _crlv == null
                          ? 'A foto do CRLV é obrigatória'
                          : null,
                    ),
                  ),
                  
                  const Divider(height: 40),
                  
                  // 4. RG
                  Text(
                    'RG (Registro Geral / Identidade)',
                    style: context.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ColorPalette.neutralVariant30,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: UploadImageField(
                      initialValue: _rg,
                      shape: BoxShape.rectangle,
                      borderRadius: 12,
                      uploadButtonText: 'Enviar RG',
                      fileUploader: uploadDatasource.uploadDocument,
                      onChanged: (newValue) {
                        setState(() {
                          _rg = newValue;
                        });
                        _updateDocumentsList(loginBloc);
                      },
                      validator: (value) => _rg == null
                          ? 'A foto do RG é obrigatória'
                          : null,
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          AppPrimaryButton(
            onPressed: widget.state.isLoading ? null : () {
              if (_formKey.currentState?.validate() == true) {
                loginBloc.onConfirmDocumentsPressed();
              }
            },
            child: widget.state.isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Enviar para Aprovação'),
          ),
        ],
      ),
    );
  }

  void _updateDocumentsList(LoginBloc loginBloc) {
    final list = <MediaEntity>[];
    if (_cnh != null) list.add(_cnh!);
    if (_crlv != null) list.add(_crlv!);
    if (_rg != null) list.add(_rg!);
    loginBloc.setDocuments(list);
  }
}
