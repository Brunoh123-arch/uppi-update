import 'package:auto_route/auto_route.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/config/constants.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/entities/payment_method_union.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:flutter_common/core/presentation/app_segmented_amount_field.dart';

import '../blocs/top_up_wallet.dart';
import '../blocs/wallet.dart';
import 'pix_qrcode_dialog.dart';

class AddCreditDialog extends StatefulWidget {
  final List<PaymentMethodUnion> paymentMethods;
  final String currency;

  const AddCreditDialog({
    super.key,
    required this.paymentMethods,
    required this.currency,
  });

  @override
  State<AddCreditDialog> createState() => _AddCreditDialogState();
}

class _AddCreditDialogState extends State<AddCreditDialog> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  double? amount;
  PaymentMethodUnion? paymentMethodUnion;

  void _openPixPayment() {
    if (formKey.currentState?.validate() != true) return;
    formKey.currentState?.save();
    if (amount == null || amount! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um valor primeiro')),
      );
      return;
    }

    // Captura referências antes do gap assíncrono
    final router = context.router;
    final messenger = ScaffoldMessenger.of(context);

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          PixQrCodeDialog(amount: amount!, currency: widget.currency),
    ).then((result) {
      if (result == true) {
        // Payment was confirmed, refresh wallet and close
        locator<WalletBloc>().load();
        router.maybePop();
        messenger.showSnackBar(
          const SnackBar(content: Text('Recarga PIX confirmada com sucesso!')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: locator<TopUpWalletBloc>(),
      child: AppResponsiveDialog(
        type: context.responsive(DialogType.bottomSheet, xl: DialogType.dialog),
        onBackPressed: () => context.router.maybePop(),
        header: (Ionicons.wallet, context.translate.addCreditToWallet, null),
        primaryButton: null,
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.translate.selectAmount, style: context.titleSmall),
              const SizedBox(height: 16),
              Center(
                child: SegmentedAmountField(
                  amounts: Constants.walletPresets,
                  currency: widget.currency,
                  onAmountChanged: (value) => amount = value,
                  onSaved: (value) => amount = value,
                ),
              ),
              const SizedBox(height: 20),

              // ======= PIX PAYMENT BUTTON (Paradise Pags) =======
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _openPixPayment,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF32BCAD), Color(0xFF00897B)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00897B).withOpacity(0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.pix, color: Colors.white, size: 22),
                        SizedBox(width: 10),
                        Text(
                          'Pagar com PIX',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.white70,
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Pagamento instantâneo • Sem taxas',
                  style: TextStyle(color: ColorPalette.neutral60, fontSize: 12),
                ),
              ),


            ],
          ),
        ),
      ),
    );
  }
}
