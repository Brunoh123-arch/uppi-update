// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

part of 'app_router.dart';

/// generated route for
/// [AddFavoriteLocationScreen]
class AddFavoriteLocationRoute
    extends PageRouteInfo<AddFavoriteLocationRouteArgs> {
  AddFavoriteLocationRoute({
    Key? key,
    AddressType? defaultAddressType,
    List<PageRouteInfo>? children,
  }) : super(
          AddFavoriteLocationRoute.name,
          args: AddFavoriteLocationRouteArgs(
            key: key,
            defaultAddressType: defaultAddressType,
          ),
          initialChildren: children,
        );

  static const String name = 'AddFavoriteLocationRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AddFavoriteLocationRouteArgs>(
          orElse: () => const AddFavoriteLocationRouteArgs());
      return AddFavoriteLocationScreen(
        key: args.key,
        defaultAddressType: args.defaultAddressType,
      );
    },
  );
}

class AddFavoriteLocationRouteArgs {
  const AddFavoriteLocationRouteArgs({
    this.key,
    this.defaultAddressType,
  });

  final Key? key;

  final AddressType? defaultAddressType;

  @override
  String toString() {
    return 'AddFavoriteLocationRouteArgs{key: $key, defaultAddressType: $defaultAddressType}';
  }
}

/// generated route for
/// [AnnouncementsScreen]
class AnnouncementsRoute extends PageRouteInfo<void> {
  const AnnouncementsRoute({List<PageRouteInfo>? children})
      : super(
          AnnouncementsRoute.name,
          initialChildren: children,
        );

  static const String name = 'AnnouncementsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const AnnouncementsScreen();
    },
  );
}

/// generated route for
/// [AuthScreen]
class AuthRoute extends PageRouteInfo<void> {
  const AuthRoute({List<PageRouteInfo>? children})
      : super(
          AuthRoute.name,
          initialChildren: children,
        );

  static const String name = 'AuthRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const AuthScreen();
    },
  );
}

/// generated route for
/// [DocumentsScreen]
class DocumentsRoute extends PageRouteInfo<void> {
  const DocumentsRoute({List<PageRouteInfo>? children})
      : super(
          DocumentsRoute.name,
          initialChildren: children,
        );

  static const String name = 'DocumentsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DocumentsScreen();
    },
  );
}

/// generated route for
/// [DriverAddPayoutAccountWrapper]
class DriverAddPayoutAccountRoute
    extends PageRouteInfo<DriverAddPayoutAccountRouteArgs> {
  DriverAddPayoutAccountRoute({
    Key? key,
    required PayoutMethodEntity payoutMethod,
    List<PageRouteInfo>? children,
  }) : super(
          DriverAddPayoutAccountRoute.name,
          args: DriverAddPayoutAccountRouteArgs(
            key: key,
            payoutMethod: payoutMethod,
          ),
          initialChildren: children,
        );

  static const String name = 'DriverAddPayoutAccountRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DriverAddPayoutAccountRouteArgs>();
      return DriverAddPayoutAccountWrapper(
        key: args.key,
        payoutMethod: args.payoutMethod,
      );
    },
  );
}

class DriverAddPayoutAccountRouteArgs {
  const DriverAddPayoutAccountRouteArgs({
    this.key,
    required this.payoutMethod,
  });

  final Key? key;

  final PayoutMethodEntity payoutMethod;

  @override
  String toString() {
    return 'DriverAddPayoutAccountRouteArgs{key: $key, payoutMethod: $payoutMethod}';
  }
}

/// generated route for
/// [DriverAnnouncementsWrapper]
class DriverAnnouncementsRoute extends PageRouteInfo<void> {
  const DriverAnnouncementsRoute({List<PageRouteInfo>? children})
      : super(
          DriverAnnouncementsRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverAnnouncementsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverAnnouncementsWrapper();
    },
  );
}

/// generated route for
/// [DriverAuthWrapper]
class DriverAuthRoute extends PageRouteInfo<void> {
  const DriverAuthRoute({List<PageRouteInfo>? children})
      : super(
          DriverAuthRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverAuthRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverAuthWrapper();
    },
  );
}

/// generated route for
/// [DriverDocumentsWrapper]
class DriverDocumentsRoute extends PageRouteInfo<void> {
  const DriverDocumentsRoute({List<PageRouteInfo>? children})
      : super(
          DriverDocumentsRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverDocumentsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverDocumentsWrapper();
    },
  );
}

