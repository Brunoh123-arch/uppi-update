import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:uppi_motorista/features/wallet/presentation/components/payout_card.dart';
import 'package:uppi_motorista/features/wallet/presentation/components/wallet_activities.dart';
import 'package:uppi_motorista/features/wallet/presentation/components/wallet_header.dart';
import 'package:uppi_motorista/features/wallet/presentation/components/wallet_payment_method.dart';

class WalletScreenMobile extends StatelessWidget {
  const WalletScreenMobile({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      child: Column(
        children: [
          WalletHeader(),
          PayoutCard(),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: WalletPaymentMethod(),
          ),
          WalletActivities(),
        ],
      ),
    );
  }
}
