import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/config/router/app_router.dart';
import 'package:flutter_common/core/theme/animation_duration.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/buttons/app_back_button.dart';
import 'package:flutter_common/core/presentation/buttons/app_text_button.dart';
import 'package:ionicons/ionicons.dart';
import 'package:rider_flutter/features/ride_history/presentation/components/ride_history_item.dart';
import 'package:flutter_common/core/presentation/common_skeletons.dart';

import '../blocs/ride_history.dart';
import '../components/ride_history_empty_state.dart';

@RoutePage()
class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  @override
  void initState() {
    locator<RideHistoryBloc>().load();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: locator<RideHistoryBloc>(),
      child: Container(
        color: context.theme.scaffoldBackgroundColor,
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              context.responsive(
                AppBackButton(onPressed: () {
                  context.router.maybePop();
                }),
                xl: const SizedBox.shrink(),
              ),
              SizedBox(height: context.responsive(16, xl: 84)),
              Text(
                context.translate.rideHistory,
                style: context.headlineSmall,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: BlocBuilder<RideHistoryBloc, RideHistoryState>(
                    builder: (context, state) {
                  return AnimatedSwitcher(
                    duration: AnimationDuration.pageStateTransitionDesktop,
                    child: state.map(
                      initial: (_) => const SizedBox.shrink(),
                      loading: (_) => ListView.separated(
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          itemBuilder: (context, index) => const RideHistorySkeletonItem(),
                          separatorBuilder: (context, index) => const SizedBox(height: 16),
                          itemCount: 3,
                        ),
                      loaded: (loaded) {
                        return RefreshIndicator(
                          onRefresh: () async => locator<RideHistoryBloc>().load(),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemBuilder: (context, index) {
                              return RideHistoryItem(
                                entity: loaded.data[index],
                                onPressed: () => context.router.push(
                                  RideHistoryDetailsRoute(
                                      entity: loaded.data[index]),
                                ),
                              );
                            },
                            separatorBuilder: (context, index) {
                              return const SizedBox(height: 16);
                            },
                            itemCount: loaded.data.length,
                          ),
                        );
                      },
                      empty: (_) => const RideHistoryEmptyState(),
                      error: (error) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Ionicons.alert_circle_outline, size: 48, color: ColorPalette.error40),
                            const SizedBox(height: 12),
                            Text(error.message, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            AppTextButton(
                              onPressed: () => locator<RideHistoryBloc>().load(),
                              text: 'Tentar novamente',
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
