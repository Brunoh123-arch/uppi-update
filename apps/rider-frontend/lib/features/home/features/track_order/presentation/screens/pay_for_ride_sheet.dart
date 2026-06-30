import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:flutter_common/core/enums/payment_mode.dart';
import 'package:flutter_common/core/utils/friendly_error.dart';
import 'package:flutter_common/core/presentation/buttons/app_close_button.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:flutter_common/core/entities/payment_method_union.dart';
import 'package:rider_flutter/core/entities/order.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/payment_method_list_view.dart';
import 'package:rider_flutter/features/home/features/track_order/presentation/blocs/track_order.dart';
import 'package:rider_flutter/features/home/features/track_order/presentation/dialogs/pay_in_cash_dialog.dart';

import 'package:rider_flutter/gen/assets.gen.dart';
import 'package:flutter_common/core/presentation/common_skeletons.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../blocs/pay_for_ride.dart';
import '../dialogs/cancel_ride_reason.dart';

class PayForRideSheet extends StatefulWidget {
  final OrderEntity order;

  const PayForRideSheet({
    super.key,
    required this.order,
  });

  @override
  State<PayForRideSheet> createState() => _SelectPaymentMethodSheetState();
}

class _SelectPaymentMethodSheetState extends State<PayForRideSheet> {
  double customCredit = 0;

