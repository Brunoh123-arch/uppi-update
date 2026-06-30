import 'package:auto_route/auto_route.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/config/router/app_router.dart';
import 'package:rider_flutter/features/auth/presentation/blocs/onboarding_cubit.dart';

class OnboardingGuard extends AutoRouteGuard {
  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final onboardingDone = locator<OnboardingCubit>().isDone;
    if (onboardingDone) {
      // Onboarding complete, allow navigation to role selection
      resolver.next(true);
    } else {
      // Onboarding not done, redirect to onboarding screen
      resolver.redirect(const OnboardingRoute());
    }
  }
}
