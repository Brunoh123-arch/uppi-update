import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:flutter_common/core/presentation/buttons/app_text_button.dart';

import 'redeem_success_dialog.dart';

class RedeemGiftCardDialog extends StatefulWidget {
  final Future<(double, String)> Function(String code) onRedeem;

  const RedeemGiftCardDialog({
    super.key,
    required this.onRedeem,
  });

  @override
  State<RedeemGiftCardDialog> createState() => _RedeemGiftCardDialogState();
}

class _RedeemGiftCardDialogState extends State<RedeemGiftCardDialog> {
  final _formKey = GlobalKey<FormState>();
  String _code = '';
  String? _errorMessage;
  bool _isLoading = false;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.onRedeem(_code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showDialog(
        context: context,
        useSafeArea: false,
        builder: (context) => RedeemSuccessDialog(
          amount: result.$1,
          currency: result.$2,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: AppResponsiveDialog(
        type: context.responsive(
          DialogType.bottomSheet,
          xl: DialogType.dialog,
        ),
        onBackPressed: () => context.router.maybePop(),
        header: (
          Ionicons.gift,
          context.t.redeemGiftCard,
          context.t.redeemGiftCardDescription,
        ),
        primaryButton: AppPrimaryButton(
          isDisabled: _isLoading,
          onPressed: _submit,
          child: _isLoading 
            ? const SizedBox(
                width: 20, 
                height: 20, 
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
              ) 
            : Text(context.t.redeem),
        ),
        secondaryButton: AppTextButton(
          text: context.t.cancel,
          onPressed: () {
            context.router.maybePop();
          },
        ),
        child: Form(
          key: _formKey,
          child: TextFormField(
            onChanged: (val) => setState(() {
              _code = val;
              _errorMessage = null;
            }),
            validator: (value) => value?.isEmpty == true
                ? context.t.pleaseEnterGiftCardCode
                : null,
            decoration: InputDecoration(
              errorText: _errorMessage,
              hintText: context.t.enterGiftCardCode,
              prefixIcon: Icon(
                Ionicons.gift,
                color: ColorPalette.primary30.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
