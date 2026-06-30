import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/presentation/shimmer_placeholder.dart';

/// Um wrapper premium de carregamento de imagem em rede.
/// Utiliza cache de alta performance e apresenta transições suaves de fade-in com placeholders de shimmer.
class UppiCachedImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? errorWidget;

  const UppiCachedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final border = borderRadius ?? BorderRadius.circular(12);

    return ClipRRect(
      borderRadius: border,
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
        fadeInDuration: const Duration(milliseconds: 300),
        placeholder: (context, url) => ShimmerPlaceholder(
          width: width ?? double.infinity,
          height: height ?? double.infinity,
          borderRadius: border,
        ),
        errorWidget: (context, url, error) =>
            errorWidget ??
            Container(
              width: width,
              height: height,
              color: Colors.grey[300],
              child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
            ),
      ),
    );
  }
}
