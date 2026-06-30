// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:connectivity_plus/connectivity_plus.dart' as _i895;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;
import 'package:supabase_flutter/supabase_flutter.dart' as _i454;
import 'package:uppi_motorista/config/locator/locator.dart' as _i760;
import 'package:uppi_motorista/core/blocs/auth_bloc.dart' as _i40;
import 'package:uppi_motorista/core/blocs/location.dart' as _i984;
import 'package:uppi_motorista/core/blocs/onboarding_cubit.dart' as _i851;
import 'package:uppi_motorista/core/blocs/route.dart' as _i723;
import 'package:uppi_motorista/core/datasources/firebase_datasource.dart'
    as _i672;
import 'package:uppi_motorista/core/datasources/location_datasource.dart'
    as _i51;
import 'package:uppi_motorista/core/datasources/location_datasource.prod.dart'
    as _i705;
import 'package:uppi_motorista/core/datasources/location_update_datasource.dart'
    as _i360;
import 'package:uppi_motorista/core/datasources/location_update_datasource.prod.dart'
    as _i738;
import 'package:uppi_motorista/core/datasources/upload_datasource.dart'
    as _i397;
import 'package:uppi_motorista/core/datasources/upload_datasource.dev.dart'
    as _i21;
import 'package:uppi_motorista/core/datasources/upload_datasource.prod.dart'
    as _i275;
import 'package:uppi_motorista/core/repositories/firebase_repository.dart'
    as _i1047;
import 'package:uppi_motorista/core/repositories/firebase_repository.prod.dart'
    as _i1063;
import 'package:uppi_motorista/core/repositories/profile_repository.dart'
    as _i59;
import 'package:uppi_motorista/core/repositories/profile_repository.prod.dart'
    as _i1006;
import 'package:uppi_motorista/core/router/app_router.dart' as _i531;
import 'package:uppi_motorista/features/announcements/data/repositories/announcements_repository.prod.dart'
    as _i319;
import 'package:uppi_motorista/features/announcements/domain/repositories/announcements_repository.dart'
    as _i346;
import 'package:uppi_motorista/features/announcements/presentation/blocs/announcements.dart'
    as _i716;
import 'package:uppi_motorista/features/auth/data/repositories/auth_repository.prod.dart'
    as _i496;
import 'package:uppi_motorista/features/auth/domain/repositories/auth_repository.dart'
    as _i33;
import 'package:uppi_motorista/features/auth/presentation/blocs/login.dart'
    as _i99;
import 'package:uppi_motorista/features/auth/presentation/blocs/onboarding_cubit.dart'
    as _i998;
import 'package:uppi_motorista/features/earnings/data/repositories/earnings_repository.prod.dart'
    as _i559;
import 'package:uppi_motorista/features/earnings/domain/repositories/earnings_repository.dart'
    as _i1033;
import 'package:uppi_motorista/features/earnings/presentation/blocs/earnings.dart'
    as _i822;
import 'package:uppi_motorista/features/home/data/repositories/home_repository.prod.dart'
    as _i181;
import 'package:uppi_motorista/features/home/domain/repositories/home_repository.dart'
    as _i609;
import 'package:uppi_motorista/features/home/presentation/blocs/cancel_reason.dart'
    as _i1048;
import 'package:uppi_motorista/features/home/presentation/blocs/home.dart'
    as _i998;
import 'package:uppi_motorista/features/payout_methods/data/repositories/payout_methods_repository.prod.dart'
    as _i1030;
import 'package:uppi_motorista/features/payout_methods/domain/repositories/payout_methods_repository.dart'
    as _i129;
import 'package:uppi_motorista/features/payout_methods/presentation/blocs/add_bank_transfer_payout_method_form_cubit.dart'
    as _i891;
import 'package:uppi_motorista/features/payout_methods/presentation/blocs/payout_accounts.dart'
    as _i247;
import 'package:uppi_motorista/features/payout_methods/presentation/blocs/payout_methods.dart'
    as _i148;
import 'package:uppi_motorista/features/profile/data/repositories/profile_repository.prod.dart'
    as _i99;
import 'package:uppi_motorista/features/profile/domain/repositories/profile_repository.dart'
    as _i819;
