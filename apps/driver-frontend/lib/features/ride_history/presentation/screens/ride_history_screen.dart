import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/router/app_router.dart';
import 'package:flutter_common/core/theme/animation_duration.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/buttons/app_back_button.dart';

import '../blocs/ride_history.dart';
import '../components/ride_history_empty_state.dart';
import '../components/ride_history_item.dart';
import 'package:uppi_motorista/core/presentation/skeletons.dart';

@RoutePage(name: 'DriverRideHistoryRoute')
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
      child: SafeArea(
        child: Container(
          color: context.theme.scaffoldBackgroundColor,
          padding: const EdgeInsets.all(16),
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
              Text(context.translate.rideHistory, style: context.headlineSmall),
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
                          itemBuilder: (context, index) => const RideHistorySkeletonItem(showDriverInfo: false),
                          separatorBuilder: (context, index) => const SizedBox(height: 16),
                          itemCount: 3,
                        ),
                        loaded: (loaded) {
                          return ListView.separated(
                            padding: EdgeInsets.zero,
                            itemBuilder: (context, index) {
                              return RideHistoryItem(
                                entity: loaded.data[index],
                                onPressed: () => context.router.push(
                                  DriverRideHistoryDetailsRoute(
                                    entity: loaded.data[index],
                                  ),
                                ),
                              );
                            },
                            separatorBuilder: (context, index) {
                              return const SizedBox(height: 16);
                            },
                            itemCount: loaded.data.length,
                          );
                        },
                        empty: (_) =>
                            const Center(child: RideHistoryEmptyState()),
                        error: (error) => Center(child: Text(error.message)),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