  @override
  void initState() {
    locator<PayForRideCubit>().load(
      selectedPaymentMethod: widget.order.paymentMethod,
      walletCreditSufficient: widget.order.isWalletCreditSufficient,
      cashEnabled: widget.order.cashPaymentAllowed,
    );
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: locator<PayForRideCubit>(),
      child: Container(
        decoration: BoxDecoration(
          color: context.theme.scaffoldBackgroundColor,
          image: DecorationImage(
            image: Assets.images.backgroundDotted.provider(),
            alignment: Alignment.topCenter,
            fit: BoxFit.fitWidth,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          if (widget.order.status !=
                              OrderStatus.waitingForPostPay)
                            AppCloseButton(
                              onPressed: () {
                                if (widget.order.status ==
                                    OrderStatus.waitingForPrePay) {
                                  showDialog(
                                    context: context,
                                    useSafeArea: false,
                                    builder: (context) =>
                                        const CancelRideReasonDialog(),
                                  );
                                } else {
                                  locator<TrackOrderBloc>().showOverview();
                                }
                              },
                            ),
                          Center(
                            child: Text(
                              context.translate.payment,
                              style: context.titleMedium,
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 16),
                      Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 32),
                            child: DottedBorder(
                              borderType: BorderType.RRect,
                              strokeWidth: 2,
                              dashPattern: const [8, 4],
                              radius: const Radius.circular(12),
                              color: ColorPalette.primary40,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: context.theme.colorScheme.surfaceContainer,
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                child: Column(
                                  children: [
                                    // Badge Executivo Superior de Métricas Reais da Viagem
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      margin: const EdgeInsets.only(bottom: 16),
                                      decoration: BoxDecoration(
                                        color: ColorPalette.primary95,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: ColorPalette.primary80.withValues(alpha: 0.3)),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Ionicons.git_compare_outline,
                                            color: ColorPalette.primary30,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Viagem de ${widget.order.distance.toFormattedDistance(context)} ➔ Duração: ${context.translate.durationInMinutes(widget.order.duration ~/ 60)}",
                                            style: context.labelMedium?.copyWith(
                                              color: ColorPalette.primary30,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    invoiceItem(
                                      context.translate.serviceFee,
                                      widget.order.cost,
                                      widget.order.currency,
                                      Ionicons.car_sport_outline,
                                    ),
                                    const SizedBox(height: 12),
                                    invoiceItem(
                                      context.translate.serviceOptionFee,
                                      0,
                                      widget.order.currency,
                                      Ionicons.options_outline,
                                    ),
                                    const SizedBox(height: 12),
                                    invoiceItem(
                                      context.translate.couponDiscount,
                                      widget.order.couponDiscount,
                                      widget.order.currency,
                                      Ionicons.ticket_outline,
                                    ),
                                    const Divider(
                                      color: ColorPalette.neutral90,
                                      indent: 4,
                                      endIndent: 4,
                                      height: 24,
                                    ),
                                    invoiceItem(
                                      context.translate.walletCreit,
                                      widget.order.walletCredit,
                                      widget.order.currency,
                                      Ionicons.wallet_outline,
                                    ),
                                    const SizedBox(height: 8),
                                    BlocBuilder<PayForRideCubit,
                                        PayForRideState>(
                                      builder: (context, state) {
                                        final isCashOrWallet = state.maybeMap(
                                          orElse: () => false,
                                          loaded: (loaded) =>
                                              loaded.selectedPaymentMethod
                                                      .paymentMode ==
                                                  PaymentMode.cash ||
                                              loaded.selectedPaymentMethod
                                                      .paymentMode ==
                                                  PaymentMode.wallet,
                                        );
                                        if (isCashOrWallet) {
                                          return const SizedBox.shrink();
                                        }
                                        return Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: ColorPalette.neutral99,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                    color:
                                                        ColorPalette.neutral90),
                                              ),
                                              child: const Icon(
                                                Ionicons.wallet,
                                                color: ColorPalette.primary40,
                                              ),
                                            ),
                                            const SizedBox(
                                              width: 12,
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  context
                                                      .translate.walletBalance,
                                                  style: context.labelSmall,
                                                ),
                                                Text(
                                                  context.translate
                                                      .addCustomCredit,
                                                  style: context.labelMedium,
                                                ),
                                              ],
                                            ),
                                            const Spacer(),
                                            SizedBox(
                                              width: 80,
                                              child: TextField(
                                                inputFormatters: [
                                                  FilteringTextInputFormatter
                                                      .allow(RegExp(r'[0-9]')),
                                                ],
                                                onChanged: (value) => setState(
                                                  () => customCredit =
                                                      double.tryParse(value) ??
                                                          0,
                                                ),
                                                decoration: InputDecoration(
                                                  contentPadding:
                                                      const EdgeInsets.all(8),
                                                  fillColor:
                                                      ColorPalette.neutral99,
                                                  hintText:
                                                      context.translate.custom,
                                                  border: InputBorder.none,
                                                  isCollapsed: true,
                                                ),
                                                style: context.bodyMedium,
                                                keyboardType:
                                                    TextInputType.number,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 32),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 32,
                            right: 32,
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  image: DecorationImage(
                                    image:
                                        Assets.images.gradientTotal.provider(),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        context.translate.totalPrice,
                                        style: context.labelMedium?.copyWith(
                                          color: ColorPalette.neutral99,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 4,
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            (widget.order.total >= 0
                                                    ? widget.order.total
                                                    : 0.0)
                                                .formatCurrency(
                                                    widget.order.currency),
                                            style: context.titleLarge?.copyWith(
                                              color: ColorPalette.neutral99,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  color: context.theme.colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: ColorPalette.primary20.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(2, 5),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    BlocBuilder<PayForRideCubit, PayForRideState>(
                      builder: (context, state) {
                        return state.map(
                          initial: (value) => const SizedBox.shrink(),
                          loading: (value) => const PaymentMethodsSkeleton(),
                          error: (value) => Center(
                            child: Text(friendlyErrorMessage(value.failure.errorMessage)),
                          ),
                          loaded: (value) => PaymentMethodListView(
                            paymentMethods: value.paymentMethods
                                .whereNot((element) =>
                                    element.paymentMode == PaymentMode.cash &&
                                    widget.order.cashPaymentAllowed == false)
                                .toList(),
                            selectedPaymentMethod: value.selectedPaymentMethod,
                            onSelected: (method) {
                              locator<PayForRideCubit>().changePaymentMethod(
                                selectedPaymentMethod: method!,
                              );
                              if (method.paymentMode == PaymentMode.cash ||
                                  method.paymentMode == PaymentMode.wallet) {
                                setState(() {
                                  customCredit = 0;
                                });
                              }
                            },
                          ),
                        );
                      },
                    ),
                    SafeArea(
                      top: false,
                      child: BlocConsumer<PayForRideCubit, PayForRideState>(
                        listener: (context, state) {
                          state.mapOrNull(
                            loaded: (loaded) {
                              loaded.paymentStatus.mapOrNull(
                                success: (success) {
                                  if (loaded.selectedPaymentMethod
                                              .paymentMode ==
                                          PaymentMode.cash ||
                                      loaded.selectedPaymentMethod
                                              .paymentMode ==
                                          PaymentMode.wallet) {
                                    locator<TrackOrderBloc>().showOverview();
                                    return;
                                  }
                                  context.showSnackBar(
                                    message: context.translate.topUpSuccess,
                                  );
                                  locator<TrackOrderBloc>().showOverview();
                                },
                                error: (failure) {
                                  context.showSnackBar(
                                    message: failure.failure.errorMessage,
                                  );
                                },
                                redirect: (redirect) {
                                  launchUrlString(
                                    redirect.url,
                                    mode: LaunchMode.externalApplication,
                                  );
                                },
                              );
                            },
                          );
                        },
                        builder: (context, state) {
                          final isPaymentLoading = state.maybeMap(
                            loaded: (loaded) => loaded.paymentStatus is PayForRidePaymentStatusLoading,
                            orElse: () => false,
                          );
                          final isMethodsLoading = state is PayForRideLoading;

                          return AppPrimaryButton(
                            isDisabled: isMethodsLoading || isPaymentLoading,
                            onPressed: () {
                              state.mapOrNull(
                                loaded: (loaded) {
                                  if (loaded
                                          .selectedPaymentMethod.paymentMode ==
                                      PaymentMode.cash) {
                                    showDialog(
                                      context: context,
                                      useSafeArea: false,
                                      builder: (context) =>
                                          const PayInCashDialog(),
                                    );
                                    return;
                                  }
                                },
                              );
                              locator<PayForRideCubit>().pay(
                                orderId: widget.order.id,
                                currency: widget.order.currency,
                                amount: widget.order.total,
                              );
                            },
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: isPaymentLoading
                                  ? const SizedBox(
                                      key: ValueKey('pay_spinner'),
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : Text(
                                      key: const ValueKey('pay_text'),
                                      context.translate.confirmPay,
                                    ),
                            ),
                          );
                        },
                      ),
                    )
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget invoiceItem(String title, double value, String currency, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: const BoxDecoration(
            color: ColorPalette.primary95,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: ColorPalette.primary30,
            size: 16,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: context.bodyMedium?.copyWith(
            color: context.theme.colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          value.formatCurrency(currency),
          style: context.bodyMedium?.copyWith(
            color: context.theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
