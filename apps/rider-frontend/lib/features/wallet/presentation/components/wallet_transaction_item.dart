import 'package:flutter/material.dart';
import 'package:flutter_common/features/wallet/presentation/components/wallet_transaction_item.dart';

import 'package:flutter_common/core/entities/wallet_transaction.dart';

class WalletTransactionItem extends StatelessWidget {
  final WalletTransactionEntity transaction;

  const WalletTransactionItem({
    super.key,
    required this.transaction,
  });

  @override
  Widget build(BuildContext context) {
    return SharedWalletTransactionItem(
      icon: transaction.icon,
      isDeduct: transaction.deductTransactionType == null,
      title: transaction.description != null && transaction.description!.isNotEmpty
          ? transaction.description!
          : transaction.title(context),
      formattedDatetime: transaction.formattedDatetime,
      formattedPrice: transaction.formattedPrice,
    );
  }
}