/// generated route for
/// [DriverEarningsWrapper]
class DriverEarningsRoute extends PageRouteInfo<void> {
  const DriverEarningsRoute({List<PageRouteInfo>? children})
      : super(
          DriverEarningsRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverEarningsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverEarningsWrapper();
    },
  );
}

/// generated route for
/// [DriverEditPhoneNumberWrapper]
class DriverEditPhoneNumberRoute extends PageRouteInfo<void> {
  const DriverEditPhoneNumberRoute({List<PageRouteInfo>? children})
      : super(
          DriverEditPhoneNumberRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverEditPhoneNumberRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverEditPhoneNumberWrapper();
    },
  );
}

/// generated route for
/// [DriverFeedbacksSummaryWrapper]
class DriverFeedbacksSummaryRoute extends PageRouteInfo<void> {
  const DriverFeedbacksSummaryRoute({List<PageRouteInfo>? children})
      : super(
          DriverFeedbacksSummaryRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverFeedbacksSummaryRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverFeedbacksSummaryWrapper();
    },
  );
}

/// generated route for
/// [DriverHomeWrapper]
class DriverHomeRoute extends PageRouteInfo<void> {
  const DriverHomeRoute({List<PageRouteInfo>? children})
      : super(
          DriverHomeRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverHomeRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverHomeWrapper();
    },
  );
}

/// generated route for
/// [DriverLanguageSettingsWrapper]
class DriverLanguageSettingsRoute extends PageRouteInfo<void> {
  const DriverLanguageSettingsRoute({List<PageRouteInfo>? children})
      : super(
          DriverLanguageSettingsRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverLanguageSettingsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverLanguageSettingsWrapper();
    },
  );
}

/// generated route for
/// [DriverMapSettingsWrapper]
class DriverMapSettingsRoute extends PageRouteInfo<void> {
  const DriverMapSettingsRoute({List<PageRouteInfo>? children})
      : super(
          DriverMapSettingsRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverMapSettingsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverMapSettingsWrapper();
    },
  );
}

/// generated route for
/// [DriverNavigationWrapper]
class DriverNavigationRoute extends PageRouteInfo<void> {
  const DriverNavigationRoute({List<PageRouteInfo>? children})
      : super(
          DriverNavigationRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverNavigationRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverNavigationWrapper();
    },
  );
}

/// generated route for
/// [DriverPayoutAccountListWrapper]
class DriverPayoutAccountListRoute extends PageRouteInfo<void> {
  const DriverPayoutAccountListRoute({List<PageRouteInfo>? children})
      : super(
          DriverPayoutAccountListRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverPayoutAccountListRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverPayoutAccountListWrapper();
    },
  );
}

/// generated route for
/// [DriverPayoutAccountsWrapper]
class DriverPayoutAccountsRoute extends PageRouteInfo<void> {
  const DriverPayoutAccountsRoute({List<PageRouteInfo>? children})
      : super(
          DriverPayoutAccountsRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverPayoutAccountsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverPayoutAccountsWrapper();
    },
  );
}

/// generated route for
/// [DriverProfileInfoWrapper]
class DriverProfileInfoRoute extends PageRouteInfo<void> {
  const DriverProfileInfoRoute({List<PageRouteInfo>? children})
      : super(
          DriverProfileInfoRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverProfileInfoRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverProfileInfoWrapper();
    },
  );
}

/// generated route for
/// [DriverProfileParentWrapper]
class DriverProfileParentRoute extends PageRouteInfo<void> {
  const DriverProfileParentRoute({List<PageRouteInfo>? children})
      : super(
          DriverProfileParentRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverProfileParentRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverProfileParentWrapper();
    },
  );
}

/// generated route for
/// [DriverProfileWrapper]
class DriverProfileRoute extends PageRouteInfo<void> {
  const DriverProfileRoute({List<PageRouteInfo>? children})
      : super(
          DriverProfileRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverProfileRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverProfileWrapper();
    },
  );
}

/// generated route for
/// [DriverRideHistoryDetailsWrapper]
class DriverRideHistoryDetailsRoute
    extends PageRouteInfo<DriverRideHistoryDetailsRouteArgs> {
  DriverRideHistoryDetailsRoute({
    Key? key,
    required OrderEntity entity,
    List<PageRouteInfo>? children,
  }) : super(
          DriverRideHistoryDetailsRoute.name,
          args: DriverRideHistoryDetailsRouteArgs(
            key: key,
            entity: entity,
          ),
          initialChildren: children,
        );

  static const String name = 'DriverRideHistoryDetailsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DriverRideHistoryDetailsRouteArgs>();
      return DriverRideHistoryDetailsWrapper(
        key: args.key,
        entity: args.entity,
      );
    },
  );
}

