import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/features/profile/presentation/dialogs/delete_account_dialog.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/blocs/auth_bloc.dart';
import 'package:uppi_motorista/core/repositories/profile_repository.dart';
import 'package:uppi_motorista/core/router/app_router.dart';
import 'package:uppi_motorista/features/auth/presentation/blocs/login.dart';
import 'package:uppi_motorista/core/error/failure.dart';
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
        await context.router.replaceAll([const DriverAuthRoute()]);
        locator<AuthBloc>().onLoggedOut();
        locator<LoginBloc>().clear();
      },
    );
  }
}
