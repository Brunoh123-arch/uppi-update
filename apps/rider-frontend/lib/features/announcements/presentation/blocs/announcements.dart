import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_common/core/entities/announcement.dart';
import '../../domain/repositories/announcements_repository.dart';

part 'announcements.event.dart';
part 'announcements.state.dart';
part 'announcements.freezed.dart';

@lazySingleton
class AnnouncementsBloc extends Cubit<AnnouncementsState> {
  final AnnouncementsRepository _repository;
  StreamSubscription? _subscription;

  AnnouncementsBloc(this._repository)
      : super(const AnnouncementsState.initial());

  void load() {
    emit(const AnnouncementsState.loading());
    _subscription?.cancel();
    _subscription = _repository.startAnnouncementsSubscription().listen((result) {
      result.fold(
        (failure) => emit(AnnouncementsState.error(failure.errorMessage)),
        (announcements) => announcements.isEmpty
            ? emit(const AnnouncementsState.empty())
            : emit(AnnouncementsState.loaded(announcements)),
      );
    });
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