class DriverRideHistoryDetailsRouteArgs {
  const DriverRideHistoryDetailsRouteArgs({
    this.key,
    required this.entity,
  });

  final Key? key;

  final OrderEntity entity;

  @override
  String toString() {
    return 'DriverRideHistoryDetailsRouteArgs{key: $key, entity: $entity}';
  }
}

/// generated route for
/// [DriverRideHistoryWrapper]
class DriverRideHistoryRoute extends PageRouteInfo<void> {
  const DriverRideHistoryRoute({List<PageRouteInfo>? children})
      : super(
          DriverRideHistoryRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverRideHistoryRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverRideHistoryWrapper();
    },
  );
}

/// generated route for
/// [DriverSettingsParentWrapper]
class DriverSettingsParentRoute extends PageRouteInfo<void> {
  const DriverSettingsParentRoute({List<PageRouteInfo>? children})
      : super(
          DriverSettingsParentRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverSettingsParentRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverSettingsParentWrapper();
    },
  );
}

/// generated route for
/// [DriverSettingsWrapper]
class DriverSettingsRoute extends PageRouteInfo<void> {
  const DriverSettingsRoute({List<PageRouteInfo>? children})
      : super(
          DriverSettingsRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverSettingsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverSettingsWrapper();
    },
  );
}

/// generated route for
/// [DriverWalletParentWrapper]
class DriverWalletParentRoute extends PageRouteInfo<void> {
  const DriverWalletParentRoute({List<PageRouteInfo>? children})
      : super(
          DriverWalletParentRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverWalletParentRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverWalletParentWrapper();
    },
  );
}

/// generated route for
/// [DriverWalletWrapper]
class DriverWalletRoute extends PageRouteInfo<void> {
  const DriverWalletRoute({List<PageRouteInfo>? children})
      : super(
          DriverWalletRoute.name,
          initialChildren: children,
        );

  static const String name = 'DriverWalletRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DriverWalletWrapper();
    },
  );
}

/// generated route for
/// [EditFavoriteLocationScreen]
class EditFavoriteLocationRoute
    extends PageRouteInfo<EditFavoriteLocationRouteArgs> {
  EditFavoriteLocationRoute({
    Key? key,
    required FavoriteLocationEntity entity,
    List<PageRouteInfo>? children,
  }) : super(
          EditFavoriteLocationRoute.name,
          args: EditFavoriteLocationRouteArgs(
            key: key,
            entity: entity,
          ),
          initialChildren: children,
        );

  static const String name = 'EditFavoriteLocationRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<EditFavoriteLocationRouteArgs>();
      return EditFavoriteLocationScreen(
        key: args.key,
        entity: args.entity,
      );
    },
  );
}

class EditFavoriteLocationRouteArgs {
  const EditFavoriteLocationRouteArgs({
    this.key,
    required this.entity,
  });

  final Key? key;

  final FavoriteLocationEntity entity;

  @override
  String toString() {
    return 'EditFavoriteLocationRouteArgs{key: $key, entity: $entity}';
  }
}

/// generated route for
/// [EditPhoneNumberScreen]
class EditPhoneNumberRoute extends PageRouteInfo<void> {
  const EditPhoneNumberRoute({List<PageRouteInfo>? children})
      : super(
          EditPhoneNumberRoute.name,
          initialChildren: children,
        );

  static const String name = 'EditPhoneNumberRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const EditPhoneNumberScreen();
    },
  );
}

/// generated route for
/// [FavoriteDriversScreen]
class FavoriteDriversRoute extends PageRouteInfo<void> {
  const FavoriteDriversRoute({List<PageRouteInfo>? children})
      : super(
          FavoriteDriversRoute.name,
          initialChildren: children,
        );

  static const String name = 'FavoriteDriversRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const FavoriteDriversScreen();
    },
  );
}

/// generated route for
/// [FavoriteLocationsListScreen]
class FavoriteLocationsListRoute extends PageRouteInfo<void> {
  const FavoriteLocationsListRoute({List<PageRouteInfo>? children})
      : super(
          FavoriteLocationsListRoute.name,
          initialChildren: children,
        );

  static const String name = 'FavoriteLocationsListRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const FavoriteLocationsListScreen();
    },
  );
}

/// generated route for
/// [FavoriteLocationsScreen]
class FavoriteLocationsRoute extends PageRouteInfo<void> {
  const FavoriteLocationsRoute({List<PageRouteInfo>? children})
      : super(
          FavoriteLocationsRoute.name,
          initialChildren: children,
        );

