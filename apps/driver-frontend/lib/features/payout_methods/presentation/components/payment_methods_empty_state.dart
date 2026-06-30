import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/gen/assets.gen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/presentation/empty_list_state.dart';

import '../blocs/payout_accounts.dart';
import '../dialogs/select_payout_method_dialog.dart';

class PaymentMethodsEmptyState extends StatelessWidget {
  const PaymentMethodsEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return EmptyListState(
      imagePath: Assets.images.rideHistoryEmptyState.path,
      title: context.translate.noPayoutMethods,
      buttonText: context.translate.addPayoutMethod,
      onPressed: () {
        showDialog(
          context: context,
          useSafeArea: false,
          builder: (context) => const SelectPayoutMethodDialog(),
        );
        locator<PayoutAccountsBloc>().load();
      },
    );
  }
}
