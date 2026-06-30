import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:uppi_motorista/features/announcements/presentation/screens/announcements_screen.dart'
    as drv;
import 'package:uppi_motorista/features/auth/presentation/screens/auth_screen.dart'
    as drv;
import 'package:uppi_motorista/features/earnings/presentation/screens/earnings_screen.dart'
    as drv;
import 'package:uppi_motorista/features/home/presentation/screens/home_screen.dart'
    as drv;
import 'package:uppi_motorista/features/navigation/presentation/screens/navigation_screen.dart'
    as drv;
import 'package:uppi_motorista/features/payout_methods/presentation/screens/add_payout_account_screen.dart'
    as drv;
import 'package:uppi_motorista/features/payout_methods/presentation/screens/payout_account_list_screen.dart'
    as drv;
import 'package:uppi_motorista/features/payout_methods/presentation/screens/payout_accounts_screen.dart'
    as drv;
import 'package:uppi_motorista/features/profile/presentation/screens/driver_documents_screen.dart'
    as drv;
import 'package:uppi_motorista/features/profile/presentation/screens/edit_phone_number_screen.dart'
    as drv;
import 'package:uppi_motorista/features/profile/presentation/screens/feedbacks_summary_screen.dart'
    as drv;
import 'package:uppi_motorista/features/profile/presentation/screens/profile_info_screen.dart'
    as drv;
import 'package:uppi_motorista/features/profile/presentation/screens/profile_parent_screen.dart'
    as drv;
import 'package:uppi_motorista/features/profile/presentation/screens/profile_screen.dart'
    as drv;
import 'package:uppi_motorista/features/ride_history/presentation/screens/ride_history_details_screen.dart'
    as drv;
import 'package:uppi_motorista/features/ride_history/presentation/screens/ride_history_screen.dart'
    as drv;
import 'package:uppi_motorista/features/settings/presentation/screens/language_settings_screen.dart'
    as drv;
import 'package:uppi_motorista/features/settings/presentation/screens/map_settings_screen.dart'
    as drv;
import 'package:uppi_motorista/features/settings/presentation/screens/settings_parent_screen.dart'
    as drv;
import 'package:uppi_motorista/features/settings/presentation/screens/settings_screen.dart'
    as drv;
import 'package:uppi_motorista/features/wallet/presentation/screens/wallet_parent_screen.dart'
    as drv;
import 'package:uppi_motorista/features/wallet/presentation/screens/wallet_screen.dart'
    as drv;

import 'package:uppi_motorista/core/entities/order.dart';
import 'package:uppi_motorista/features/payout_methods/domain/entitites/payout_method.dart';

@RoutePage(name: 'DriverAuthRoute')
class DriverAuthWrapper extends StatelessWidget {
  const DriverAuthWrapper({super.key});
  @override
  Widget build(context) => const drv.AuthScreen();
}

@RoutePage(name: 'DriverNavigationRoute')
class DriverNavigationWrapper extends StatelessWidget {
  const DriverNavigationWrapper({super.key});
  @override
  Widget build(context) => const drv.NavigationScreen();
}

@RoutePage(name: 'DriverHomeRoute')
class DriverHomeWrapper extends StatelessWidget {
  const DriverHomeWrapper({super.key});
  @override
  Widget build(context) => const drv.HomeScreen();
}

@RoutePage(name: 'DriverEarningsRoute')
class DriverEarningsWrapper extends StatelessWidget {
  const DriverEarningsWrapper({super.key});
  @override
  Widget build(context) => const drv.EarningsScreen();
}

@RoutePage(name: 'DriverRideHistoryRoute')
class DriverRideHistoryWrapper extends StatelessWidget {
  const DriverRideHistoryWrapper({super.key});
  @override
  Widget build(context) => const drv.RideHistoryScreen();
}

@RoutePage(name: 'DriverRideHistoryDetailsRoute')
class DriverRideHistoryDetailsWrapper extends StatelessWidget {
  final OrderEntity entity;
  const DriverRideHistoryDetailsWrapper({super.key, required this.entity});
  @override
  Widget build(context) => drv.RideHistoryDetailsScreen(entity: entity);
}

