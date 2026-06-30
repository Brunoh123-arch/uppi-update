import 'package:flutter/material.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/features/wallet/presentation/blocs/wallet.dart';
import 'package:rider_flutter/features/wallet/presentation/components/wallet_activities.dart';
import 'package:rider_flutter/features/wallet/presentation/components/wallet_header.dart';
import 'package:rider_flutter/features/wallet/presentation/components/wallet_payment_method.dart';
import 'package:rider_flutter/features/wallet/presentation/components/wallet_coupons.dart';
import 'package:rider_flutter/features/wallet/presentation/components/wallet_financial_chart.dart';

class WalletScreenMobile extends StatelessWidget {
  const WalletScreenMobile({super.key});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => locator<WalletBloc>().load(),
      child: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WalletHeader(),
            WalletFinancialChart(), // Fase 18: Gráficos de Finanças Executivos
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: WalletPaymentMethod(),
            ),
            WalletActivities(),
            WalletCoupons(),
          ],
        ),
      ),
    );
  }
}
