import 'package:dartz/dartz.dart';
import 'package:flutter_common/core/entities/media.dart';
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/datasources/firebase_datasource.dart';
import 'package:rider_flutter/core/entities/profile.dart';
import 'package:flutter_common/core/enums/gender.dart';
import 'package:rider_flutter/core/error/failure.dart';
import 'package:rider_flutter/core/repositories/profile_repository.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

@prod
@LazySingleton(as: ProfileRepository)
class ProfileRepositoryProd implements ProfileRepository {
  final FirebaseDatasource firebaseDatasource;

  ProfileRepositoryProd(this.firebaseDatasource);

  @override
  Future<Either<Failure, ProfileEntity>> getProfile() async {
    try {
      final uid = firebaseDatasource.uid;
      if (uid == null) {
        return Left(Failure.serverError('Usuário não autenticado'));
      }

      final supabaseClient = Supabase.instance.client;
      final userData = await supabaseClient
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();

      if (userData == null) {
        return Left(Failure.serverError('Perfil não encontrado'));
      }

      MediaEntity? profileImage;
      if (userData['avatar_url'] != null) {
        profileImage = MediaEntity(id: '', address: userData['avatar_url']);
      }

      final fullName = userData['full_name']?.toString() ?? '';
      final nameParts = fullName.split(' ');
      final firstName = nameParts.isNotEmpty ? nameParts.first : '';
      final lastName =
          nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

      return Right(ProfileEntity(
        firstName: firstName,
        lastName: lastName,
        countryCode: 'BR',
        email: userData['email'] as String?,
        gender: _parseGender(userData['gender'] as String?),
        profileImage: profileImage,
        presetProfileImage: userData['preset_avatar_number'] as int?,
        number: userData['phone'] as String? ?? '',
        idNumber: userData['id_number'] as String?,
      ));
    } catch (e) {
      return Left(Failure.serverError(e.toString()));
    }
  }

  @override
  Stream<Either<Failure, ProfileEntity>> startProfileSubscription() async* {
    final uid = firebaseDatasource.uid;
    if (uid == null) {
      yield Left(Failure.serverError('User not authenticated'));
      return;
    }

    final supabaseClient = Supabase.instance.client;
    yield* supabaseClient
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', uid)
        .asyncMap((_) async {
      return await getProfile();
    });
  }

  Gender? _parseGender(String? gender) {
    switch (gender) {
      case 'Male':
        return Gender.male;
      case 'Female':
        return Gender.female;
      default:
        return null;
    }
  }
}
