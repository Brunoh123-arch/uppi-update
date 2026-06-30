import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:injectable/injectable.dart';

import '../entities/profile.dart';
import '../repositories/profile_repository.dart';

part 'auth_bloc.state.dart';
part 'auth_bloc.freezed.dart';
part 'auth_bloc.g.dart';

@lazySingleton
class AuthBloc extends HydratedCubit<AuthState> {
  final ProfileRepository profileRepository;
  StreamSubscription? _profileSubscription;
  StreamSubscription? _supabaseAuthSub;
  Completer<bool> sessionRestored = Completer<bool>();

  AuthBloc(this.profileRepository) : super(const AuthState.unauthenticated()) {
    _startAuthListeners();
    // UPPI BRASIL: Evita travamento de 4s na Splash Screen se não houver usuário logado
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
    _supabaseAuthSub?.cancel();
    return super.close();
  }

  /// UPPI BRASIL: Escuta mudanças de auth em tempo real e lida com a restauração de sessão reativa.
  void _startAuthListeners() {
    _supabaseAuthSub?.cancel();
    _supabaseAuthSub =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final session = data.session;
      final user = session?.user;

      if (user != null) {
        final curState = state;
        final bool alreadyAuthenticated = curState.map(
          unauthenticated: (_) => false,
          authenticated: (authed) => authed.jwtToken == user.id,
        );

        if (!alreadyAuthenticated) {
          debugPrint(
              '[AuthBloc-Rider] Supabase user detectado (${user.id}), recuperando perfil...');
          try {
            var profileResult = await profileRepository.getProfile();

            // UPPI BRASIL: Se o usuário estiver autenticado no Supabase Auth mas sem registro na tabela de profiles,
            // tenta criar automaticamente chamando a Edge Function sync-profile.
            if (profileResult.isLeft()) {
              final failure = profileResult.fold((l) => l, (r) => null)!;
              if (failure.errorMessage.contains('Perfil não encontrado')) {
                debugPrint(
                    '[AuthBloc-Rider] Perfil não encontrado no banco de dados. Tentando auto-criar via sync-profile...');
                try {
                  await Supabase.instance.client.functions.invoke(
                    'sync-profile',
                    body: {
                      'full_name': user.userMetadata?['full_name'] ??
                          user.userMetadata?['name'] ??
                          'Usuário',
                      'email': user.email ?? '',
                    },
                  );
                  profileResult = await profileRepository.getProfile();
                } catch (e) {
                  debugPrint(
                      '[AuthBloc-Rider] Erro ao tentar auto-criar perfil: $e');
                }
              }
            }

            profileResult.fold(
              (failure) {
                debugPrint(
                    '[AuthBloc-Rider] Perfil não encontrado ou erro no DB ($failure), mantendo sessão ativa para onboarding.');
                emit(const AuthState.unauthenticated());
                if (!sessionRestored.isCompleted) {
                  sessionRestored.complete(false);
                }
              },
              (profileEntity) {
                _updatePushToken();
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
            debugPrint('[AuthBloc-Rider] Erro ao recuperar perfil: $e');
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
          debugPrint(
              '[AuthBloc-Rider] Supabase signedOut ou sem sessão — emitindo unauthenticated');
          emit(const AuthState.unauthenticated());
        }
        if (!sessionRestored.isCompleted) {
          sessionRestored.complete(false);
        }
      }
    }, onError: (err) {
      debugPrint('[AuthBloc-Rider] Erro no stream de auth: $err');
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

  void onLoggedIn({
    required String jwtToken,
    required ProfileEntity profile,
  }) {
    _updatePushToken();
    emit(
      AuthState.authenticated(
        jwtToken: jwtToken,
        profile: profile,
      ),
    );
    requestUserInfo();
  }

  void profileUpdated(ProfileEntity profile) {
    emit(
      state.map(
        unauthenticated: (unauthenticated) => throw Exception(
          'Unauthenticated user',
        ),
        authenticated: (authenticated) => authenticated.copyWith(
          profile: profile,
        ),
      ),
    );
  }

  void requestUserInfo() {
    state.mapOrNull(
      authenticated: (authenticated) {
        _profileSubscription?.cancel();
        _profileSubscription = profileRepository
            .startProfileSubscription()
            .listen((profileOrFailure) {
          profileOrFailure.fold(
            (l) {
              if (Supabase.instance.client.auth.currentUser == null) {
                emit(const AuthState.unauthenticated());
              }
            },
            (r) {
              final token = Supabase.instance.client.auth.currentUser?.id ?? '';
              _updatePushToken();
              emit(AuthState.authenticated(
                jwtToken: token,
                profile: r,
              ));
            },
          );
        });
      },
    );
  }

  void skipLogin() {
    emit(const AuthState.unauthenticated(isGuest: true));
  }

  void onLoggedOut() async {
    try {
      // UPPI BRASIL: Desassocia o token FCM no backend para evitar vazamento de notificações push pós-logout
      await Supabase.instance.client.functions.invoke(
        'update-fcm-token',
        body: {'token': null},
      );
    } catch (_) {}
    await Supabase.instance.client.auth.signOut();
    sessionRestored = Completer<bool>();
    emit(const AuthState.unauthenticated(isGuest: false));
  }

  Future<void> _updatePushToken() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Get FCM token
      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (_) {}

      // Also update FCM token directly in Supabase profiles
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
