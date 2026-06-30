import 'package:dartz/dartz.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_common/features/profile/presentation/components/user_info_hero.dart';
import 'package:uppi_motorista/gen/assets.gen.dart';

/// Wrapper local do motorista que delega ao [SharedUserInfoHero] do flutter_common.
class UserInfoHero extends StatelessWidget {
  final String name;
  final Option<Either<String, String>> avatar;
  final String phoneNumber;

  const UserInfoHero({
    super.key,
    required this.name,
    required this.avatar,
    required this.phoneNumber,
  });

  @override
  Widget build(BuildContext context) {
    return SharedUserInfoHero(
      name: name,
      avatar: avatar,
      phoneNumber: phoneNumber,
      defaultAvatarPath: Assets.avatars.a1.path,
    );
  }
}
