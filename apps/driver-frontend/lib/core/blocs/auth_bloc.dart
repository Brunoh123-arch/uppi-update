import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:flutter_common/core/entities/wallet.dart';

import '../entities/profile.dart';
import '../repositories/profile_repository.dart';
import '../error/failure.dart';

part 'auth_bloc.state.dart';
part 'auth_bloc.freezed.dart';
part 'auth_bloc.g.dart';

@lazySingleton
class AuthBloc extends HydratedCubit<AuthState> {
  final ProfileRepository profileRepository;
  StreamSubscription<dynamic>? _supabaseAuthSub;
  StreamSubscription<Either<Failure, ProfileEntity>>? _profileSubscription;
  int? _expectedSearchRadius;
  int _searchRadiusRequestToken = 0;
  final Completer<bool> sessionRestored = Completer<bool>();

  AuthBloc(this.profileRepository) : super(const AuthState.unauthenticated()) {
    _startAuthListeners();
    // UPPI BRASIL: Evita travamento de 4s na Splash Screen se não houver motorista logado
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        if (!sessionRestored.isCompleted) {
          sessionRestored.complete(false);
        }
      }
    } catch (_) {}
  }

  @override
  Future<void> close() {
    _profileSubscription?.cancel();
    _walletSubscription?.cancel();
    _supabaseAuthSub?.cancel();
    return super.close();
  }

  /// UPPI BRASIL: Escuta mudanças de auth em tempo real e lida com a restauração de sessão reativa do motorista.
  void _startAuthListeners() {
    _supabaseAuthSub?.cancel();
    // Supabase Auth listener (para sessões Supabase)
    _supabaseAuthSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final session = data.session;
      final user = session?.user;

      if (user != null) {
        final curState = state;
        final bool alreadyAuthenticated = curState.map(
          unauthenticated: (_) => false,
          authenticated: (authed) => authed.jwtToken == user.id,
        );

        if (!alreadyAuthenticated) {
          debugPrint('[AuthBloc-Driver] Supabase user detectado (${user.id}), recuperando perfil...');
          try {
            final profile = await profileRepository.getProfile();
            profile.fold(
              (failure) {
                debugPrint('[AuthBloc-Driver] Perfil não encontrado ou erro no DB ($failure), mantendo sessão ativa para onboarding.');
                emit(const AuthState.unauthenticated());
                if (!sessionRestored.isCompleted) {
                  sessionRestored.complete(false);
                }
              },
              (profileEntity) {
                _updatePushToken();
                _startWalletSubscription();
                emit(AuthState.authenticated(
                  jwtToken: user.id,
                  profile: profileEntity,
                ));
                requestUserInfo();
                if (!sessionRestored.isCompleted) {
                  sessionRestored.complete(true);
                }
              },
            );
          } catch (e) {
            debugPrint('[AuthBloc-Driver] Erro ao recuperar perfil: $e');
            if (!sessionRestored.isCompleted) {
              sessionRestored.complete(false);
            }
          }
        } else {
          if (!sessionRestored.isCompleted) {
            sessionRestored.complete(true);
          }
        }
      } else {
        if (state is _Authenticated) {
          debugPrint('[AuthBloc-Driver] Supabase signedOut ou sem sessão — emitindo unauthenticated');
          emit(const AuthState.unauthenticated());
        }
        if (!sessionRestored.isCompleted) {
          sessionRestored.complete(false);
        }
      }
    }, onError: (err) {
      debugPrint('[AuthBloc-Driver] Erro no stream de auth: $err');
      if (!sessionRestored.isCompleted) {
        sessionRestored.complete(false);
      }
    });
  }

  @override
  AuthState? fromJson(Map<String, dynamic> json) => AuthState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(AuthState state) {
    final map = state.toJson();
    if (map['runtimeType'] == 'authenticated') {
      map['jwtToken'] = '';
    }
    return map;
  }

  StreamSubscription<List<Map<String, dynamic>>>? _walletSubscription;

  void _startWalletSubscription() {
    _walletSubscription?.cancel();
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    _walletSubscription = Supabase.instance.client
        .from('wallets')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .listen((event) {
          if (event.isNotEmpty) {
            final data = event.first;
            final balance = (data['balance'] as num?)?.toDouble() ?? 0.0;
            state.mapOrNull(
              authenticated: (authenticated) {
                final wallet = WalletEntity(
                  balance: balance,
                  currency: 'BRL',
                );
                emit(authenticated.copyWith(
                  profile: authenticated.profile.copyWith(wallets: [wallet]),
                ));
              },
            );
          }
        });
  }

  void onLoggedIn({required String jwtToken, required ProfileEntity profile}) {
    _updatePushToken();
    _startWalletSubscription();
    emit(AuthState.authenticated(jwtToken: jwtToken, profile: profile));
    requestUserInfo();
  }

  void requestUserInfo() {
    state.mapOrNull(
      authenticated: (authenticated) {
        _profileSubscription?.cancel();
        _profileSubscription = profileRepository.startProfileSubscription().listen((profileOrFailure) {
          profileOrFailure.fold(
            (l) {
               // Do nothing or handle failure
            },
            (r) {
              final curState = state;
              if (curState is! _Authenticated) return;
              _updatePushToken();
              final updatedProfile = _expectedSearchRadius != null
                  ? r.copyWith(searchRadius: _expectedSearchRadius)
                  : r;
              emit(AuthState.authenticated(
                jwtToken: curState.jwtToken,
                profile: updatedProfile,
              ));
            },
          );
        });
      },
    );
  }

  void changeSearchRadius(int? radius) {
    state.mapOrNull(
      authenticated: (authenticated) {
        // ── Atualização OTIMISTA: muda na UI na hora ──
        final safeRadius = (radius != null && radius >= 1000) ? radius : 1000;
        final oldRadius = authenticated.profile.searchRadius;
        _expectedSearchRadius = safeRadius;
        final currentToken = ++_searchRadiusRequestToken;
        debugPrint('[AuthBloc] changeSearchRadius: $oldRadius → $safeRadius (token: $currentToken)');
        emit(authenticated.copyWith(
          profile: authenticated.profile.copyWith(
            searchRadius: safeRadius,
          ),
        ));

        // ── Persiste no servidor em background ──
        profileRepository.updateRadius(radius: safeRadius).then((result) {
          if (currentToken != _searchRadiusRequestToken) {
            debugPrint('[AuthBloc] Ignorando resposta obsoleta de raio de busca (token $currentToken, atual $_searchRadiusRequestToken)');
            return;
          }
          result.fold(
            (failure) {
              debugPrint('[AuthBloc] Falha ao salvar raio no servidor: ${failure.message}');
              // Reverte se falhou
              _expectedSearchRadius = null;
              final currentState = state;
              if (currentState is _Authenticated) {
                emit(currentState.copyWith(
                  profile: currentState.profile.copyWith(
                    searchRadius: oldRadius,
                  ),
                ));
              }
            },
            (updatedProfile) {
              debugPrint('[AuthBloc] Raio salvo no servidor: ${updatedProfile.searchRadius}');
              _expectedSearchRadius = null;
              final currentState = state;
              if (currentState is _Authenticated) {
                emit(currentState.copyWith(
                  profile: updatedProfile,
                ));
              }
            },
          );
        });
      },
    );
  }

  void onLoggedOut() async {
    try {
      // 1. Seta o status do motorista para offline no backend
      await Supabase.instance.client.functions.invoke(
        'update-driver-status',
        body: {'status': 'offline'},
      );
    } catch (_) {}
    try {
      // 2. Desassocia o token FCM no backend para evitar vazamento de notificações push pós-logout
      await Supabase.instance.client.functions.invoke(
        'update-fcm-token',
        body: {'token': null},
      );
    } catch (_) {}
    await Supabase.instance.client.auth.signOut();
    emit(const AuthState.unauthenticated());
  }

  Future<void> _updatePushToken() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (_) {}

      if (fcmToken != null) {
        try {
          await Supabase.instance.client.functions.invoke(
            'update-fcm-token',
            body: {'token': fcmToken},
          );
        } catch (_) {}
      }
    } catch (_) {}
  }
}
