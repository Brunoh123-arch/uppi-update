import 'package:dartz/dartz.dart' hide State;
import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/avatars/app_avatar.dart';

/// Widget de cabeçalho de perfil que exibe avatar, nome e telefone.
///
/// [verificationStatus] é opcional. Quando igual a `'approved'`, exibe um
/// ícone de verificação azul ao lado do nome (útil para o app do passageiro).
class SharedUserInfoHero extends StatelessWidget {
  final String name;
  final Option<Either<String, String>> avatar;
  final String phoneNumber;
  final String defaultAvatarPath;

  /// Status de verificação de identidade. Exibe badge se == 'approved'.
  final String? verificationStatus;

  const SharedUserInfoHero({
    super.key,
    required this.name,
    required this.avatar,
    required this.phoneNumber,
    required this.defaultAvatarPath,
    this.verificationStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 50),
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: context.titleMedium?.copyWith(
                          color: ColorPalette.primary30,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (verificationStatus == 'approved') ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.verified,
                        color: Colors.blue,
                        size: 20,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  phoneNumber,
                  style: context.bodyMedium?.copyWith(
                    color: ColorPalette.neutralVariant50,
                  ),
                ),
              ],
            ),
          ),
        ),
        Center(
          child: AppAvatar(
            avatar: avatar,
            defaultAvatarPath: defaultAvatarPath,
          ),
        ),
      ],
    );
  }
}
