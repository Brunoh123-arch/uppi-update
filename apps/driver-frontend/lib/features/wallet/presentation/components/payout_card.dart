import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/features/wallet/presentation/blocs/wallet.dart';
import 'package:uppi_motorista/features/wallet/presentation/dialogs/request_payout_dialog.dart';
import 'package:ionicons/ionicons.dart';

class PayoutCard extends StatelessWidget {
  const PayoutCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WalletBloc, WalletState>(
      builder: (context, state) {
        return state.maybeMap(
          orElse: () => const SizedBox(),
          loaded: (loaded) {
            final balance = loaded.data.balance;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: ColorPalette.primary95,
                  width: 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF32BCAD).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.pix,
                          color: Color(0xFF32BCAD),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Resgate Rápido Pix",
                              style: context.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.1,
                              ),
                            ),
                            Text(
                              "Transfira seus ganhos instantaneamente",
                              style: context.bodySmall?.copyWith(
                                color: ColorPalette.neutral40,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: balance <= 0
                            ? null
                            : () {
                                showDialog(
                                  context: context,
                                  useSafeArea: false,
                                  builder: (_) => RequestPayoutDialog(
                                    availableBalance: balance,
                                    currency: loaded.data.currency,
                                  ),
                                );
                              },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: balance <= 0
                                ? null
                                : const LinearGradient(
                                    colors: [Color(0xFF32BCAD), Color(0xFF00897B)],
                                  ),
                            color: balance <= 0 ? ColorPalette.neutral90 : null,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: balance <= 0
                                ? null
                                : [
                                    BoxShadow(
                                      color: const Color(0xFF00897B).withOpacity(0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Ionicons.cash_outline,
                                color: balance <= 0 ? ColorPalette.neutral50 : Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "Solicitar Saque",
                                style: TextStyle(
                                  color: balance <= 0 ? ColorPalette.neutral50 : Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
