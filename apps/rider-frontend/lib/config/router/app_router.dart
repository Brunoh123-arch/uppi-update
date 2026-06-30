import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import 'package:auto_route/auto_route.dart';

// ── Rider screens ──────────────────────────────────────────────────────────
import 'package:rider_flutter/core/entities/favorite_location.dart';
import 'package:rider_flutter/core/entities/order_compact.dart';
import 'package:rider_flutter/core/enums/address_type.dart';
import 'package:rider_flutter/features/announcements/presentation/screens/announcements_screen.dart';
import 'package:rider_flutter/features/auth/presentation/screens/auth_screen.dart';
import 'package:rider_flutter/features/auth/presentation/screens/onboarding_screen.mobile.dart';
import 'package:rider_flutter/features/auth/presentation/screens/role_selection_screen.dart';
import 'package:rider_flutter/features/auth/presentation/screens/splash_screen.dart';
import 'package:rider_flutter/features/favorite_locations/presentation/screens/add_screen.dart';
import 'package:rider_flutter/features/favorite_locations/presentation/screens/edit_screen.dart';
import 'package:rider_flutter/features/favorite_locations/presentation/screens/list_screen.dart';
import 'package:rider_flutter/features/favorite_locations/presentation/screens/favorite_locations_screen.dart';
import 'package:rider_flutter/features/favorite_locations/presentation/screens/locate_screen.dart';
import 'package:rider_flutter/features/home/presentation/screens/home_screen.dart';
import 'package:rider_flutter/features/navigation/presentation/screens/navigation_screen.dart';
import 'package:rider_flutter/features/payment_methods/presentation/screens/payment_methods_screen.dart';
import 'package:rider_flutter/features/profile/presentation/screens/edit_phone_number_screen.dart';
import 'package:rider_flutter/features/profile/presentation/screens/favorite_drivers_screen.dart';
import 'package:rider_flutter/features/profile/presentation/screens/profile_info_screen.dart';
import 'package:rider_flutter/features/profile/presentation/screens/profile_parent_screen.dart';
import 'package:rider_flutter/features/profile/presentation/screens/profile_screen.dart';
import 'package:rider_flutter/features/profile/presentation/screens/documents_screen.dart';
import 'package:rider_flutter/features/ride_history/presentation/screens/ride_history_details_screen.dart';
import 'package:rider_flutter/features/ride_history/presentation/screens/ride_history_screen.dart';
import 'package:rider_flutter/features/scheduled_rides/presentation/screens/scheduled_ride_details_screen.dart';
import 'package:rider_flutter/features/scheduled_rides/presentation/screens/scheduled_rides_screen.dart';
import 'package:rider_flutter/features/settings/presentation/screens/language_settings_screen.dart';
import 'package:rider_flutter/features/settings/presentation/screens/map_settings_screen.dart';
import 'package:rider_flutter/features/settings/presentation/screens/settings_parent_screen.dart';
import 'package:rider_flutter/features/settings/presentation/screens/settings_screen.dart';
import 'package:rider_flutter/features/wallet/presentation/screens/wallet_parent_screen.dart';
import 'package:rider_flutter/features/wallet/presentation/screens/wallet_screen.dart';

// ── Driver screens — importados diretamente via wrappers ─────────
import 'package:rider_flutter/features/driver/presentation/screens/driver_wrappers_screen.dart';
import 'package:uppi_motorista/core/entities/order.dart';
import 'package:uppi_motorista/features/payout_methods/domain/entitites/payout_method.dart';

import 'onboarding_guard.dart';
import 'driver_mode_guard.dart';
import 'auth_guard.dart';
import 'driver_auth_guard.dart';
import 'package:rider_flutter/features/auth/presentation/screens/lgpd_consent_wrapper_screen.dart';

part 'app_router.gr.dart';

