import 'package:flutter/material.dart';
import 'package:flutter_common/core/presentation/buttons/app_bordered_button.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:flutter_common/core/extensions/extensions.dart';
import 'package:ionicons/ionicons.dart';

class SharedDeleteAccountDialog extends StatelessWidget {
  final Future<String?> Function() onDeleteAccount;
  final VoidCallback onSuccess;

  const SharedDeleteAccountDialog({
    super.key,
    required this.onDeleteAccount,
    required this.onSuccess,
  });

  @override
  Widget build(BuildContext context) {
    return AppResponsiveDialog(
      header: (
        Ionicons.trash_bin,
        context.t.deleteAccount,
        context.t.deleteAccountNotice,
      ),
      type: context.responsive(
        DialogType.bottomSheet,
        xl: DialogType.dialog,
      ),
      primaryButton: AppBorderedButton(
        onPressed: () {
          Navigator.pop(context);
        },
        title: context.t.cancel,
      ),
      secondaryButton: AppPrimaryButton(
        onPressed: () async {
          final errorMessage = await onDeleteAccount();
          if (context.mounted) {
            if (errorMessage != null) {
              context.showSnackBar(
                message: errorMessage,
              );
            } else {
              context.showSnackBar(
                message: context.t.accountDeleted,
              );
              onSuccess();
            }
          }
        },
        color: PrimaryButtonColor.error,
        child: Text(context.t.confirmAndDeleteAccount),
      ),
      child: const SizedBox(),
    );
  }
}
