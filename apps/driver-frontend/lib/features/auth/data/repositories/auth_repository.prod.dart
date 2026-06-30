import 'dart:async';
import 'package:dartz/dartz.dart';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uppi_motorista/core/entities/profile.dart';
import 'package:uppi_motorista/core/entities/profile_full.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:uppi_motorista/core/entities/vehicle_model.dart';
import 'package:uppi_motorista/core/entities/vehicle_color.dart';
import 'package:uppi_motorista/features/auth/domain/entities/registration_remote_data.dart';
import 'package:flutter_common/core/enums/gender.dart';

import '../../domain/entities/verify_number_response.dart';
import '../../domain/entities/verify_otp_response.dart';
import '../../domain/repositories/auth_repository.dart';
import 'package:uppi_motorista/core/enums/driver_status.dart';

@prod
@LazySingleton(as: AuthRepository)
class AuthRepositoryProd implements AuthRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Armazena temporariamente o número enquanto o usuário está no fluxo de OTP
  String? _pendingPhone;

  Failure _mapExceptionToFailure(dynamic e, String defaultMessage) {
    if (e is AuthException) {
      final msg = e.message.toLowerCase();
      final status = e.statusCode?.toString() ?? '';
      if (status == '429' || 
          msg.contains('rate limit') || 
          msg.contains('too many requests') || 
          msg.contains('slow down') || 
          msg.contains('sms') || 
          msg.contains('over_limit') ||
          msg.contains('throttling') ||
          msg.contains('sobrecarga')) {
        return const Failure.error(message: 'Muitas solicitações. Aguarde 2 minutos antes de tentar novamente.');
      }
      return Failure.error(message: e.message);
    }
    return Failure.error(message: '$defaultMessage: $e');
  }

  @override
  Future<Either<Failure, VerifyNumberResponse>> verifyNumber({
    required String mobileNumber,
    required String countryIsoCode,
  }) async {
    try {
      final digits = mobileNumber.replaceAll(RegExp(r'\D'), '');
      final normalized = '+$countryIsoCode$digits';

      _pendingPhone = normalized;

      // Verifica se já existe um perfil com esse telefone no Supabase
      final row = await _supabase
          .from('profiles')
          .select('id')
          .eq('phone', normalized)
          .maybeSingle();
          
      final isExistingUser = row != null;

      // ── Disparar SMS via Supabase ──
      await _supabase.auth.signInWithOtp(phone: normalized);

      return Right(
        VerifyNumberResponse(
          hash: normalized,
          isExistingUser: isExistingUser,
        ),
      );
    } catch (e) {
      debugPrint('verifyNumber catch: $e');
      return Left(_mapExceptionToFailure(e, 'Falha ao verificar número'));
    }
  }

  ProfileFullEntity _parseDriverProfile(
    String uid,
    Map<String, dynamic>? data,
  ) {
    if (data == null) return ProfileFullEntity.emptyProfile;

    DriverStatus parseStatus(String? status) {
      switch (status?.toLowerCase()) {
        case 'offline':
          return const DriverStatus.offline();
        case 'online':
          return const DriverStatus.online();
        case 'ontrip':
        case 'in_progress':
          return const DriverStatus.onTrip();
        case 'blocked':
          return const DriverStatus.blocked();
        case 'softreject':
        case 'soft_reject':
          return const DriverStatus.softReject();
        case 'hardreject':
        case 'hard_reject':
          return const DriverStatus.hardReject();
        case 'pendingapproval':
        case 'pending_approval':
        case 'waiting_documents':
        case 'pending_review':
          return const DriverStatus.pendingApproval();
        case 'active':
        case 'approved':
          return const DriverStatus.offline();
        default:
          return const DriverStatus.pendingSubmission();
      }
    }

    final fullName = data['full_name']?.toString() ?? '';
    final nameParts = fullName.split(' ');

    return ProfileFullEntity(
      id: uid,
      firstName: nameParts.isNotEmpty ? nameParts.first : null,
      lastName: nameParts.length > 1 ? nameParts.sublist(1).join(' ') : null,
      mobileNumber: data['phone']?.toString(),
      status: parseStatus(data['status'] as String?),
      gender: null,
      certificateNumber: data['certificate_number'] as String?,
      email: data['email'] as String?,
      address: data['address'] as String?,
      searchDistance: data['search_distance'] as int?,
      vehiclePlateNumber: data['vehicle_plate_number'] as String?,
      vehicleProductionYear: data['vehicle_production_year'] as int?,
      vehicleModelId: data['vehicle_model_id'] as String?,
      vehicleColorId: data['vehicle_color_id'] as String?,
      vehicleCategory: data['vehicle_type']?.toString(),
      bankName: data['bank_name'] as String?,
      bankAccountNumber: data['bank_account_number'] as String?,
      bankSwiftCode: data['bank_swift_code'] as String?,
      bankRoutingNumber: data['bank_routing_number'] as String?,
      profilePicture: null,
      documents: null,
    );
  }

  @override
  Future<Either<Failure, VerifyOtpResponse>> verifyOtp(
    String hash,
    String otp,
  ) async {
    try {
      if (otp.isEmpty) {
        return const Left(Failure.error(message: 'Código inválido'));
      }

      final phone = hash;

      // ── Validar OTP e Criar Sessão no Supabase Auth ──
      try {
        await _supabase.auth.verifyOTP(
          type: OtpType.sms,
          phone: phone,
          token: otp,
        );
      } catch (e) {
        return Left(_mapExceptionToFailure(e, 'Erro ao validar OTP'));
      }
      // ── Fim criação de sessão ──

      final safePhone = phone.replaceAll(RegExp(r'[^0-9]'), '');

      final row = await _supabase
          .from('profiles')
          .select()
          .ilike('phone', '%$safePhone%')
          .maybeSingle();

      if (row != null) {
        final uid = row['id'] as String;
        return Right(
          VerifyOtpResponse(
            jwtToken: 'supabase_phone',
            driverFullProfile: _parseDriverProfile(uid, row),
            hasPassword: true,
          ),
        );
      } else {
        return Right(
          VerifyOtpResponse(
            jwtToken: 'supabase_phone_new',
            driverFullProfile: ProfileFullEntity.emptyProfile.copyWith(
              mobileNumber: phone,
            ),
            hasPassword: true,
          ),
        );
      }
    } catch (e) {
      debugPrint('verifyOtp catch: $e');
      return Left(_mapExceptionToFailure(e, 'Erro ao verificar código'));
    }
  }

  @override
  Future<Either<Failure, VerifyOtpResponse>> verifyPassword(
    String mobileNumber,
    String password,
  ) async {
    return const Left(
      Failure.error(),
    ); // Usando OTP via Firebase, Senha ignorada
  }

  @override
  Future<Either<Failure, bool>> setPassword(String password) async {
    return const Right(true);
  }

  @override
  Future<Either<Failure, RegistrationRemoteData>> getRegistrationData() async {
    try {
      // Buscar perfil atual do motorista no Supabase
      ProfileFullEntity profile = ProfileFullEntity.emptyProfile;
      final uid = _supabase.auth.currentUser?.id;
      Map<String, dynamic>? row;

      if (uid != null) {
        row = await _supabase
            .from('profiles')
            .select()
            .eq('id', uid)
            .maybeSingle();
      } else if (_pendingPhone != null) {
        row = await _supabase
            .from('profiles')
            .select()
            .eq('phone', _pendingPhone!)
            .maybeSingle();
      }

      if (row != null) {
        profile = _parseDriverProfile(row['id'] as String, row);
      }

      // Buscar modelos de veículos do Supabase
      final modelsData = await _supabase.from('car_models').select('id, name, category').order('name');
      final models = (modelsData as List).map((data) {
        return VehicleModelEntity(
          id: data['id']?.toString() ?? '',
          name: data['name']?.toString() ?? '',
          category: data['category']?.toString() ?? 'carro',
        );
      }).toList();

      // Buscar cores de veículos do Supabase
      final colorsData = await _supabase.from('car_colors').select();
      final colors = (colorsData as List).map((data) {
        return VehicleColorEntity(
          id: data['id']?.toString() ?? '',
          name: data['name']?.toString() ?? '',
        );
      }).toList();

      return Right(
        RegistrationRemoteData(
          profile: profile,
          vehicleModels: models,
          vehicleColors: colors,
        ),
      );
    } catch (_) {
      return const Left(Failure.error());
    }
  }

  @override
  Future<Either<Failure, VerifyNumberResponse>> resendOtp(
    String mobileNumber,
  ) async {
    final phone = _pendingPhone ?? '+$mobileNumber'.replaceAll(RegExp(r'[^0-9+]'), '');
    try {
      await _supabase.auth.signInWithOtp(phone: phone);
      return Right(
        VerifyNumberResponse(
          hash: phone,
          isExistingUser: true, // Optimistic assumption for resend
        ),
      );
    } catch (e) {
      debugPrint('resendOtp catch: $e');
      return Left(_mapExceptionToFailure(e, 'Falha ao reenviar código'));
    }
  }

  @override
  Future<Either<Failure, ProfileEntity>> updateProfile({
    required String firstName,
    required String lastName,
    required Gender gender,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    final phone = _pendingPhone;

    if (uid == null && phone == null) return const Left(Failure.error());

    // Sincroniza perfil via Edge Function (autoria validada pelo servidor)
    await _supabase.functions.invoke(
      'sync-profile',
      body: {
        'role': 'driver',
        'fullName': '$firstName $lastName',
      },
    );

    final row = uid != null
        ? await _supabase.from('profiles').select().eq('id', uid).maybeSingle()
        : await _supabase
              .from('profiles')
              .select()
              .eq('phone', phone!)
              .maybeSingle();

    final data = row ?? {};
    final st = data['status']?.toString();
    DriverStatus driverStatus = const DriverStatus.offline();
    if (st == 'online') driverStatus = const DriverStatus.online();

    return Right(
      ProfileEntity(
        firstName: firstName,
        lastName: lastName,
        countryCode: 'BR',
        gender: gender,
        email: data['email']?.toString(),
        status: driverStatus,
        number: data['phone']?.toString() ?? '',
        searchRadius: data['search_distance'] as int? ?? 5000,
        profilePicture: null,
        orders: [],
        wallets: [],
      ),
    );
  }

  @override
  Future<Either<Failure, ProfileEntity>> register({
    required ProfileFullEntity profile,
  }) async {
    String? uid = _supabase.auth.currentUser?.id;

    if (uid == null) {
      return const Left(Failure.error(message: 'Sessão expirada. Por favor, faça a verificação por SMS novamente.'));
    }

    String phone = _pendingPhone ?? profile.mobileNumber ?? '';
    if (phone.isNotEmpty) {
      phone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
      if (!phone.startsWith('+')) {
        if (phone.startsWith('55')) {
          phone = '+$phone';
        } else {
          phone = '+55$phone';
        }
      }
    }

    try {
      // Registrar motorista via Edge Function (garante validação e role=driver no servidor)
      final response = await _supabase.functions.invoke(
        'register-driver',
        body: {
          'fullName': '${profile.firstName ?? ''} ${profile.lastName ?? ''}'.trim(),
          'phone': phone,
          'vehiclePlate': profile.vehiclePlateNumber,
          'vehicleModelId': profile.vehicleModelId,
          'vehicleColorId': profile.vehicleColorId,
          'vehicleYear': profile.vehicleProductionYear,
          'vehicleCategory': profile.vehicleCategory,
          'bankName': profile.bankName,
          'bankAccountNumber': profile.bankAccountNumber,
          'bankSwiftCode': profile.bankSwiftCode,
          'bankRoutingNumber': profile.bankRoutingNumber,
          'address': profile.address,
          'email': profile.email,
          'certificateNumber': profile.certificateNumber,
          'searchDistance': profile.searchDistance,
          'documents': [
            if (profile.documents != null && profile.documents!.isNotEmpty)
              {
                'name': 'CNH',
                'url': profile.documents![0].address,
              },
            if (profile.documents != null && profile.documents!.length > 1)
              {
                'name': 'CRLV',
                'url': profile.documents![1].address,
              },
            if (profile.documents != null && profile.documents!.length > 2)
              {
                'name': 'RG',
                'url': profile.documents![2].address,
              },
          ],
          'avatarUrl': profile.profilePicture?.address,
        },
      );

      if (response.status != 200) {
        final errMsg = response.data?['error'] ?? 'Falha ao registrar motorista';
        debugPrint('[AuthRepositoryProd.register] Error Response Status: ${response.status}, Data: ${response.data}');
        return Left(Failure.error(message: errMsg.toString()));
      }
    } catch (e) {
      debugPrint('register catch: $e');
      return Left(Failure.error(message: 'Erro de rede ou servidor: $e'));
    }

    return Right(
      ProfileEntity(
        firstName: profile.firstName,
        lastName: profile.lastName,
        countryCode: 'BR',
        gender: profile.gender,
        email: profile.email,
        status: const DriverStatus.pendingApproval(),
        number: phone,
        searchRadius: profile.searchDistance ?? 5000,
        profilePicture: null,
        orders: [],
        wallets: [],
      ),
    );
  }
}
