import 'dart:async';
import 'package:uppi_motorista/core/entities/profile_full.dart';
import 'package:uppi_motorista/core/entities/vehicle_color.dart';
import 'package:uppi_motorista/core/entities/vehicle_model.dart';
import 'package:uppi_motorista/core/enums/driver_status.dart';
import 'package:uppi_motorista/core/utils/status_parser.dart';
import 'package:uppi_motorista/features/auth/domain/entities/login_page.dart';
import 'package:flutter_common/core/entities/media.dart';
import 'package:flutter_common/core/enums/gender.dart';
import 'package:flutter_common/features/country_code_dialog/domain/entities/country_code.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


import '../../domain/entities/verify_otp_response.dart';
import '../../domain/repositories/auth_repository.dart';
import 'package:uppi_motorista/core/error/failure.dart';

part 'login.state.dart';
part 'login.freezed.dart';
part 'login.g.dart';

@LazySingleton()
class LoginBloc extends HydratedCubit<LoginState> {
  AuthRepository repository;
  StreamSubscription<dynamic>? _authSubscription;

  LoginBloc(this.repository) : super(const LoginState()) {
    _checkExistingSession();
    _startAuthListener();
  }

  void _startAuthListener() {
    _authSubscription?.cancel();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session == null) {
        final isFillingForm = state.loginPage.maybeMap(
          orElse: () => true,
          enterNumber: (_) => false,
          enterOtp: (_) => false,
          enterPassword: (_) => false,
          setPassword: (_) => false,
          accessDenied: (_) => false,
          success: (_) => false,
        );
        if (isFillingForm) {
          emit(const LoginState());
        }
      }
    });
  }

  void _checkExistingSession() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      // Se o usuário já estiver preenchendo o formulário, mantemos o estado local
      final isFillingForm =
          state.profileFullEntity != null &&
          (state.loginPage == const LoginPage.contactDetails() ||
              state.loginPage == const LoginPage.vehicleDetails() ||
              state.loginPage == const LoginPage.documents());

      if (isFillingForm) {
        return; // Preserva o progresso local
      }

      // Restauração de sessão — não é signup, é login existente.
      onGoogleSignInSuccess(user.id, isSignUp: false, isSessionRestore: true);
    }
  }

  void onBackPressed() {
    emit(
      state.loginPage.when(
        enterNumber: () =>
            state.copyWith(loginPage: const LoginPage.enterNumber()),
        enterOtp: (otp) =>
            state.copyWith(loginPage: const LoginPage.enterNumber()),
        enterPassword: () =>
            state.copyWith(loginPage: const LoginPage.enterNumber()),
        setPassword: () =>
            state.copyWith(loginPage: const LoginPage.enterNumber()),
        contactDetails: () =>
            state.copyWith(loginPage: const LoginPage.enterNumber()),
        vehicleDetails: () =>
            state.copyWith(loginPage: const LoginPage.contactDetails()),
        payoutInformation: () =>
            state.copyWith(loginPage: const LoginPage.vehicleDetails()),
        documents: () =>
            state.copyWith(loginPage: const LoginPage.vehicleDetails()),
        success: (profile) =>
            state.copyWith(loginPage: const LoginPage.enterNumber()),
        accessDenied: () =>
            state.copyWith(loginPage: const LoginPage.enterNumber()),
      ),
    );
  }

  void reset() => emit(const LoginState());

  void onNumberChanged(CountryCode countryCode, String number) =>
      emit(state.copyWith(countryCode: countryCode, mobileNumber: number));

  void onOtpChanged(String newOtp) => state.loginPage.mapOrNull(
    enterOtp: (enterOtp) =>
        emit(state.copyWith(loginPage: enterOtp.copyWith(otp: newOtp))),
  );

  void onCurrentPasswordChanged(String password) =>
      emit(state.copyWith(currentPassword: password));

  void onNewPasswordChanged(String password) =>
      emit(state.copyWith(newPassword: password));

  void onNewPasswordSubmitted() async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    final result = await repository.setPassword(state.newPassword!);
    result.fold(
      (l) =>
          emit(state.copyWith(errorMessage: l.errorMessage, isLoading: false)),
      (r) async => _processVerifiedUser(
        VerifyOtpResponse(
          jwtToken: state.jwtToken!,
          driverFullProfile: state.profileFullEntity!,
          hasPassword: true,
        ),
      ),
    );
  }

  void sendOtp() async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    final result = await repository.resendOtp(
      state.countryCode!.e164CC + state.mobileNumber!,
    );
    result.fold(
      (l) =>
          emit(state.copyWith(errorMessage: l.errorMessage, isLoading: false)),
      (r) {
        emit(
          state.copyWith(
            loginPage: state.loginPage.maybeMap(
              orElse: () => const LoginPage.enterOtp(),
              enterOtp: (otp) => otp,
            ),
            isLoading: false,
            errorMessage: null,
            verificationHash: r.hash!,
            lastOtpSentAt: DateTime.now(),
          ),
        );
      },
    );
  }

  void onGoogleSignInSuccess(String uid, {bool isSignUp = false, bool isSessionRestore = false}) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      // Busca perfil do motorista no Supabase (sincronizado pela Edge Function sync_profile)
      final supabase = Supabase.instance.client;
      final data = await supabase
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();



      if (data != null) {
        final vehicleDetails = data['vehicle_details'] as Map? ?? {};
        final fullName = data['full_name']?.toString() ?? '';
        final nameParts = fullName.split(' ');

        final profile = ProfileFullEntity(
          id: uid,
          firstName: nameParts.isNotEmpty ? nameParts.first : null,
          lastName: nameParts.length > 1 ? nameParts.skip(1).join(' ') : null,
          mobileNumber: data['phone']?.toString(),
          status: data['role'] == 'driver'
              ? StatusParser.fromString(data['status']?.toString())
              : const DriverStatus.pendingSubmission(),
          gender: null,
          certificateNumber: vehicleDetails['certificateNumber']?.toString(),
          email: data['email']?.toString(),
          address: vehicleDetails['address']?.toString(),
          searchDistance: vehicleDetails['searchDistance'] as int?,
          vehiclePlateNumber: vehicleDetails['plate']?.toString(),
          vehicleProductionYear: vehicleDetails['year'] as int?,
          vehicleModelId: vehicleDetails['model']?.toString(),
          vehicleColorId: vehicleDetails['color']?.toString(),
          vehicleCategory: vehicleDetails['category']?.toString(),
          bankName: vehicleDetails['bankName']?.toString(),
          bankAccountNumber: vehicleDetails['bankAccountNumber']?.toString(),
          bankSwiftCode: vehicleDetails['bankSwiftCode']?.toString(),
          bankRoutingNumber: vehicleDetails['bankRoutingNumber']?.toString(),
          profilePicture: null,
          documents: null,
        );

        if (!isSignUp && !isSessionRestore && profile.status == const DriverStatus.pendingSubmission()) {
          emit(state.copyWith(
            isLoading: false,
            errorMessage: 'Você não completou o cadastro. Por favor, clique em Cadastrar-se.',
          ));
          return;
        }

        if (isSignUp && !isSessionRestore && profile.status != const DriverStatus.pendingSubmission()) {
          emit(state.copyWith(
            isLoading: false,
            errorMessage: 'Você já possui uma conta de motorista. Por favor, clique em Entrar.',
          ));
          return;
        }

        _processVerifiedUser(
          VerifyOtpResponse(
            jwtToken: 'firebase',
            driverFullProfile: profile,
            hasPassword: true,
          ),
        );
      } else {
        if (!isSignUp && !isSessionRestore) {
          emit(state.copyWith(
            isLoading: false,
            errorMessage: 'Nenhuma conta encontrada. Por favor, clique em Cadastrar-se.',
          ));
          return;
        }

        // Perfil ainda nao sincronizado pela Edge Function — primeiro acesso
        final authUser = supabase.auth.currentUser;
        final email = authUser?.email;
        final name = authUser?.userMetadata?['full_name']?.toString() ?? authUser?.userMetadata?['name']?.toString() ?? '';
        final nameParts = name.split(' ');

        final profile = ProfileFullEntity.emptyProfile.copyWith(
          id: uid,
          email: email,
          firstName: nameParts.isNotEmpty ? nameParts.first : null,
          lastName: nameParts.length > 1 ? nameParts.skip(1).join(' ') : null,
        );

        _processVerifiedUser(
          VerifyOtpResponse(
            jwtToken: 'firebase_tmp',
            driverFullProfile: profile,
            hasPassword: true,
          ),
        );
      }
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Error processing login: $e',
        ),
      );
    }
  }

  void onNumberSubmitted() async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    final result = await repository.verifyNumber(
      mobileNumber: state.countryCode!.e164CC + state.mobileNumber!,
      countryIsoCode: state.countryCode!.iso2CC,
    );
    result.fold(
      (l) =>
          emit(state.copyWith(isLoading: false, errorMessage: l.errorMessage)),
      (r) {
        emit(
          state.copyWith(
            loginPage: const LoginPage.enterOtp(),
            isLoading: false,
            errorMessage: null,
            verificationHash: r.hash ?? 'hash',
            lastOtpSentAt: DateTime.now(),
          ),
        );
      },
    );
  }

  void onConfirmOtpPressed() async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    final result = await repository.verifyOtp(
      state.verificationHash!,
      state.loginPage.maybeMap(orElse: () => '', enterOtp: (otp) => otp.otp!),
    );
    result.fold((l) {
      if (l.errorMessage == 'Mobile number not found') {
        emit(
          state.copyWith(
            loginPage: const LoginPage.enterNumber(),
            isLoading: false,
            errorMessage: null,
            verificationHash: null,
          ),
        );
        return;
      }
      emit(state.copyWith(errorMessage: l.errorMessage, isLoading: false));
    }, (r) async => _processVerifiedUser(r));
  }

  void onConfirmPasswordPressed() async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    final result = await repository.verifyPassword(
      state.countryCode!.e164CC + state.mobileNumber!,
      state.currentPassword!,
    );
    result.fold(
      (l) =>
          emit(state.copyWith(errorMessage: l.errorMessage, isLoading: false)),
      (r) async => _processVerifiedUser(r),
    );
  }

  void _processVerifiedUser(VerifyOtpResponse response) async {
    final profile = response.driverFullProfile;
    emit(
      state.copyWith(
        isLoading: true,
        jwtToken: response.jwtToken,
        profileFullEntity: profile,
      ),
    );
    if (response.hasPassword == false) {
      emit(
        state.copyWith(
          loginPage: const LoginPage.setPassword(),
          isLoading: false,
          errorMessage: null,
        ),
      );
      return;
    }
    if (profile.status == const DriverStatus.pendingSubmission()) {
      final remoteData = await repository.getRegistrationData();
      remoteData.fold(
        (l) => emit(
          state.copyWith(errorMessage: l.errorMessage, isLoading: false),
        ),
        (rRemote) {
          emit(
            state.copyWith(
              loginPage: const LoginPage.contactDetails(),
              isLoading: false,
              vehicleModels: rRemote.vehicleModels,
              vehicleColors: rRemote.vehicleColors,
              profileFullEntity: rRemote.profile,
              errorMessage: null,
              jwtToken: response.jwtToken,
            ),
          );
        },
      );
    } else if (profile.status == const DriverStatus.blocked() ||
        profile.status == const DriverStatus.hardReject()) {
      emit(
        state.copyWith(
          loginPage: const LoginPage.accessDenied(),
          isLoading: false,
          errorMessage: null,
        ),
      );
    } else {
      emit(
        state.copyWith(
          loginPage: LoginPage.success(profile: profile.toEntity),
          isLoading: false,
          errorMessage: null,
          jwtToken: response.jwtToken,
          profileFullEntity: profile,
        ),
      );
    }
  }

  Future<void> loadRegistrationData() async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    final remoteData = await repository.getRegistrationData();
    remoteData.fold(
      (l) => emit(
        state.copyWith(errorMessage: l.errorMessage, isLoading: false),
      ),
      (rRemote) {
        emit(
          state.copyWith(
            isLoading: false,
            vehicleModels: rRemote.vehicleModels,
            vehicleColors: rRemote.vehicleColors,
            profileFullEntity: rRemote.profile,
            errorMessage: null,
          ),
        );
      },
    );
  }

  // START: Contact Details

  void onGenderChanged(Gender? gender) =>
      emit(state.copyWith.profileFullEntity!.call(gender: gender));

  void onFirstNameChanged(String? firstName) =>
      emit(state.copyWith.profileFullEntity!.call(firstName: firstName));

  void onLastNameChanged(String? lastName) =>
      emit(state.copyWith.profileFullEntity!.call(lastName: lastName));

  void onAddressChanged(String? address) =>
      emit(state.copyWith.profileFullEntity!.call(address: address));

  void onEmailChanged(String? email) =>
      emit(state.copyWith.profileFullEntity!.call(email: email));

  void onCertificateNumberChanged(String? certificateNumber) => emit(
    state.copyWith.profileFullEntity!.call(
      certificateNumber: certificateNumber,
    ),
  );

  void onMobileNumberChanged(String? mobileNumber) =>
      emit(state.copyWith.profileFullEntity!.call(mobileNumber: mobileNumber));

  void onConfirmContactDetailsPressed() =>
      emit(state.copyWith(loginPage: const LoginPage.vehicleDetails()));

  // END: Contact Details

  // START: Vehicle Details

  void onPlateNumberChanged(String? newValue) => emit(
    state.copyWith.profileFullEntity!.call(vehiclePlateNumber: newValue),
  );

  void onVehicleModelIdChanged(String? newValue) =>
      emit(state.copyWith.profileFullEntity!.call(vehicleModelId: newValue));

  void onVehicleColorIdChanged(String? newValue) =>
      emit(state.copyWith.profileFullEntity!.call(vehicleColorId: newValue));

  void onVehicleProductionYearChanged(int? newValue) => emit(
    state.copyWith.profileFullEntity!.call(vehicleProductionYear: newValue),
  );

  void onVehicleCategoryChanged(String? newValue) => emit(
    state.copyWith.profileFullEntity!.call(vehicleCategory: newValue),
  );

  void onConfirmVehicleDetailsPressed() =>
      emit(state.copyWith(loginPage: const LoginPage.documents()));

  // END: Vehicle Details

  // START: Payout Information

  void onBankNameChanged(String? newValue) =>
      emit(state.copyWith.profileFullEntity!.call(bankName: newValue));

  void onBankAccountNumberChanged(String? newValue) =>
      emit(state.copyWith.profileFullEntity!.call(bankAccountNumber: newValue));

  void onBankRoutingNumberChanged(String? newValue) =>
      emit(state.copyWith.profileFullEntity!.call(bankRoutingNumber: newValue));

  void onBankSwiftCodeChanged(String? newValue) =>
      emit(state.copyWith.profileFullEntity!.call(bankSwiftCode: newValue));

  void onConfirmPayoutInformationPressed() =>
      emit(state.copyWith(loginPage: const LoginPage.documents()));

  // END: Payout Information

  // START: Upload Documents

  void onProfilePhotoChanged(MediaEntity? newValue) =>
      emit(state.copyWith.profileFullEntity!.call(profilePicture: newValue));

  void setDocuments(List<MediaEntity> newValue) {
    emit(state.copyWith.profileFullEntity!.call(documents: newValue));
  }

  void onConfirmDocumentsPressed() async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    final result = await repository.register(profile: state.profileFullEntity!);
    result.fold(
      (l) =>
          emit(state.copyWith(errorMessage: l.errorMessage, isLoading: false)),
      (r) => emit(state.copyWith(loginPage: LoginPage.success(profile: r))),
    );
  }

  @override
  LoginState? fromJson(Map<String, dynamic> json) => LoginState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(LoginState state) => state.toJson();

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}
