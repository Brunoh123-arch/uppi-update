import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/features/profile/data/models/profile_aggregations_info.dart';

import '../../domain/repositories/profile_repository.dart';

part 'profile.state.dart';
part 'profile.freezed.dart';

@lazySingleton
class ProfileBloc extends Cubit<ProfileState> {
  final ProfileRepository _repository;
  StreamSubscription? _subscription;

  ProfileBloc(this._repository) : super(const ProfileState.initial());

  void load() {
    emit(const ProfileState.loading());
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
