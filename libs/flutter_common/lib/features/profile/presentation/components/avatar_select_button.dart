import 'package:dartz/dartz.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/avatars/app_avatar.dart';
import 'package:ionicons/ionicons.dart';

class SharedAvatarSelectButton extends StatelessWidget {
  final Option<Either<String, String>> avatar;
  final VoidCallback onPressed;
  final String defaultAvatarPath;

  const SharedAvatarSelectButton({
    super.key,
    required this.avatar,
    required this.onPressed,
    required this.defaultAvatarPath,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.all(0),
      onPressed: onPressed,
      minimumSize: const Size(0, 0),
      child: Column(
        children: [
          AppAvatar(
            avatar: avatar,
            defaultAvatarPath: defaultAvatarPath,
            size: 80,
          ),
          Transform.translate(
            offset: const Offset(32, -32),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ColorPalette.primary99,
                border: Border.all(
                  color: ColorPalette.primary95,
                ),
              ),
              child: const Icon(
                Ionicons.add,
                color: ColorPalette.neutral70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