@RoutePage(name: 'DriverAnnouncementsRoute')
class DriverAnnouncementsWrapper extends StatelessWidget {
  const DriverAnnouncementsWrapper({super.key});
  @override
  Widget build(context) => const drv.AnnouncementsScreen();
}

@RoutePage(name: 'DriverWalletParentRoute')
class DriverWalletParentWrapper extends StatelessWidget {
  const DriverWalletParentWrapper({super.key});
  @override
  Widget build(context) => const drv.WalletParentScreen();
}

@RoutePage(name: 'DriverWalletRoute')
class DriverWalletWrapper extends StatelessWidget {
  const DriverWalletWrapper({super.key});
  @override
  Widget build(context) => const drv.WalletScreen();
}

@RoutePage(name: 'DriverProfileParentRoute')
class DriverProfileParentWrapper extends StatelessWidget {
  const DriverProfileParentWrapper({super.key});
  @override
  Widget build(context) => const drv.ProfileParentScreen();
}

@RoutePage(name: 'DriverProfileRoute')
class DriverProfileWrapper extends StatelessWidget {
  const DriverProfileWrapper({super.key});
  @override
  Widget build(context) => const drv.ProfileScreen();
}

@RoutePage(name: 'DriverProfileInfoRoute')
class DriverProfileInfoWrapper extends StatelessWidget {
  const DriverProfileInfoWrapper({super.key});
  @override
  Widget build(context) => const drv.ProfileInfoScreen();
}

@RoutePage(name: 'DriverFeedbacksSummaryRoute')
class DriverFeedbacksSummaryWrapper extends StatelessWidget {
  const DriverFeedbacksSummaryWrapper({super.key});
  @override
  Widget build(context) => const drv.FeedbacksSummaryScreen();
}

@RoutePage(name: 'DriverEditPhoneNumberRoute')
class DriverEditPhoneNumberWrapper extends StatelessWidget {
  const DriverEditPhoneNumberWrapper({super.key});
  @override
  Widget build(context) => const drv.EditPhoneNumberScreen();
}

@RoutePage(name: 'DriverPayoutAccountsRoute')
class DriverPayoutAccountsWrapper extends StatelessWidget {
  const DriverPayoutAccountsWrapper({super.key});
  @override
  Widget build(context) => const drv.PayoutAccountsScreen();
}

@RoutePage(name: 'DriverDocumentsRoute')
class DriverDocumentsWrapper extends StatelessWidget {
  const DriverDocumentsWrapper({super.key});
  @override
  Widget build(context) => const drv.DriverDocumentsScreen();
}

@RoutePage(name: 'DriverPayoutAccountListRoute')
class DriverPayoutAccountListWrapper extends StatelessWidget {
  const DriverPayoutAccountListWrapper({super.key});
  @override
  Widget build(context) => const drv.PayoutAccountListScreen();
}

@RoutePage(name: 'DriverAddPayoutAccountRoute')
class DriverAddPayoutAccountWrapper extends StatelessWidget {
  final PayoutMethodEntity payoutMethod;
  const DriverAddPayoutAccountWrapper({super.key, required this.payoutMethod});
  @override
  Widget build(context) =>
      drv.AddPayoutAccountScreen(payoutMethod: payoutMethod);
}

@RoutePage(name: 'DriverSettingsParentRoute')
class DriverSettingsParentWrapper extends StatelessWidget {
  const DriverSettingsParentWrapper({super.key});
  @override
  Widget build(context) => const drv.SettingsParentScreen();
}

@RoutePage(name: 'DriverSettingsRoute')
class DriverSettingsWrapper extends StatelessWidget {
  const DriverSettingsWrapper({super.key});
  @override
  Widget build(context) => const drv.SettingsScreen();
}

@RoutePage(name: 'DriverLanguageSettingsRoute')
class DriverLanguageSettingsWrapper extends StatelessWidget {
  const DriverLanguageSettingsWrapper({super.key});
  @override
  Widget build(context) => const drv.LanguageSettingsScreen();
}

@RoutePage(name: 'DriverMapSettingsRoute')
class DriverMapSettingsWrapper extends StatelessWidget {
  const DriverMapSettingsWrapper({super.key});
  @override
  Widget build(context) => const drv.MapSettingsScreen();
}
