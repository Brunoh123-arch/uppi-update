import 'package:flutter/material.dart';
import 'package:flutter_common/core/extensions/extensions.dart';

import '../../domain/entities/onboarding.dart';

class OnboardingFormBuilder {
  final int onboardingItemIndex;

  const OnboardingFormBuilder({required this.onboardingItemIndex});

  Widget buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: onBoardingItem(context).image.image(),
    );
  }

  Widget buildFooter(BuildContext context) {
    return buildInformationFooter(context);
  }

  Widget buildInformationFooter(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          onBoardingItem(context).title,
          style: context.headlineSmall?.copyWith(
            color: context.theme.colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          onBoardingItem(context).description,
          style: context.bodyMedium?.copyWith(
            color: context.theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  OnBoardingItem onBoardingItem(BuildContext context) {
    final items = onboardingItems(context);
    if (onboardingItemIndex >= items.length) {
      return items.last;
    }
    return items[onboardingItemIndex];
  }
}
