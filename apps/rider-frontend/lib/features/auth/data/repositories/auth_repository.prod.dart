import 'dart:async';
import 'package:dartz/dartz.dart';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:rider_flutter/core/entities/profile.dart';
import 'package:rider_flutter/core/error/failure.dart';
import 'package:flutter_common/core/enums/gender.dart';

import '../../domain/entities/verify_number_response.dart';
import '../../domain/entities/verify_otp_response.dart';
import '../../domain/repositories/auth_repository.dart';

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
        return Failure.server(message: 'Muitas solicitações. Aguarde 2 minutos antes de tentar novamente.');
      }
      return Failure.server(message: e.message);
    }
    return Failure.server(message: '$defaultMessage: $e');
  }

  @override
  Future<Either<Failure, VerifyNumberResponse>> verifyNumber({
    required String mobileNumber,
    required String countryCode,
  }) async {
    try {
      // Normaliza para formato E.164: countryCode (ex: +55) + dígitos do número local
      // Remove o "+" do countryCode se presente, depois junta com os dígitos do número
      final ccDigits = countryCode.replaceAll(RegExp(r'\D'), '');
      final numDigits = mobileNumber.replaceAll(RegExp(r'\D'), '');
      final normalized = '+$ccDigits$numDigits';

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

  @override
  Future<Either<Failure, VerifyOtpResponse>> verifyOtp(
    String hash,
    String otp,
  ) async {
    try {
      if (otp.isEmpty) {
        return Left(Failure.server(message: 'Informe o código de verificação'));
      }

      final phone = hash; // hash = número normalizado (passado em verifyNumber)

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

      // Busca perfil existente pelo telefone
      final row = await _supabase
          .from('profiles')
          .select()
          .eq('phone', phone)
          .maybeSingle();

      if (row != null) {
        // Usuário existente
        final fullName = row['full_name']?.toString() ?? '';
        final nameParts = fullName.split(' ');
        return Right(VerifyOtpResponse(
          jwtToken: 'supabase_phone',
          profile: ProfileEntity(
            firstName: nameParts.isNotEmpty ? nameParts.first : null,
            lastName:
                nameParts.length > 1 ? nameParts.sublist(1).join(' ') : null,
            countryCode: 'BR',
            email: row['email'] as String?,
            gender: null,
            profileImage: null,
            presetProfileImage: row['preset_avatar_number'] as int?,
            number: row['phone'] as String? ?? phone,
            idNumber: row['id_number'] as String?,
          ),
          hasPassword: true,
          hasName: (row['full_name'] as String?)?.isNotEmpty ?? false,
          registrationRequired: false,
        ));
      } else {
        // Novo usuário — pede nome na próxima tela
        return Right(VerifyOtpResponse(
          jwtToken: 'supabase_phone_new',
          profile: ProfileEntity(
            firstName: null,
            lastName: null,
            countryCode: 'BR',
            email: null,
            gender: null,
            profileImage: null,
            presetProfileImage: null,
            number: phone,
            idNumber: null,
          ),
          hasPassword: true,
          hasName: false,
          registrationRequired: true,
        ));
      }
    } catch (e) {
      debugPrint('verifyOtp catch: $e');
      return Left(_mapExceptionToFailure(e, 'Erro ao verificar código'));
    }
  }

  /// [DEPRECATED] Login por senha foi descontinuado em favor do fluxo OTP nativo do Supabase.
  /// Mantido apenas por compatibilidade com a interface do repositório.
  @override
  Future<Either<Failure, VerifyOtpResponse>> verifyPassword(
    String mobileNumber,
    String password,
  ) async {
    return Left(Failure.server(message: 'Login por senha não suportado. Utilize o código de verificação recebido por SMS.'));
  }

  /// [DEPRECATED] Fluxo de senha descontinuado. Retorna bypass de password como true
  /// para direcionar o usuário diretamente para as etapas ativas do cadastro.
  @override
  Future<Either<Failure, VerifyOtpResponse>> setPassword(
      String password) async {
    return const Right(VerifyOtpResponse(
      jwtToken: 'supabase_phone',
      profile: null,
      hasPassword: true,
      hasName: true,
      registrationRequired: false,
    ));
  }

  @override
  Future<Either<Failure, VerifyNumberResponse>> resendOtp(
      String mobileNumber) async {
    try {
      final phone = _pendingPhone;
      if (phone == null || phone.isEmpty) {
        return Left(Failure.server(message: 'Número de telefone não encontrado para reenvio.'));
      }
      await _supabase.auth.signInWithOtp(phone: phone);
      return Right(
        VerifyNumberResponse(
          hash: phone,
          isExistingUser: true, // We don't know this exactly here, but the UI only cares about success
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
    required String? email,
    required Gender? gender,
    required String? idNumber,
  }) async {
    try {
      // Para auth por telefone sem Firebase, usamos o número do estado pendente
      final phone = _pendingPhone;

      final updateData = <String, dynamic>{
        'full_name': '$firstName $lastName'.trim(),
        'email': email,
        'gender': gender?.name ?? 'unknown',
        'id_number': idNumber,
        'status': 'Enabled',
        'role': 'rider',
      };

      if (phone != null) {
        // Verifica se já existe uma linha com esse telefone
        final existing = await _supabase
            .from('profiles')
            .select('id')
            .eq('phone', phone)
            .maybeSingle();

        if (existing != null) {
          // Já existe a row, apenas atualiza via EF (o EF pega o uid do JWT)
          await _supabase.functions.invoke(
            'sync-profile',
            body: updateData,
          );
        } else {
          // Usa o UID da sessão criada em verifyOtp (se não for criado, EF vai falhar, e tudo bem, é protegido)
          await _supabase.functions.invoke(
            'sync-profile',
            body: updateData,
          );
        }
      }

      final row = await _supabase
          .from('profiles')
          .select()
          .eq('phone', phone ?? '')
          .maybeSingle();
      final userData = row ?? {};

      return Right(ProfileEntity(
        firstName: firstName,
        lastName: lastName,
        email: userData['email'] as String?,
        idNumber: userData['id_number'] as String?,
        countryCode: 'BR',
        gender: gender,
        profileImage: null,
        presetProfileImage: null,
        number: userData['phone'] as String? ?? phone ?? '',
      ));
    } catch (e) {
      debugPrint('updateProfile catch: $e');
      return Left(Failure.server(message: 'Erro ao salvar perfil: $e'));
    }
  }
}