@Singleton()
@AutoRouterConfig(replaceInRouteName: 'Screen|Dialog|Page,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
        // ── Onboarding (Primeiro uso) ───────────────────────────────────────
        AutoRoute(
          page: OnboardingRoute.page,
          path: '/onboarding',
        ),

        // ── LGPD Consent ────────────────────────────────────────────────────
        AutoRoute(
          page: LgpdConsentWrapperRoute.page,
          path: '/lgpd-consent',
        ),

        // ── Splash Screen (Verifica AppMode salvo) ──────────────────────────
        AutoRoute(
          page: SplashRoute.page,
          path: '/',
          initial: true,
        ),

        // ── Selecao de modo (tela inicial se n tem modo salvo) ──────────────
        AutoRoute(
          page: RoleSelectionRoute.page,
          path: '/role-selection',
          guards: [OnboardingGuard()],
        ),

        // ── Auth do rider ────────────────────────────────────────────────────
        AutoRoute(page: AuthRoute.page, path: '/auth'),

        // ── Auth do driver (tela propria) ────────────────────────────────────
        AutoRoute(page: DriverAuthRoute.page, path: '/driver-auth'),

        // ── App do PASSAGEIRO ─────────────────────────────────────────────────
        AutoRoute(
          path: '/passenger',
          page: NavigationRoute.page,
          guards: [OnboardingGuard(), AuthGuard()],
          children: [
            AutoRoute(page: HomeRoute.page, path: 'home', initial: true),
            AutoRoute(
              page: ProfileParentRoute.page,
              path: 'profile',
              children: [
                AutoRoute(page: ProfileRoute.page, path: '', initial: true),
                AutoRoute(page: ProfileInfoRoute.page, path: 'info'),
                AutoRoute(
                    page: EditPhoneNumberRoute.page, path: 'edit-phone-number'),
                AutoRoute(
                    page: FavoriteDriversRoute.page, path: 'favorite-drivers'),
                AutoRoute(page: DocumentsRoute.page, path: 'documents'),
              ],
            ),
            AutoRoute(page: AnnouncementsRoute.page, path: 'announcements'),
            AutoRoute(
              page: WalletParentRoute.page,
              path: 'wallet',
              children: [
                AutoRoute(page: WalletRoute.page, path: '', initial: true),
                AutoRoute(
                    page: PaymentMethodsRoute.page, path: 'payment-methods'),
              ],
            ),
            AutoRoute(
              page: FavoriteLocationsRoute.page,
              path: 'favorite-locations',
              children: [
                AutoRoute(
                    page: FavoriteLocationsListRoute.page,
                    path: '',
                    initial: true),
                AutoRoute(page: AddFavoriteLocationRoute.page, path: 'add'),
                AutoRoute(page: EditFavoriteLocationRoute.page, path: 'edit'),
                AutoRoute(
                    page: LocateFavoriteLocationRoute.page, path: 'locate'),
              ],
            ),
            AutoRoute(page: ScheduledRidesRoute.page, path: 'scheduled-rides'),
            AutoRoute(
                page: ScheduledRideDetailsRoute.page,
                path: 'scheduled-rides/details'),
            AutoRoute(page: RideHistoryRoute.page, path: 'ride-history'),
            AutoRoute(
                page: RideHistoryDetailsRoute.page,
                path: 'ride-history/details'),
            AutoRoute(
              page: SettingsParentRoute.page,
              path: 'settings',
              children: [
                AutoRoute(page: SettingsRoute.page, path: '', initial: true),
                AutoRoute(page: MapSettingsRoute.page, path: 'map'),
                AutoRoute(page: LanguageSettingsRoute.page, path: 'language'),
              ],
            ),
          ],
        ),

        // ── App do MOTORISTA — unico MaterialApp, guard verifica modo ─────────
        AutoRoute(
          path: '/driver',
          page: DriverNavigationRoute.page,
          guards: [DriverModeGuard(), DriverAuthGuard()],
          children: [
            AutoRoute(page: DriverHomeRoute.page, path: 'home', initial: true),
            AutoRoute(page: DriverEarningsRoute.page, path: 'earnings'),
            AutoRoute(page: DriverRideHistoryRoute.page, path: 'ride-history'),
            AutoRoute(
                page: DriverRideHistoryDetailsRoute.page,
                path: 'ride-history/details'),
            AutoRoute(
                page: DriverAnnouncementsRoute.page, path: 'announcements'),
            AutoRoute(
              page: DriverWalletParentRoute.page,
              path: 'wallet',
              children: [
                AutoRoute(
                    page: DriverWalletRoute.page, path: '', initial: true),
              ],
            ),
            AutoRoute(
              page: DriverProfileParentRoute.page,
              path: 'profile',
              children: [
                AutoRoute(
                    page: DriverProfileRoute.page, path: '', initial: true),
                AutoRoute(page: DriverProfileInfoRoute.page, path: 'info'),
                AutoRoute(
                    page: DriverFeedbacksSummaryRoute.page,
                    path: 'feedbacks-summary'),
                AutoRoute(
                    page: DriverEditPhoneNumberRoute.page,
                    path: 'phone-number'),
                AutoRoute(
                    page: DriverPayoutAccountsRoute.page,
                    path: 'payout-accounts'),
                AutoRoute(page: DriverDocumentsRoute.page, path: 'documents'),
                AutoRoute(
                    page: DriverPayoutAccountListRoute.page,
                    path: 'payout-accounts-list'),
                AutoRoute(
                    page: DriverAddPayoutAccountRoute.page,
                    path: 'add-payout-account'),
              ],
            ),
            AutoRoute(
              page: DriverSettingsParentRoute.page,
              path: 'settings',
              children: [
                AutoRoute(
                    page: DriverSettingsRoute.page, path: '', initial: true),
                AutoRoute(
                    page: DriverLanguageSettingsRoute.page, path: 'language'),
                AutoRoute(page: DriverMapSettingsRoute.page, path: 'map'),
              ],
            ),
          ],
        ),
      ];
}
