import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:rider_flutter/core/entities/favorite_driver.dart';
import 'package:rider_flutter/features/profile/domain/repositories/profile_repository.dart';

part 'favorite_drivers.state.dart';
part 'favorite_drivers.freezed.dart';

@lazySingleton
class FavoriteDriversCubit extends Cubit<FavoriteDriversState> {
  final ProfileRepository _repository;
  StreamSubscription? _subscription;

  FavoriteDriversCubit(this._repository)
      : super(const FavoriteDriversState.initial());

  void load() {
    emit(const FavoriteDriversState.loading());
    _subscription?.cancel();
    _subscription =
        _repository.startFavoriteDriversSubscription().listen((result) {
      result.fold(
        (l) => emit(FavoriteDriversState.error(message: l.errorMessage)),
        (r) => r.isEmpty
            ? emit(const FavoriteDriversState.empty())
            : emit(FavoriteDriversState.loaded(drivers: r)),
      );
    });
  }

  void delete(FavoriteDriverEntity entity) async {
    final result = await _repository.deleteFavoriteDriver(entity: entity);
    result.fold(
      (l) => emit(FavoriteDriversState.error(message: l.errorMessage)),
      // Stream auto-updates after delete
      (r) {},
    );
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
