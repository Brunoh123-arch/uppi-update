import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_common/core/extensions/extensions.dart';
import 'package:flutter_common/core/utils/friendly_error.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/entities/media.dart';
import 'package:ionicons/ionicons.dart';

class UploadImageField extends StatefulWidget {
  final MediaEntity? initialValue;
  final void Function(MediaEntity?)? onSaved;
  final void Function(MediaEntity?)? onChanged;
  final String? Function(MediaEntity?)? validator;
  final Future<MediaEntity> Function(String) fileUploader;
  final BoxShape shape;
  final double? borderRadius;
  final String uploadButtonText;
  final Future<String?> Function()? customPicker;

  const UploadImageField({
    super.key,
    this.initialValue,
    this.onSaved,
    this.validator,
    required this.fileUploader,
    this.shape = BoxShape.circle,
    this.borderRadius,
    required this.uploadButtonText,
    this.onChanged,
    this.customPicker,
  });

  @override
  State<UploadImageField> createState() => _UploadImageFieldState();
}

class _UploadImageFieldState extends State<UploadImageField> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return FormField<MediaEntity>(
      validator: widget.validator,
      initialValue: widget.initialValue,
      onSaved: widget.onSaved,
      builder: (state) {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: widget.shape,
                borderRadius: widget.borderRadius != null
                    ? BorderRadius.circular(widget.borderRadius!)
                    : null,
                border: Border.all(color: const Color(0xffe2e8f0), width: 8),
              ),
              child: state.value != null
                  ? Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        shape: widget.shape,
                        borderRadius: widget.borderRadius != null
                            ? BorderRadius.circular(widget.borderRadius! * 0.5)
                            : null,
                      ),
                      child: CachedNetworkImage(
                        imageUrl: state.value!.address,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const CupertinoActivityIndicator(),
                        errorWidget: (context, url, error) => const Icon(Ionicons.warning_outline, color: Colors.red),
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: widget.shape,
                        borderRadius: widget.borderRadius != null
                            ? BorderRadius.circular(widget.borderRadius! * 0.5)
                            : null,
                        color: const Color(0xfff4f5fe),
                      ),
                      child: _isLoading 
                        ? const CupertinoActivityIndicator() 
                        : const Icon(
                            Ionicons.cloud_upload,
                            color: ColorPalette.primary30,
                          ),
                    ),
            ),
            const SizedBox(height: 16),
            CupertinoButton(
              minimumSize: Size.zero,
              padding: const EdgeInsets.all(0),
              onPressed: _isLoading ? null : () async {
                String? filePath;
                if (widget.customPicker != null) {
                  filePath = await widget.customPicker!();
                } else {
                  final result = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                  );
                  filePath = result?.path;
                }
                
                if (filePath != null) {
                  setState(() => _isLoading = true);
                  try {
                    final media = await widget.fileUploader(filePath);
                    state.didChange(media);
                    widget.onChanged?.call(media);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(friendlyErrorMessage(e, fallback: 'Não foi possível enviar a imagem.')),
                        ),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isLoading = false);
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: ColorPalette.primary99,
                  border: Border.all(color: ColorPalette.primary95, width: 1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _isLoading ? 'Enviando...' : widget.uploadButtonText,
                  style: context.labelMedium?.copyWith(
                    color: _isLoading 
                        ? context.theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                        : context.theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            if (state.hasError) ...[
              const SizedBox(height: 8),
              Text(
                state.errorText!,
                style: context.bodyMedium?.copyWith(
                  color: context.theme.colorScheme.error,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
