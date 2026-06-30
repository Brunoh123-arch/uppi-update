import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter_common/features/wallet/presentation/components/shared_wallet_header.dart';
import 'package:uppi_motorista/features/wallet/presentation/blocs/wallet.dart';
import 'package:uppi_motorista/gen/assets.gen.dart';
import 'package:uppi_motorista/features/redeem_gift_card/domain/repositories/redeem_gift_card_repository.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:flutter/material.dart';
import 'package:uppi_motorista/features/wallet/presentation/dialogs/add_credit_dialog.dart';
import 'package:flutter_common/core/entities/payment_method_union.dart';
import 'package:flutter_common/features/redeem_gift_card/presentation/dialogs/redeem_gift_card_dialog.dart';

class WalletHeader extends StatelessWidget {
  const WalletHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WalletBloc, WalletState>(
      builder: (context, state) {
        final rawBalance = state.maybeMap(
          orElse: () => null,
          loaded: (state) => state.data.balance,
        );

        final currency = state.maybeMap(
          orElse: () => null,
          loaded: (state) => state.data.currency,
        );

        final formattedPendingBalance = state.maybeMap(
          orElse: () => null,
          loaded: (state) => state.data.pendingBalance?.formatCurrency(state.data.currency),
        );

        return SharedWalletHeader(
          balance: rawBalance,
          currency: currency,
          formattedPendingBalance: formattedPendingBalance,
          backgroundImage: Assets.images.walletHeaderBackground.provider(),
          onRedeemGiftCard: () async {
            final giftDialogResult = await showDialog(
              context: context,
              useSafeArea: false,
              builder: (context) => RedeemGiftCardDialog(
                onRedeem: (code) async {
                  final repo = locator<RedeemGiftCardRepository>();
                  final result = await repo.redeemGiftCard(code: code);
                  return result.fold(
                    (l) => throw Exception(l.errorMessage),
                    (r) => r,
                  );
                },
              ),
            );
            if (giftDialogResult == true) {
              locator<WalletBloc>().load();
            }
          },
          onAddCredit: () {
            locator<WalletBloc>().state.maybeMap(
              orElse: () {},
              loaded: (loaded) {
                showDialog(
                  context: context,
                  useSafeArea: false,
                  builder: (context) => AddCreditDialog(
                    currency: loaded.data.currency,
                    paymentMethods: (
                      loaded.data.paymentGateways,
                      loaded.data.savedPaymentMethods
                    ).toPaymentMethodUnion,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
