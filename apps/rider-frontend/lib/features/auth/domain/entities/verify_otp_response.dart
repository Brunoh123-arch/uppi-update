import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:rider_flutter/core/entities/profile.dart';

part 'verify_otp_response.freezed.dart';

/// Resposta do OTP. O uso de factories extras (success/registrationRequired)
/// seria com freezed union, mas como o arquivo gerado ainda usa a versão base,
/// usamos campos booleanos para distinguir os estados.
@freezed
class VerifyOtpResponse with _$VerifyOtpResponse {
  const factory VerifyOtpResponse({
    required String jwtToken,
    required ProfileEntity? profile,
    required bool hasPassword,
    required bool hasName,

    /// true = usuário novo, precisa completar cadastro
    @Default(false) bool registrationRequired,
  }) = _VerifyOtpResponse;
}
