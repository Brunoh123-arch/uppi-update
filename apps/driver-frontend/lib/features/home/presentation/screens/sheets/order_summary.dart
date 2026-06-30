import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/entities/order.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/features/home/presentation/blocs/home.dart';
import 'package:uppi_motorista/features/home/presentation/dialogs/confirm_cash_payment.dart';
import 'package:uppi_motorista/gen/assets.gen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:flutter_common/core/presentation/avatars/app_avatar.dart';
import 'package:flutter_common/core/presentation/buttons/app_bordered_button.dart';
import 'package:flutter_common/core/presentation/buttons/app_close_button.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/invoice/invoice.dart';
import 'package:flutter_common/core/enums/payment_mode.dart';
import 'package:ionicons/ionicons.dart';


class OrderSummary extends StatelessWidget {
  final OrderEntity order;

  const OrderSummary({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.theme.colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 150,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: Assets.images.drawerTopBackground.provider(),
                fit: BoxFit.cover,
              ),
            ),
            child: SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: order.status == OrderStatus.finished
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: AppCloseButton(
                          onPressed: () {
                            locator<HomeBloc>().add(
                              HomeEvent.onSummaryConfirmed(orderId: order.id),
                            );
                          },
                        ),
                      )
                    : const SizedBox(),
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -33),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppAvatar(
                  avatar: order.avatar,
                  defaultAvatarPath: Assets.avatars.a1.path,
                ),
                const SizedBox(height: 8),
                Text(order.riderFullName, style: context.titleMedium),
                const SizedBox(height: 4),
                Text(
                  order.serviceName,
                  style: context.bodyMedium?.copyWith(
                    color: ColorPalette.neutralVariant50,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Distância e duração da corrida finalizada
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Ionicons.map_outline,
                size: 16,
                color: ColorPalette.neutralVariant50,
              ),
              const SizedBox(width: 4),
              Text(
                order.distanceBest.toFormattedDistance(context),
                style: context.bodyMedium?.copyWith(
                  color: ColorPalette.neutralVariant50,
                ),
              ),
              const SizedBox(width: 16),
              const Icon(
                Ionicons.time_outline,
                size: 16,
                color: ColorPalette.neutralVariant50,
              ),
              const SizedBox(width: 4),
              Text(
                '${order.durationBest ~/ 60} min',
                style: context.bodyMedium?.copyWith(
                  color: ColorPalette.neutralVariant50,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Invoice(
                currency: order.currency,
                total: order.costAfterCoupon,
                items: [
                  ("Taxa de serviço", order.serviceCost),
                  ("Taxa de espera", order.waitCost),
                  ("Opções da corrida", order.rideOptionsCost),
                  ("Desconto", -(order.costBest - order.costAfterCoupon)),
                ],
              ),
            ),
          ),
          const Spacer(),
          if (order.cashPaymentAllowed)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AppPrimaryButton(
                  isDisabled: order.status == OrderStatus.finished,
                  onPressed: () {
                    showDialog(
                      context: context,
                      useSafeArea: false,
                      builder: (context) => ConfirmCashPayment(
                        orderId: order.id,
                        amount: order.costAfterCoupon,
                        currency: order.currency,
                        paymentMode: order.paymentMode,
                      ),
                    );
                  },
                  child: Text(
                    order.paymentMode == PaymentMode.pix
                        ? 'Pagamento em PIX'
                        : 'Pagamento em dinheiro',
                  ),
                ),
              ),
            ),
          if (order.cashPaymentAllowed == false)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "O pagamento ainda não foi confirmado.",
                      textAlign: TextAlign.center,
                      style: context.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    AppBorderedButton(
                      onPressed: () {
                        // Abre o chat de verdade (antes só mostrava um aviso
                        // e não levava a lugar nenhum). Ao fechar o chat, o
                        // bloc devolve para a página de pagamento.
                        locator<HomeBloc>().add(const HomeEvent.onShowChat());
                      },
                      icon: Ionicons.chatbubble_outline,
                      title: "Contatar passageiro via Chat",
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
