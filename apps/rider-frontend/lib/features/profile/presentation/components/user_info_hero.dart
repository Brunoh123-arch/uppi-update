import 'package:dartz/dartz.dart' hide State;
import 'package:flutter/material.dart';
import 'package:flutter_common/features/profile/presentation/components/user_info_hero.dart';
import 'package:rider_flutter/config/env.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wrapper local que busca o [verificationStatus] do Supabase e delega
/// a renderização ao [SharedUserInfoHero] do flutter_common.
class UserInfoHero extends StatefulWidget {
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
  State<UserInfoHero> createState() => _UserInfoHeroState();
}

class _UserInfoHeroState extends State<UserInfoHero> {
  String? _verificationStatus;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final supabase = Supabase.instance.client;
      final uid =
          supabase.auth.currentUser?.id ?? locator<FirebaseDatasource>().uid;
      if (uid != null) {
        final profile = await supabase
            .from('profiles')
            .select('vehicle_details')
            .eq('id', uid)
            .maybeSingle();
        if (profile != null && mounted) {
          final meta = profile['vehicle_details'] as Map? ?? {};
          setState(() {
            _verificationStatus =
                meta['identityVerificationStatus']?.toString();
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SharedUserInfoHero(
      name: widget.name,
      avatar: widget.avatar,
      phoneNumber: widget.phoneNumber,
      defaultAvatarPath: Env.defaultAvatar,
      verificationStatus: _verificationStatus,
    );
  }
}