import 'package:uppi_motorista/features/profile/presentation/blocs/feedbacks_summary.dart'
    as _i796;
import 'package:uppi_motorista/features/profile/presentation/blocs/profile.dart'
    as _i624;
import 'package:uppi_motorista/features/redeem_gift_card/data/repositories/redeem_gift_card_repository.prod.dart'
    as _i86;
import 'package:uppi_motorista/features/redeem_gift_card/domain/repositories/redeem_gift_card_repository.dart'
    as _i507;
import 'package:uppi_motorista/features/redeem_gift_card/presentation/blocs/redeem_gift_card.dart'
    as _i564;
import 'package:uppi_motorista/features/ride_history/data/repositories/ride_history_repository.prod.dart'
    as _i10;
import 'package:uppi_motorista/features/ride_history/domain/repositories/ride_history_repository.dart'
    as _i974;
import 'package:uppi_motorista/features/ride_history/presentation/blocs/report_issue.dart'
    as _i690;
import 'package:uppi_motorista/features/ride_history/presentation/blocs/ride_history.dart'
    as _i744;
import 'package:uppi_motorista/features/wallet/data/repositories/wallet_repository.prod.dart'
    as _i75;
import 'package:uppi_motorista/features/wallet/domain/repositories/wallet_repository.dart'
    as _i269;
import 'package:uppi_motorista/features/wallet/presentation/blocs/top_up_wallet.dart'
    as _i544;
import 'package:uppi_motorista/features/wallet/presentation/blocs/wallet.dart'
    as _i915;

const String _dev = 'dev';
const String _prod = 'prod';

