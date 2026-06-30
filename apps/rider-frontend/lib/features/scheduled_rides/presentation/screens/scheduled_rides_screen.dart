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
import 'package:rider_flutter/features/scheduled_rides/presentation/components/empty_state.dart';
import 'package:rider_flutter/features/scheduled_rides/presentation/components/list_item.dart';
import 'package:flutter_common/core/presentation/common_skeletons.dart';

import '../blocs/scheduled_rides.dart';

@RoutePage()
class ScheduledRidesScreen extends StatefulWidget {
  const ScheduledRidesScreen({super.key});

  @override
  State<ScheduledRidesScreen> createState() => _ScheduledRidesScreenState();
}

class _ScheduledRidesScreenState extends State<ScheduledRidesScreen> {
  @override
  void initState() {
    locator<ScheduledRidesBloc>().load();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: locator<ScheduledRidesBloc>(),
      child: Container(
        color: context.theme.scaffoldBackgroundColor,
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              context.responsive(
                AppBackButton(
                  onPressed: () {
                    context.router.maybePop();
                  },
                ),
                xl: const SizedBox.shrink(),
              ),
              SizedBox(height: context.responsive(16, xl: 84)),
              Text(
                context.translate.scheduledRides,
                style: context.headlineSmall,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: BlocBuilder<ScheduledRidesBloc, ScheduledRidesState>(
                    builder: (context, state) {
                  return AnimatedSwitcher(
                    duration: AnimationDuration.pageStateTransitionDesktop,
                    child: state.map(
                      initial: (_) => const SizedBox.shrink(),
                      loading: (_) => const ScheduledRidesSkeleton(),
                      loaded: (loaded) {
                        return RefreshIndicator(
                          onRefresh: () async => locator<ScheduledRidesBloc>().load(),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemBuilder: (context, index) {
                              return ScheduledRidesListItem(
                                entity: loaded.data[index],
                                onPressed: () async {
                                  await context.router.push(
                                    ScheduledRideDetailsRoute(
                                      entity: loaded.data[index],
                                    ),
                                  );
                                  locator<ScheduledRidesBloc>().load();
                                },
                              );
                            },
                            separatorBuilder: (context, index) {
                              return const SizedBox(height: 16);
                            },
                            itemCount: loaded.data.length,
                          ),
                        );
                      },
                      empty: (_) => const ScheduledRidesEmptyState(),
                      error: (error) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Ionicons.alert_circle_outline, size: 48, color: ColorPalette.error40),
                            const SizedBox(height: 12),
                            Text(error.message, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            AppTextButton(
                              onPressed: () => locator<ScheduledRidesBloc>().load(),
                              text: 'Tentar novamente',
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              )
            ],
          ),
        ),
      ),
    );
  }
}
