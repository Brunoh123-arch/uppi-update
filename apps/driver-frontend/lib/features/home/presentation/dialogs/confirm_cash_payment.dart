import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/features/home/presentation/blocs/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/buttons/app_bordered_button.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:flutter_common/core/enums/payment_mode.dart';
import 'package:ionicons/ionicons.dart';

class ConfirmCashPayment extends StatefulWidget {
  final String orderId;
  final double amount;
  final String currency;
  final PaymentMode paymentMode;

  const ConfirmCashPayment({
    super.key,
    required this.amount,
    required this.currency,
    required this.orderId,
    required this.paymentMode,
  });

  @override
  State<ConfirmCashPayment> createState() => _ConfirmCashPaymentState();
}

class _ConfirmCashPaymentState extends State<ConfirmCashPayment> {
  final _tollController = TextEditingController();
  final _distanceController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _tollController.dispose();
    _distanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: AppResponsiveDialog(
        header: (
          widget.paymentMode == PaymentMode.pix ? Ionicons.qr_code : Ionicons.cash,
          widget.paymentMode == PaymentMode.pix ? "Pagamento em PIX" : context.translate.cashPayment,
          widget.paymentMode == PaymentMode.pix
              ? "Confirme se o pagamento em PIX de ${widget.amount.formatCurrency(widget.currency)} foi recebido e insira custos adicionais se aplicável."
              : "Confirme se o pagamento em dinheiro de ${widget.amount.formatCurrency(widget.currency)} foi recebido e insira custos adicionais se aplicável.",
        ),
        primaryButton: AppPrimaryButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              final cleanTollStr = _tollController.text.replaceAll(',', '.').trim();
              final toll = double.tryParse(cleanTollStr) ?? 0.0;

              final cleanDistStr = _distanceController.text.replaceAll(',', '.').trim();
              final kmDistance = double.tryParse(cleanDistStr);
              final actualDistanceMeters = kmDistance != null ? kmDistance * 1000.0 : null;

              locator<HomeBloc>().add(
                HomeEvent.paidInCash(
                  orderId: widget.orderId,
                  amount: widget.amount,
                  tollAmount: toll,
                  actualDistance: actualDistanceMeters,
                ),
              );
              Navigator.pop(context);
            }
          },
          child: Text(context.translate.confirmAndEndTrip),
        ),
        secondaryButton: AppBorderedButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          title: context.translate.cancel,
        ),
        type: context.responsive(DialogType.bottomSheet, xl: DialogType.dialog),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Pedágios pagos no trajeto? (Opcional)",
                  style: context.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: ColorPalette.neutral30,
                  ) ?? const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: ColorPalette.neutral30,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _tollController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    prefixText: "R\$ ",
                    hintText: "0.00",
                    hintStyle: const TextStyle(color: ColorPalette.neutral70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: ColorPalette.neutral90),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: ColorPalette.primary50, width: 2),
                    ),
                    filled: true,
                    fillColor: ColorPalette.neutral99,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final cleanVal = value.replaceAll(',', '.').trim();
                    final val = double.tryParse(cleanVal);
                    if (val == null) return "Número inválido";
                    if (val < 0) return "Não pode ser negativo";
                    if (val > 30.00) return "Limite máximo de R\$ 30,00";
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  "Distância real percorrida? (Opcional)",
                  style: context.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: ColorPalette.neutral30,
                  ) ?? const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: ColorPalette.neutral30,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _distanceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    suffixText: " km",
                    hintText: "Ex: 8.5",
                    hintStyle: const TextStyle(color: ColorPalette.neutral70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: ColorPalette.neutral90),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: ColorPalette.primary50, width: 2),
                    ),
                    filled: true,
                    fillColor: ColorPalette.neutral99,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final cleanVal = value.replaceAll(',', '.').trim();
                    final val = double.tryParse(cleanVal);
                    if (val == null) return "Número inválido";
                    if (val < 0) return "Não pode ser negativo";
                    return null;
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
