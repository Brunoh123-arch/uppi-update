import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/buttons/app_back_button.dart';

import 'package:flutter_common/core/presentation/countup_text.dart';
import 'shared_action_buttons.dart';

class SharedWalletHeader extends StatelessWidget {
  final double? balance;
  final String? currency;
  final String? formattedPendingBalance;
  final ImageProvider backgroundImage;
  final Future<void> Function() onRedeemGiftCard;
  final VoidCallback onAddCredit;
  final VoidCallback? onWithdraw;

  const SharedWalletHeader({
    super.key,
    required this.balance,
    required this.currency,
    this.formattedPendingBalance,
    required this.backgroundImage,
    required this.onRedeemGiftCard,
    required this.onAddCredit,
    this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 32),
          decoration: BoxDecoration(
            borderRadius: context.responsive(
              BorderRadius.zero,
              xl: BorderRadius.circular(20),
            ),
            image: DecorationImage(
              image: backgroundImage,
              fit: BoxFit.cover,
            ),
          ),
          child: SafeArea(
            top: context.responsive(true, xl: false),
            bottom: false,
            child: Column(
              children: [
                context.responsive(
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppBackButton(
                      onPressed: () => context.router.maybePop(),
                    ),
                  ),
                  xl: const SizedBox(
                    height: 84,
                  ),
                ),
                Text(
                  context.t.walletBalance,
                  style: context.bodyMedium?.copyWith(
                    color: context.theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (balance != null && currency != null)
                  CountUpText(
                    begin: 0,
                    end: balance!,
                    formatValue: (val) => val.formatCurrency(currency!),
                    style: context.headlineLarge?.copyWith(
                      color: ColorPalette.primary30,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                else
                  Text(
                    "",
                    style: context.headlineLarge?.copyWith(
                      color: ColorPalette.primary30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (formattedPendingBalance != null &&
                    formattedPendingBalance!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: ColorPalette.primary30.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: ColorPalette.primary30.withValues(alpha: 0.15),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 14,
                          color: ColorPalette.primary30.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Pendente: $formattedPendingBalance",
                          style: context.bodySmall?.copyWith(
                            color: ColorPalette.primary30.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(
                  height: context.responsive(16, xl: 64),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Center(
            child: SharedActionButtons(
              onRedeemGiftCard: onRedeemGiftCard,
              onAddCredit: onAddCredit,
              onWithdraw: onWithdraw,
            ),
          ),
        ),
      ],
    );
  }
}
