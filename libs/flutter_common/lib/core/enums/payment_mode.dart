enum PaymentMode { paymentGateway, savedPaymentMethod, cash, wallet, pix }

extension PaymentModeX on PaymentMode {
  bool get isPaid =>
      (this != PaymentMode.cash && this != PaymentMode.paymentGateway && this != PaymentMode.pix);
}
