import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:intl/intl.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/extensions/extensions.dart';
import 'package:flutter_common/l10n/messages.dart';

part 'wallet_transaction.freezed.dart';

enum WalletRechargeTransactionType {
  bankTransfer,
  gift,
  correction,
  inAppPayment,
  orderFee,
  unknown,
}

extension WalletRechargeTransactionTypeX on WalletRechargeTransactionType {
  IconData get icon {
    switch (this) {
      case WalletRechargeTransactionType.bankTransfer:
        return Ionicons.business;
      case WalletRechargeTransactionType.gift:
        return Ionicons.gift;
      case WalletRechargeTransactionType.correction:
        return Ionicons.information;
      case WalletRechargeTransactionType.inAppPayment:
        return Ionicons.card;
      case WalletRechargeTransactionType.orderFee:
        return Ionicons.cash;
      case WalletRechargeTransactionType.unknown:
        return Ionicons.information;
    }
  }

  String getTitle(BuildContext context) {
    switch (this) {
      case WalletRechargeTransactionType.bankTransfer:
        return S.of(context).bankTransfer;
      case WalletRechargeTransactionType.gift:
        return S.of(context).gift;
      case WalletRechargeTransactionType.correction:
        return S.of(context).correction;
      case WalletRechargeTransactionType.inAppPayment:
        return S.of(context).inappPayment;
      case WalletRechargeTransactionType.orderFee:
        return S.of(context).orderFee;
      case WalletRechargeTransactionType.unknown:
        final locale = Localizations.localeOf(context).languageCode;
        return locale == 'pt' ? 'Desconhecido' : 'Unknown';
    }
  }
}

enum WalletDeductTransactionType {
  orderFee,
  parkingFee,
  cancellationFee,
  withdraw,
  correction,
  commisson,
  unknown,
}

extension WalletDeductTransactionTypeX on WalletDeductTransactionType {
  IconData get icon {
    switch (this) {
      case WalletDeductTransactionType.orderFee:
        return Ionicons.car;
      case WalletDeductTransactionType.parkingFee:
        return Ionicons.car;
      case WalletDeductTransactionType.cancellationFee:
        return Ionicons.close;
      case WalletDeductTransactionType.withdraw:
        return Ionicons.cash;
      case WalletDeductTransactionType.commisson:
        return Ionicons.car;
      case WalletDeductTransactionType.correction:
      case WalletDeductTransactionType.unknown:
        return Ionicons.information;
    }
  }

  String getTitle(BuildContext context) {
    switch (this) {
      case WalletDeductTransactionType.commisson:
        final locale = Localizations.localeOf(context).languageCode;
        return locale == 'pt' ? 'Comissão' : 'Commission';
      case WalletDeductTransactionType.unknown:
        final locale = Localizations.localeOf(context).languageCode;
        return locale == 'pt' ? 'Desconhecido' : 'Unknown';
      case WalletDeductTransactionType.orderFee:
        return S.of(context).orderFee;
      case WalletDeductTransactionType.parkingFee:
        return S.of(context).parkingFee;
      case WalletDeductTransactionType.cancellationFee:
        return S.of(context).cancellationFee;
      case WalletDeductTransactionType.withdraw:
        return S.of(context).withdraw;
      case WalletDeductTransactionType.correction:
        return S.of(context).correction;
    }
  }
}

@freezed
class WalletTransactionEntity with _$WalletTransactionEntity {
  const factory WalletTransactionEntity({
    required String id,
    required DateTime dateTime,
    required String currency,
    required double amount,
    required WalletRechargeTransactionType? rechargeTransactionType,
    required WalletDeductTransactionType? deductTransactionType,
    String? description,
  }) = _WalletTransactionEntity;
}

extension WalletTransactionEntityX on WalletTransactionEntity {
  String get formattedPrice =>
      NumberFormat.simpleCurrency(name: currency).format(amount);
  String get formattedDatetime => dateTime.formatDateTime;
  String get formattedTime => dateTime.formatTime;
  IconData get icon =>
      deductTransactionType?.icon ?? rechargeTransactionType?.icon ?? Ionicons.information;
  String title(BuildContext context) =>
      deductTransactionType?.getTitle(context) ??
      rechargeTransactionType?.getTitle(context) ??
      '';
}
