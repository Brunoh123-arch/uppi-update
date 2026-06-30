import 'package:dartz/dartz.dart';
import 'package:uppi_motorista/core/enums/driver_status.dart';
import 'package:flutter_common/core/entities/media.dart';
import 'package:flutter_common/core/enums/gender.dart';
import 'package:flutter_common/features/country_code_dialog/domain/entities/country_code.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter_common/core/entities/wallet.dart';

import 'order.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

@freezed
class ProfileEntity with _$ProfileEntity {
  const factory ProfileEntity({
    required String? firstName,
    required String? lastName,
    required DriverStatus status,
    required Gender? gender,
    required String? email,
    required String? countryCode,
    required MediaEntity? profilePicture,
    required String number,
    required int? searchRadius,
    required List<WalletEntity> wallets,
    required List<OrderEntity> orders,
    String? certificateNumber,
    List<MediaEntity>? documents,
  }) = _ProfileEntity;

  factory ProfileEntity.fromJson(Map<String, dynamic> json) =>
      _$ProfileEntityFromJson(json);

  static ProfileEntity get emptyProfile => const ProfileEntity(
    firstName: null,
    lastName: null,
    countryCode: 'BR',
    gender: null,
    email: null,
    status: DriverStatus.offline(),
    number: '',
    searchRadius: 5000,
    profilePicture: null,
    orders: [],
    wallets: [],
  );

  const ProfileEntity._();

  String get fullName => '$firstName $lastName';

  Option<Either<String, String>> get avatar {
    if (profilePicture != null) {
      return Some(Right(profilePicture!.address));
    } else {
      return const None();
    }
  }

  String get mobileNumberFormatted {
    if (countryCode?.isEmpty == false) {
      final country = CountryCode.parseByIso(countryCode!);
      final dialCode = country.e164CC;
      final mobileNumber = (number.startsWith(dialCode))
          ? number.substring(dialCode.length)
          : number;
      return '+$dialCode $mobileNumber';
    } else {
      return "+$number";
    }
  }

  WalletEntity? get mainWallet {
    if (wallets.isEmpty) {
      return null;
    } else {
      return wallets.reduce(
        (value, element) => value.balance > element.balance ? value : element,
      );
    }
  }
}
