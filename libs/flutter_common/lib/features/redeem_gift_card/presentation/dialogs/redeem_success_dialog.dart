import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';

class RedeemSuccessDialog extends StatelessWidget {
  final double amount;
  final String currency;
  final Widget? animation;

  const RedeemSuccessDialog({
    super.key,
    required this.amount,
    required this.currency,
    this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return AppResponsiveDialog(
      type: context.responsive(
        DialogType.bottomSheet,
        xl: DialogType.dialog,
      ),
      header: (
        Ionicons.gift,
        context.t.redeemSuccessTitle,
        context.t.redeemSuccessDescription(amount.formatCurrency(currency)),
      ),
      primaryButton: AppPrimaryButton(
        child: Text(context.t.ok),
        onPressed: () {
          Navigator.of(context).pop();
        },
      ),
      child: animation ?? const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Icon(Ionicons.checkmark_circle, size: 80, color: Colors.green),
        ),
      ),
    );
  }
}
