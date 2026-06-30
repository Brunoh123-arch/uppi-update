import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:uppi_motorista/features/profile/data/models/profile_aggregations_info.dart';

import '../../domain/repositories/profile_repository.dart';
import 'package:uppi_motorista/core/error/failure.dart';

part 'profile.state.dart';
part 'profile.freezed.dart';

@lazySingleton
class ProfileBloc extends Cubit<ProfileState> {
  final ProfileRepository _repository;
  StreamSubscription? _subscription;

  ProfileBloc(this._repository) : super(const ProfileState.initial());

  void load() {
    final isAlreadyLoaded = state.maybeMap(
      loaded: (_) => true,
      orElse: () => false,
    );
    if (!isAlreadyLoaded) {
      emit(const ProfileState.loading());
    }
    _subscription?.cancel();
    _subscription =
        _repository.startProfileAggregationsSubscription().listen((result) {
      result.fold(
        (error) => emit(ProfileState.error(error.errorMessage)),
        (data) => emit(ProfileState.loaded(data)),
      );
    });
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
