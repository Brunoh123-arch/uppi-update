// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

part of 'app_router.dart';

/// generated route for
/// [AddPayoutAccountScreen]
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
      return AddPayoutAccountScreen(
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
/// [AnnouncementsScreen]
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
      return const AnnouncementsScreen();
    },
  );
}

/// generated route for
/// [AuthScreen]
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
      return const AuthScreen();
    },
  );
}

/// generated route for
/// [DriverDocumentsScreen]
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
      return const DriverDocumentsScreen();
    },
  );
}

/// generated route for
/// [EarningsScreen]
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
      return const EarningsScreen();
    },
  );
}

/// generated route for
/// [EditPhoneNumberScreen]
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
      return const EditPhoneNumberScreen();
    },
  );
}

/// generated route for
/// [FeedbacksSummaryScreen]
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
      return const FeedbacksSummaryScreen();
    },
  );
}

/// generated route for
/// [HomeScreen]
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
      return const HomeScreen();
    },
  );
}

/// generated route for
/// [LanguageSettingsScreen]
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
      return const LanguageSettingsScreen();
    },
  );
}

/// generated route for
/// [MapSettingsScreen]
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
      return const MapSettingsScreen();
    },
  );
}

/// generated route for
/// [NavigationScreen]
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
      return const NavigationScreen();
    },
  );
}

/// generated route for
/// [PayoutAccountListScreen]
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
      return const PayoutAccountListScreen();
    },
  );
}

/// generated route for
/// [PayoutAccountsScreen]
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
      return const PayoutAccountsScreen();
    },
  );
}

/// generated route for
/// [ProfileInfoScreen]
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
      return const ProfileInfoScreen();
    },
  );
}

/// generated route for
/// [ProfileParentScreen]
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
      return const ProfileParentScreen();
    },
  );
}

/// generated route for
/// [ProfileScreen]
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
      return const ProfileScreen();
    },
  );
}

/// generated route for
/// [RideHistoryDetailsScreen]
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
      return RideHistoryDetailsScreen(
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
/// [RideHistoryScreen]
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
      return const RideHistoryScreen();
    },
  );
}

/// generated route for
/// [SettingsParentScreen]
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
      return const SettingsParentScreen();
    },
  );
}

/// generated route for
/// [SettingsScreen]
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
      return const SettingsScreen();
    },
  );
}

/// generated route for
/// [WalletParentScreen]
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
      return const WalletParentScreen();
    },
  );
}

/// generated route for
/// [WalletScreen]
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
      return const WalletScreen();
    },
  );
}
