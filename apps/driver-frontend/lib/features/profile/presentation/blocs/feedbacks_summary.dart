import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../data/models/feedbacks_summary.dart';
import '../../domain/repositories/profile_repository.dart';

part 'feedbacks_summary.state.dart';
part 'feedbacks_summary.freezed.dart';

@lazySingleton
class FeedbacksSummaryCubit extends Cubit<FeedbacksSummaryState> {
  final ProfileRepository _repository;
  StreamSubscription? _subscription;

  FeedbacksSummaryCubit(this._repository)
    : super(const FeedbacksSummaryState.initial());

  void load() {
    final isAlreadyLoaded = state.maybeMap(
      loaded: (_) => true,
      empty: (_) => true,
      orElse: () => false,
    );
    if (!isAlreadyLoaded) {
      emit(const FeedbacksSummaryState.loading());
    }
    _subscription?.cancel();
    _subscription =
        _repository.startFeedbacksSummarySubscription().listen((result) {
      result.fold(
        (failure) =>
            emit(FeedbacksSummaryState.error(errorMessage: failure.toString())),
        (summary) {
          if (summary.averageRating == null) {
            emit(const FeedbacksSummaryState.empty());
            return;
          }
          emit(FeedbacksSummaryState.loaded(summary: summary));
        },
      );
    });
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
