import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/gen/assets.gen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/presentation/empty_list_state.dart';

class FeedbacksSummaryEmptyState extends StatelessWidget {
  const FeedbacksSummaryEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return EmptyListState(
      imagePath: Assets.images.rideHistoryEmptyState.path,
      title: context.translate.feedbacksSummaryEmptyStateHeading,
      subTitle: context.translate.feedbacksSummaryEmptyStateTitle,
    );
  }
}
