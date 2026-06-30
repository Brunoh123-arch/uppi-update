// ╔═══════════════════════════════════════════════════════════════════════════╗
// ║  ROTEADOR — Driver Frontend (Uppi Motorista)                            ║
// ╚═══════════════════════════════════════════════════════════════════════════╝

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

// ── Screens ──
import 'package:uppi_motorista/features/announcements/presentation/screens/announcements_screen.dart';
import 'package:uppi_motorista/features/auth/presentation/screens/auth_screen.dart';
import 'package:uppi_motorista/features/earnings/presentation/screens/earnings_screen.dart';
import 'package:uppi_motorista/features/home/presentation/screens/home_screen.dart';
import 'package:uppi_motorista/features/navigation/presentation/screens/navigation_screen.dart';

import 'package:uppi_motorista/features/payout_methods/presentation/screens/add_payout_account_screen.dart';
import 'package:uppi_motorista/features/payout_methods/presentation/screens/payout_account_list_screen.dart';
import 'package:uppi_motorista/features/payout_methods/presentation/screens/payout_accounts_screen.dart';
import 'package:uppi_motorista/features/profile/presentation/screens/driver_documents_screen.dart';
import 'package:uppi_motorista/features/profile/presentation/screens/edit_phone_number_screen.dart';
import 'package:uppi_motorista/features/profile/presentation/screens/feedbacks_summary_screen.dart';
import 'package:uppi_motorista/features/profile/presentation/screens/profile_info_screen.dart';
import 'package:uppi_motorista/features/profile/presentation/screens/profile_parent_screen.dart';
import 'package:uppi_motorista/features/profile/presentation/screens/profile_screen.dart';
import 'package:uppi_motorista/features/ride_history/presentation/screens/ride_history_details_screen.dart';
import 'package:uppi_motorista/features/ride_history/presentation/screens/ride_history_screen.dart';
import 'package:uppi_motorista/features/settings/presentation/screens/language_settings_screen.dart';
import 'package:uppi_motorista/features/settings/presentation/screens/map_settings_screen.dart';
import 'package:uppi_motorista/features/settings/presentation/screens/settings_parent_screen.dart';
import 'package:uppi_motorista/features/settings/presentation/screens/settings_screen.dart';
import 'package:uppi_motorista/features/wallet/presentation/screens/wallet_parent_screen.dart';
import 'package:uppi_motorista/features/wallet/presentation/screens/wallet_screen.dart';

// ── Entities usadas nas rotas ──
import 'package:uppi_motorista/core/entities/order.dart';
import 'package:uppi_motorista/features/payout_methods/domain/entitites/payout_method.dart';

part 'app_router.gr.dart';

@Singleton()
@AutoRouterConfig(replaceInRouteName: 'Screen|Dialog|Page,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [];
}