extension GetItInjectableX on _i174.GetIt {
// initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(
      this,
      environment,
      environmentFilter,
    );
    final serviceModule = _$ServiceModule();
    gh.singleton<_i851.OnboardingCubit>(() => _i851.OnboardingCubit());
    gh.singleton<_i531.AppRouter>(() => _i531.AppRouter());
    gh.singleton<_i998.OnboardingCubit>(() => _i998.OnboardingCubit());
    gh.lazySingleton<_i895.Connectivity>(() => serviceModule.connectivity);
    gh.lazySingleton<_i454.SupabaseClient>(() => serviceModule.supabaseClient);
    gh.lazySingleton<_i723.RouteCubit>(() => _i723.RouteCubit());
    gh.lazySingleton<_i397.UploadDatasource>(
      () => _i21.UploadDatasourceMock(),
      registerFor: {_dev},
    );
    gh.lazySingleton<_i1047.FirebaseRepository>(
      () => _i1063.FirebaseRepositoryProd(),
      registerFor: {_prod},
    );
    gh.lazySingleton<_i51.LocationDatasource>(
      () => _i705.LocationDatasourceImpl(),
      registerFor: {_prod},
    );
    gh.lazySingleton<_i360.LocationUpdateDatasource>(
      () => _i738.LocationUpdateDatasourceProd(),
      registerFor: {_prod},
    );
    gh.lazySingleton<_i33.AuthRepository>(
      () => _i496.AuthRepositoryProd(),
      registerFor: {_prod},
    );
    gh.lazySingleton<_i609.HomeRepository>(
      () => _i181.HomeRepositoryProd(),
      registerFor: {_prod},
    );
    gh.lazySingleton<_i397.UploadDatasource>(
      () => _i275.UploadDatasourceImpl(),
      registerFor: {_prod},
    );
    gh.lazySingleton<_i672.FirebaseDatasource>(() =>
        _i672.FirebaseDatasource(supabaseClient: gh<_i454.SupabaseClient>()));
    gh.lazySingleton<_i998.HomeBloc>(() => _i998.HomeBloc(
          gh<_i609.HomeRepository>(),
          gh<_i1047.FirebaseRepository>(),
        ));
    gh.lazySingleton<_i99.LoginBloc>(
        () => _i99.LoginBloc(gh<_i33.AuthRepository>()));
    gh.lazySingleton<_i974.RideHistoryRepository>(
      () => _i10.RideHistoryRepositoryImpl(
        gh<_i672.FirebaseDatasource>(),
        supabaseClient: gh<_i454.SupabaseClient>(),
      ),
      registerFor: {_prod},
    );
    gh.lazySingleton<_i1048.CancelReasonCubit>(
        () => _i1048.CancelReasonCubit(gh<_i609.HomeRepository>()));
    gh.lazySingleton<_i984.LocationBloc>(() => _i984.LocationBloc(
          gh<_i51.LocationDatasource>(),
          gh<_i360.LocationUpdateDatasource>(),
        ));
    gh.lazySingleton<_i59.ProfileRepository>(
      () => _i1006.ProfileRepositoryProd(gh<_i672.FirebaseDatasource>()),
      registerFor: {_prod},
    );
    gh.lazySingleton<_i507.RedeemGiftCardRepository>(
      () => _i86.RedeemGiftCardRepositoryImpl(gh<_i672.FirebaseDatasource>()),
      registerFor: {_prod},
    );
    gh.lazySingleton<_i819.ProfileRepository>(
      () => _i99.ProfileRepositoryProd(gh<_i672.FirebaseDatasource>()),
      registerFor: {_prod},
    );
    gh.lazySingleton<_i346.AnnouncementsRepository>(
      () => _i319.AnnouncementsRepositoryImpl(gh<_i672.FirebaseDatasource>()),
      registerFor: {_prod},
    );
    gh.lazySingleton<_i716.AnnouncementsBloc>(
        () => _i716.AnnouncementsBloc(gh<_i346.AnnouncementsRepository>()));
    gh.lazySingleton<_i269.WalletRepository>(
      () => _i75.WalletRepositoryImpl(gh<_i672.FirebaseDatasource>()),
      registerFor: {_prod},
    );
    gh.lazySingleton<_i544.TopUpWalletBloc>(
        () => _i544.TopUpWalletBloc(gh<_i269.WalletRepository>()));
    gh.lazySingleton<_i129.PayoutMethodsRepository>(
      () => _i1030.PayoutMethodsRepositoryImpl(gh<_i672.FirebaseDatasource>()),
      registerFor: {_prod},
    );
    gh.lazySingleton<_i690.ReportIssueCubit>(
        () => _i690.ReportIssueCubit(gh<_i974.RideHistoryRepository>()));
    gh.lazySingleton<_i744.RideHistoryBloc>(
        () => _i744.RideHistoryBloc(gh<_i974.RideHistoryRepository>()));
    gh.lazySingleton<_i1033.EarningsRepository>(
      () => _i559.EarningsRepositoryImpl(gh<_i672.FirebaseDatasource>()),
      registerFor: {_prod},
    );
    gh.lazySingleton<_i40.AuthBloc>(
        () => _i40.AuthBloc(gh<_i59.ProfileRepository>()));
    gh.lazySingleton<_i564.RedeemGiftCardBloc>(
        () => _i564.RedeemGiftCardBloc(gh<_i507.RedeemGiftCardRepository>()));
    gh.lazySingleton<_i796.FeedbacksSummaryCubit>(
        () => _i796.FeedbacksSummaryCubit(gh<_i819.ProfileRepository>()));
    gh.lazySingleton<_i624.ProfileBloc>(
        () => _i624.ProfileBloc(gh<_i819.ProfileRepository>()));
    gh.lazySingleton<_i891.AddBankTransferPayoutMethodFormCubit>(() =>
        _i891.AddBankTransferPayoutMethodFormCubit(
            gh<_i129.PayoutMethodsRepository>()));
    gh.lazySingleton<_i247.PayoutAccountsBloc>(
        () => _i247.PayoutAccountsBloc(gh<_i129.PayoutMethodsRepository>()));
    gh.lazySingleton<_i148.PayoutMethodsBloc>(
        () => _i148.PayoutMethodsBloc(gh<_i129.PayoutMethodsRepository>()));
    gh.lazySingleton<_i915.WalletBloc>(
        () => _i915.WalletBloc(gh<_i269.WalletRepository>()));
    gh.lazySingleton<_i822.EarningsBloc>(
        () => _i822.EarningsBloc(gh<_i1033.EarningsRepository>()));
    return this;
  }
}

class _$ServiceModule extends _i760.ServiceModule {}