  static const String name = 'FavoriteLocationsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const FavoriteLocationsScreen();
    },
  );
}

/// generated route for
/// [HomeScreen]
class HomeRoute extends PageRouteInfo<void> {
  const HomeRoute({List<PageRouteInfo>? children})
      : super(
          HomeRoute.name,
          initialChildren: children,
        );

  static const String name = 'HomeRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const HomeScreen();
    },
  );
}

/// generated route for
/// [LanguageSettingsScreen]
class LanguageSettingsRoute extends PageRouteInfo<void> {
  const LanguageSettingsRoute({List<PageRouteInfo>? children})
      : super(
          LanguageSettingsRoute.name,
          initialChildren: children,
        );

  static const String name = 'LanguageSettingsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const LanguageSettingsScreen();
    },
  );
}

/// generated route for
/// [LgpdConsentWrapperScreen]
class LgpdConsentWrapperRoute extends PageRouteInfo<void> {
  const LgpdConsentWrapperRoute({List<PageRouteInfo>? children})
      : super(
          LgpdConsentWrapperRoute.name,
          initialChildren: children,
        );

  static const String name = 'LgpdConsentWrapperRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const LgpdConsentWrapperScreen();
    },
  );
}

/// generated route for
/// [LocateFavoriteLocationScreen]
class LocateFavoriteLocationRoute extends PageRouteInfo<void> {
  const LocateFavoriteLocationRoute({List<PageRouteInfo>? children})
      : super(
          LocateFavoriteLocationRoute.name,
          initialChildren: children,
        );

  static const String name = 'LocateFavoriteLocationRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const LocateFavoriteLocationScreen();
    },
  );
}

/// generated route for
/// [MapSettingsScreen]
class MapSettingsRoute extends PageRouteInfo<void> {
  const MapSettingsRoute({List<PageRouteInfo>? children})
      : super(
          MapSettingsRoute.name,
          initialChildren: children,
        );

  static const String name = 'MapSettingsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const MapSettingsScreen();
    },
  );
}

/// generated route for
/// [NavigationScreen]
class NavigationRoute extends PageRouteInfo<void> {
  const NavigationRoute({List<PageRouteInfo>? children})
      : super(
          NavigationRoute.name,
          initialChildren: children,
        );

  static const String name = 'NavigationRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const NavigationScreen();
    },
  );
}

/// generated route for
/// [OnboardingScreen]
class OnboardingRoute extends PageRouteInfo<void> {
  const OnboardingRoute({List<PageRouteInfo>? children})
      : super(
          OnboardingRoute.name,
          initialChildren: children,
        );

  static const String name = 'OnboardingRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const OnboardingScreen();
    },
  );
}

/// generated route for
/// [PaymentMethodsScreen]
class PaymentMethodsRoute extends PageRouteInfo<void> {
  const PaymentMethodsRoute({List<PageRouteInfo>? children})
      : super(
          PaymentMethodsRoute.name,
          initialChildren: children,
        );

  static const String name = 'PaymentMethodsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const PaymentMethodsScreen();
    },
  );
}

/// generated route for
/// [ProfileInfoScreen]
class ProfileInfoRoute extends PageRouteInfo<void> {
  const ProfileInfoRoute({List<PageRouteInfo>? children})
      : super(
          ProfileInfoRoute.name,
          initialChildren: children,
        );

  static const String name = 'ProfileInfoRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const ProfileInfoScreen();
    },
  );
}

/// generated route for
/// [ProfileParentScreen]
class ProfileParentRoute extends PageRouteInfo<void> {
  const ProfileParentRoute({List<PageRouteInfo>? children})
      : super(
          ProfileParentRoute.name,
          initialChildren: children,
        );

  static const String name = 'ProfileParentRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const ProfileParentScreen();
    },
  );
}

/// generated route for
/// [ProfileScreen]
class ProfileRoute extends PageRouteInfo<void> {
  const ProfileRoute({List<PageRouteInfo>? children})
      : super(
          ProfileRoute.name,
          initialChildren: children,
        );

  static const String name = 'ProfileRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const ProfileScreen();
    },
  );
}

