import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rider_flutter/features/wallet/presentation/components/wallet_transaction_item.dart';
import 'package:flutter_common/core/presentation/common_skeletons.dart';
import 'package:flutter_common/features/wallet/presentation/components/shared_wallet_activities.dart';

import '../blocs/wallet.dart';

class WalletActivities extends StatelessWidget {
  const WalletActivities({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WalletBloc, WalletState>(
      builder: (context, state) {
        return state.map(
          initial: (_) => SharedWalletActivities(
            isLoading: true,
            activities: const [],
            loadingIndicator: const WalletActivitiesSkeleton(),
          ),
          loading: (_) => SharedWalletActivities(
            isLoading: true,
            activities: const [],
            loadingIndicator: const WalletActivitiesSkeleton(),
          ),
          loaded: (loaded) => SharedWalletActivities(
            isLoading: false,
            activities: loaded.data.transactions
                .map((e) => WalletTransactionItem(transaction: e))
                .toList(),
            loadingIndicator: const SizedBox(),
          ),
          error: (error) => SharedWalletActivities(
            isLoading: false,
            errorMessage: error.message,
            activities: const [],
            loadingIndicator: const SizedBox(),
          ),
        );
      },
    );
  }
}
