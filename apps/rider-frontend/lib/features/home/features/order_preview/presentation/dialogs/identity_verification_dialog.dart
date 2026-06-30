import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/buttons/app_bordered_button.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ionicons/ionicons.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';

/// Dialog que exige selfie e foto do RG antes de solicitar uma corrida.
/// Upload agora vai para o Supabase Storage (bucket: identity-docs).
/// Status de verificação salvo em profiles.vehicle_details['identityVerificationStatus'].
class IdentityVerificationDialog extends StatefulWidget {
  const IdentityVerificationDialog({super.key});

  @override
  State<IdentityVerificationDialog> createState() =>
      _IdentityVerificationDialogState();
}

class _IdentityVerificationDialogState
    extends State<IdentityVerificationDialog> {
  Uint8List? _selfieBytes;
  Uint8List? _rgBytes;
  String? _selfieName;
  String? _rgName;
  bool _isLoading = false;

  Future<void> _pickImage(bool isSelfie) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: isSelfie ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          if (isSelfie) {
            _selfieBytes = bytes;
            _selfieName = image.name;
          } else {
            _rgBytes = bytes;
            _rgName = image.name;
          }
        });
      }
    } catch (e) {
      // Fallback para galeria se câmera não disponível (web)
      if (isSelfie) {
        final picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 80,
        );
        if (image != null) {
          final bytes = await image.readAsBytes();
          setState(() {
            _selfieBytes = bytes;
            _selfieName = image.name;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _selfieBytes != null && _rgBytes != null;

    return AppResponsiveDialog(
      type: context.responsive(DialogType.bottomSheet, xl: DialogType.dialog),
      header: (
        Ionicons.shield_checkmark,
        'Verificação de Identidade',
        'Para sua segurança, envie uma selfie e uma foto do seu RG antes de solicitar a corrida.',
      ),
      primaryButton: AppPrimaryButton(
        isDisabled: !canConfirm || _isLoading,
        onPressed: () async {
          setState(() => _isLoading = true);
          try {
            final user = Supabase.instance.client.auth.currentUser;
            if (user == null) throw Exception('Usuário não autenticado');

            // Usa o client Supabase padrão (políticas RLS abertas para identity-docs)
            final supabase = Supabase.instance.client;
            final uid = user.id;
            final timestamp = DateTime.now().millisecondsSinceEpoch;

            // Upload Selfie → Supabase Storage (bucket: identity-docs)
            final selfiePath = 'riders/$uid/selfie_$timestamp.jpg';
            await supabase.storage.from('identity-docs').uploadBinary(
                  selfiePath,
                  _selfieBytes!,
                  fileOptions: const FileOptions(
                      contentType: 'image/jpeg', upsert: true),
                );
            final selfieUrl = await Supabase.instance.client.storage
                .from('identity-docs')
                .createSignedUrl(selfiePath, 315360000);

            // Upload RG → Supabase Storage (bucket: identity-docs)
            final rgPath = 'riders/$uid/rg_$timestamp.jpg';
            await supabase.storage.from('identity-docs').uploadBinary(
                  rgPath,
                  _rgBytes!,
                  fileOptions: const FileOptions(
                      contentType: 'image/jpeg', upsert: true),
                );
            final rgUrl = await Supabase.instance.client.storage
                .from('identity-docs')
                .createSignedUrl(rgPath, 315360000);

            // Salvar status de verificação no Supabase (colunas dedicadas em profiles)
            await supabase.functions.invoke(
              'sync-profile',
              body: {
                'identity_verification_status': 'pending',
                'identity_docs': {
                  'selfieUrl': selfieUrl,
                  'rgUrl': rgUrl,
                  'submittedAt': DateTime.now().toIso8601String(),
                },
              },
            );

            if (mounted) {
              Navigator.of(context).pop(true);
            }
          } catch (e) {
            setState(() => _isLoading = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Erro ao enviar documentos. Tente novamente.'),
                  backgroundColor: Colors.red.shade700,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        },
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Confirmar e Solicitar'),
      ),
      secondaryButton: AppBorderedButton(
        onPressed: () => Navigator.of(context).pop(false),
        title: 'Cancelar',
      ),
      child: Column(
        children: [
          _UploadCard(
            title: 'Selfie',
            subtitle: _selfieName ?? 'Tire uma foto do seu rosto',
            icon: Ionicons.camera,
            hasImage: _selfieBytes != null,
            imageBytes: _selfieBytes,
            onTap: () => _pickImage(true),
          ),
          const Divider(height: 24),
          _UploadCard(
            title: 'RG (Documento)',
            subtitle: _rgName ?? 'Envie uma foto do seu RG',
            icon: Ionicons.card,
            hasImage: _rgBytes != null,
            imageBytes: _rgBytes,
            onTap: () => _pickImage(false),
          ),
        ],
      ),
    );
  }
}

// ─── Upload Card Widget ──────────────────────────────────────────────────────

class _UploadCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool hasImage;
  final Uint8List? imageBytes;
  final VoidCallback onTap;

  const _UploadCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.hasImage,
    required this.imageBytes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasImage
                ? ColorPalette.primary60
                : ColorPalette.neutralVariant90,
            width: hasImage ? 2 : 1,
          ),
          color: hasImage
              ? ColorPalette.primary95.withValues(alpha: 0.3)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: hasImage
                    ? Colors.transparent
                    : ColorPalette.neutralVariant95,
              ),
              clipBehavior: Clip.antiAlias,
              child: hasImage && imageBytes != null
                  ? Image.memory(
                      imageBytes!,
                      fit: BoxFit.cover,
                      width: 48,
                      height: 48,
                    )
                  : Icon(
                      icon,
                      color: ColorPalette.neutral60,
                      size: 24,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: ColorPalette.neutral10,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ColorPalette.neutral60,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            hasImage
                ? const Icon(Ionicons.checkmark_circle,
                    color: ColorPalette.primary40, size: 24)
                : const Icon(Ionicons.add_circle_outline,
                    color: ColorPalette.neutral80, size: 24),
          ],
        ),
      ),
    );
  }
}