/// generated route for
/// [RideHistoryDetailsScreen]
class RideHistoryDetailsRoute
    extends PageRouteInfo<RideHistoryDetailsRouteArgs> {
  RideHistoryDetailsRoute({
    Key? key,
    required OrderCompactEntity entity,
    List<PageRouteInfo>? children,
  }) : super(
          RideHistoryDetailsRoute.name,
          args: RideHistoryDetailsRouteArgs(
            key: key,
            entity: entity,
          ),
          initialChildren: children,
        );

  static const String name = 'RideHistoryDetailsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RideHistoryDetailsRouteArgs>();
      return RideHistoryDetailsScreen(
        key: args.key,
        entity: args.entity,
      );
    },
  );
}

class RideHistoryDetailsRouteArgs {
  const RideHistoryDetailsRouteArgs({
    this.key,
    required this.entity,
  });

  final Key? key;

  final OrderCompactEntity entity;

  @override
  String toString() {
    return 'RideHistoryDetailsRouteArgs{key: $key, entity: $entity}';
  }
}

/// generated route for
/// [RideHistoryScreen]
class RideHistoryRoute extends PageRouteInfo<void> {
  const RideHistoryRoute({List<PageRouteInfo>? children})
      : super(
          RideHistoryRoute.name,
          initialChildren: children,
        );

  static const String name = 'RideHistoryRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const RideHistoryScreen();
    },
  );
}

/// generated route for
/// [RoleSelectionScreen]
class RoleSelectionRoute extends PageRouteInfo<void> {
  const RoleSelectionRoute({List<PageRouteInfo>? children})
      : super(
          RoleSelectionRoute.name,
          initialChildren: children,
        );

  static const String name = 'RoleSelectionRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const RoleSelectionScreen();
    },
  );
}

/// generated route for
/// [ScheduledRideDetailsScreen]
class ScheduledRideDetailsRoute
    extends PageRouteInfo<ScheduledRideDetailsRouteArgs> {
  ScheduledRideDetailsRoute({
    Key? key,
    required OrderCompactEntity entity,
    List<PageRouteInfo>? children,
  }) : super(
          ScheduledRideDetailsRoute.name,
          args: ScheduledRideDetailsRouteArgs(
            key: key,
            entity: entity,
          ),
          initialChildren: children,
        );

  static const String name = 'ScheduledRideDetailsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ScheduledRideDetailsRouteArgs>();
      return ScheduledRideDetailsScreen(
        key: args.key,
        entity: args.entity,
      );
    },
  );
}

class ScheduledRideDetailsRouteArgs {
  const ScheduledRideDetailsRouteArgs({
    this.key,
    required this.entity,
  });

  final Key? key;

  final OrderCompactEntity entity;

  @override
  String toString() {
    return 'ScheduledRideDetailsRouteArgs{key: $key, entity: $entity}';
  }
}

/// generated route for
/// [ScheduledRidesScreen]
class ScheduledRidesRoute extends PageRouteInfo<void> {
  const ScheduledRidesRoute({List<PageRouteInfo>? children})
      : super(
          ScheduledRidesRoute.name,
          initialChildren: children,
        );

  static const String name = 'ScheduledRidesRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const ScheduledRidesScreen();
    },
  );
}

/// generated route for
/// [SettingsParentScreen]
class SettingsParentRoute extends PageRouteInfo<void> {
  const SettingsParentRoute({List<PageRouteInfo>? children})
      : super(
          SettingsParentRoute.name,
          initialChildren: children,
        );

  static const String name = 'SettingsParentRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const SettingsParentScreen();
    },
  );
}

/// generated route for
/// [SettingsScreen]
class SettingsRoute extends PageRouteInfo<void> {
  const SettingsRoute({List<PageRouteInfo>? children})
      : super(
          SettingsRoute.name,
          initialChildren: children,
        );

  static const String name = 'SettingsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const SettingsScreen();
    },
  );
}

/// generated route for
/// [SplashScreen]
class SplashRoute extends PageRouteInfo<void> {
  const SplashRoute({List<PageRouteInfo>? children})
      : super(
          SplashRoute.name,
          initialChildren: children,
        );

  static const String name = 'SplashRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const SplashScreen();
    },
  );
}

/// generated route for
/// [WalletParentScreen]
class WalletParentRoute extends PageRouteInfo<void> {
  const WalletParentRoute({List<PageRouteInfo>? children})
      : super(
          WalletParentRoute.name,
          initialChildren: children,
        );

  static const String name = 'WalletParentRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const WalletParentScreen();
    },
  );
}

/// generated route for
/// [WalletScreen]
class WalletRoute extends PageRouteInfo<void> {
  const WalletRoute({List<PageRouteInfo>? children})
      : super(
          WalletRoute.name,
          initialChildren: children,
        );

  static const String name = 'WalletRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const WalletScreen();
    },
  );
}
