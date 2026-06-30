import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:injectable/injectable.dart';

@singleton
class OnboardingCubit extends HydratedCubit<int> {
  OnboardingCubit() : super(0);

  void nextPage() => emit(state >= 2 ? 2 : state + 1);

  void previousPage() => emit(state <= 0 ? 0 : state - 1);

  void reset() => emit(0);

  void skip() => emit(2);

  @override
  int? fromJson(Map<String, dynamic> json) {
    int val = json['onboarding'] as int? ?? 0;
    return val > 2 ? 2 : val;
  }

  @override
  Map<String, dynamic>? toJson(int state) {
    return {'onboarding': state};
  }
}

extension OnboardingCubitX on OnboardingCubit {
  bool get isDone => state >= 2;
}

