import 'package:flutter_common/features/wallet/wallet.dart';
import 'package:flutter_common/gen/assets.gen.dart';

import '../../domain/entitites/payout_account.dart';

/// Extension to convert PayoutAccountEntity to a SavedCard widget.
/// Replaces the old GraphQL fragment-based mapper.
extension PayoutAccountProdX on PayoutAccountEntity {
  SavedCard toSavedCard({
    required Function(bool)? onDefaultChanged,
    required Function()? onDeletePressed,
  }) {
    return SavedCard(
      accountNumber: accountNumber ?? '****',
      accountHolderName: accountHolderName ?? '-',
      bankName: bankName ?? '-',
      cardImage: Assets.images.cardBackground1.provider(),
      icon: null,
      isDefault: isDefault,
      deletePressed: onDeletePressed,
      markAsDefaultPressed: onDefaultChanged,
    );
  }
}
