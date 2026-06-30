import 'package:dartz/dartz.dart';
import 'package:uppi_motorista/core/datasources/firebase_datasource.dart';
import 'package:uppi_motorista/core/enums/driver_status.dart';
import 'package:uppi_motorista/core/error/failure.dart';
import 'package:flutter_common/core/entities/media.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_common/core/entities/wallet.dart';

import 'package:uppi_motorista/core/utils/status_parser.dart';

import '../entities/profile.dart';
import 'profile_repository.dart';

@prod
@LazySingleton(as: ProfileRepository)
class ProfileRepositoryProd implements ProfileRepository {
  final FirebaseDatasource firebaseDatasource;
  final SupabaseClient supabaseClient;

  ProfileRepositoryProd(this.firebaseDatasource)
    : supabaseClient = Supabase.instance.client;

  @override
  Future<Either<Failure, ProfileEntity>> getProfile() async {
    try {
      final uid = supabaseClient.auth.currentUser?.id;
      if (uid == null) return Left(Failure.server(message: 'Não autenticado'));

      // Busca o perfil do motorista na tabela 'profiles' do Supabase
      final data = await supabaseClient
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();

      if (data == null) {
        return Left(Failure.server(message: 'Perfil não encontrado'));
      }

      MediaEntity? profilePicture;
      if (data['avatar_url'] != null) {
        profilePicture = MediaEntity(id: '', address: data['avatar_url']);
      }

      final st = data['status']?.toString();
      final role = data['role']?.toString();
      final isApproved = data['is_approved'] == true;
      DriverStatus driverStatus = role == 'driver'
          ? StatusParser.fromString(st)
          : const DriverStatus.pendingSubmission();

      if (isApproved && driverStatus == const DriverStatus.pendingApproval()) {
        driverStatus = const DriverStatus.online();
      }

      // Divide o full_name para compatibilidade com o formato esperado
      final fullName = data['full_name']?.toString() ?? '';
      final nameParts = fullName.split(' ');
      final firstName = nameParts.isNotEmpty ? nameParts.first : '';
      final lastName = nameParts.length > 1
          ? nameParts.sublist(1).join(' ')
          : '';

      final walletData = await supabaseClient
          .from('wallets')
          .select('balance')
          .eq('user_id', uid)
          .maybeSingle();
      final balance = (walletData?['balance'] as num?)?.toDouble() ?? 0.0;
      final wallet = WalletEntity(
        balance: balance,
        currency: 'BRL',
      );

      return Right(
        ProfileEntity(
          firstName: firstName,
          lastName: lastName,
          countryCode:
              'BR', // Supabase migration padroniza isso ou usa outra fonte
          gender: null,
          email: data['email']?.toString(),
          status: driverStatus,
          number: data['phone_number']?.toString() ?? '',
          searchRadius: data['search_radius'] as int? ?? 5000,
          profilePicture: profilePicture,
          orders: [],
          wallets: [wallet],
        ),
      );
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }

  @override
  Stream<Either<Failure, ProfileEntity>> startProfileSubscription() async* {
    final uid = supabaseClient.auth.currentUser?.id;
    if (uid == null) {
      yield Left(Failure.server(message: 'User not authenticated'));
      yield* const Stream.empty();
      return;
    }

    yield* supabaseClient
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', uid)
        .asyncMap((_) async {
      return await getProfile();
    });
  }

  @override
  Future<Either<Failure, ProfileEntity>> updateRadius({
    required int? radius,
  }) async {
    try {
      final uid = supabaseClient.auth.currentUser?.id;
      if (uid == null) throw Exception("User not authenticated");

      // Garante que nunca envia null — mínimo 1000m
      final safeRadius = (radius != null && radius >= 1000) ? radius : 1000;

      await supabaseClient.functions.invoke(
        'sync-profile',
        body: {'search_radius': safeRadius},
      );

      // Reutiliza getProfile() para retornar o perfil completo
      // (evita perder wallet, status, email etc.)
      return await getProfile();
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteAccount() async {
    try {
        await supabaseClient.functions.invoke('delete-user-account');
      await firebaseDatasource.signOut();
      return const Right(null);
    } catch (e) {
      return Left(Failure.server(message: e.toString()));
    }
  }
}
