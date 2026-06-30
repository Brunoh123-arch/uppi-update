import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/config/constants.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/entities/payment_method_union.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:flutter_common/core/presentation/app_segmented_amount_field.dart';
import 'package:flutter_common/core/presentation/payment_method_list_view.dart';
import 'package:rider_flutter/features/wallet/presentation/blocs/top_up_wallet.dart';
import 'package:url_launcher/url_launcher_string.dart';

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
        type: context.responsive(
          DialogType.bottomSheet,
          xl: DialogType.dialog,
        ),
        onBackPressed: () => context.router.maybePop(),
        header: (Ionicons.wallet, context.translate.addCreditToWallet, null),
        primaryButton: BlocConsumer<TopUpWalletBloc, TopUpWalletState>(
          listener: (context, state) {
            state.mapOrNull(
              loaded: (loaded) {
                loaded.data.map(success: (success) {
                  context.router.maybePop();
                  locator<WalletBloc>().load();
                  context.showSnackBar(
                    message: context.translate.topUpSuccess,
                  );
                }, failure: (failure) {
                  context.showSnackBar(
                    message: 'top up failed',
                  );
                }, redirect: (redirect) {
                  launchUrlString(
                    redirect.url,
                    mode: LaunchMode.externalApplication,
                  );
                });
              },
            );
          },
          builder: (context, state) {
            return AppPrimaryButton(
              isDisabled: state.maybeMap(
                orElse: () => false,
                loading: (_) => true,
              ),
              onPressed: () {
                if (formKey.currentState?.validate() == true) {
                  formKey.currentState?.save();
                  locator<TopUpWalletBloc>().topUpWallet(
                    paymentMode: paymentMethodUnion!.paymentMode,
                    paymentMethodId: paymentMethodUnion!.id ?? "0",
                    currency: widget.currency,
                    amount: amount!,
                  );
                }
              },
              child: Text(
                context.translate.payNow,
              ),
            );
          },
        ),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.translate.selectAmount,
                style: context.titleSmall,
              ),
              const SizedBox(height: 16),
              Center(
                child: SegmentedAmountField(
                  amounts: Constants.walletPresets,
                  currency: widget.currency,
                  onAmountChanged: (value) {
                    amount = value;
                  },
                  onSaved: (value) {
                    amount = value;
                  },
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
                          color: const Color(0xFF00897B).withValues(alpha: 0.25),
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
              const Center(
                child: Text(
                  'Pagamento instantâneo • Sem taxas',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ),

              const SizedBox(height: 16),

              // Divider with "ou" text
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'ou',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),

              FormField<PaymentMethodUnion>(
                onSaved: (value) {
                  paymentMethodUnion = value;
                },
                builder: (state) {
                  return PaymentMethodListView(
                    paymentMethods: widget.paymentMethods,
                    selectedPaymentMethod: state.value,
                    onSelected: (method) {
                      state.didChange(method);
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
