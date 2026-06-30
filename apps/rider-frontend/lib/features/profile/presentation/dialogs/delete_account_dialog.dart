import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/features/profile/presentation/dialogs/delete_account_dialog.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/config/router/app_router.dart';
import 'package:rider_flutter/core/blocs/auth_bloc.dart';
import '../../domain/repositories/profile_repository.dart';

class DeleteAccountDialog extends StatelessWidget {
  const DeleteAccountDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return SharedDeleteAccountDialog(
      onDeleteAccount: () async {
        final result = await locator<ProfileRepository>().deleteAccount();
        return result.fold(
          (l) => l.errorMessage,
          (r) => null,
        );
      },
      onSuccess: () async {
        await context.router.replaceAll([const AuthRoute()]);
        locator<AuthBloc>().onLoggedOut();
      },
    );
  }
}
