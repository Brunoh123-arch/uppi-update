import 'package:auto_route/auto_route.dart';
import 'package:uppi_motorista/features/earnings/presentation/components/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter_common/core/theme/animation_duration.dart';
import 'package:flutter_common/core/utils/friendly_error.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:ionicons/ionicons.dart';
import 'package:uppi_motorista/features/earnings/domain/entities/earnings_dataset.dart';

import '../blocs/earnings.dart';
import '../components/earnings_header.dart';
import 'package:uppi_motorista/core/presentation/skeletons.dart';

@RoutePage(name: 'DriverEarningsRoute')
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  @override
  void initState() {
    locator<EarningsBloc>().load();
    super.initState();
  }

  void _showAllEarningsSheet(BuildContext context, EarningsDataset dataset) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: context.theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: EdgeInsets.only(
            top: 24,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Extrato Detalhado",
                    style: context.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    dataset.totalEarnings.formatCurrency(dataset.currency),
                    style: context.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: context.theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                "Total de corridas: ${dataset.totalRides} • Distância: ${dataset.totalDistanceTraveled.toFormattedDistance(context)}",
                style: context.bodyMedium?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Expanded(
                child: dataset.rides.isEmpty
                    ? Center(
                        child: Text(
                          "Nenhuma corrida registrada neste período.",
                          style: context.bodyLarge,
                        ),
                      )
                    : ListView.separated(
                        itemCount: dataset.rides.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (context, index) {
                          final ride = dataset.rides[index];
                          final isMoto = ride.serviceName.toLowerCase().contains("moto");
                          final iconData = isMoto ? Ionicons.bicycle : Ionicons.car;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: context.theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    iconData,
                                    color: context.theme.colorScheme.onPrimaryContainer,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        ride.serviceName,
                                        style: context.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "De: ${ride.pickupAddress}",
                                        style: context.bodySmall,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        "Para: ${ride.dropoffAddress}",
                                        style: context.bodySmall,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        ride.createdAt.formatDateTime,
                                        style: context.bodySmall?.copyWith(
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  ride.amount.formatCurrency(dataset.currency),
                                  style: context.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: locator<EarningsBloc>(),
      child: Container(
        color: context.theme.scaffoldBackgroundColor,
        padding: context.responsive(
          null,
          xl: const EdgeInsets.only(top: 104, left: 24, right: 24, bottom: 24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            context.responsive(
              const SizedBox(),
              xl: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  context.translate.earnings,
                  style: context.headlineSmall,
                ),
              ),
            ),
            Expanded(
              child: BlocBuilder<EarningsBloc, EarningsState>(
                builder: (context, state) {
                  return Column(
                    children: [
                      EarningsHeader(
                        dataset: state.pageState.mapOrNull(
                          loaded: (value) => value.dataset,
                        ),
                        onTotalPressed: state.pageState.maybeMap(
                          loaded: (value) => () => _showAllEarningsSheet(context, value.dataset),
                          orElse: () => null,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: AnimationDuration.pageStateTransitionMobile,
                          child: state.pageState.map(
                            empty: (value) => const EarningsEmptyState(),
                            initial: (_) => const SizedBox(),
                            error: (error) => Text(friendlyErrorMessage(error.errorMessage)),
                            loading: (value) => const EarningsSkeleton(),
                            loaded: (loaded) => Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Center(
                                      child: Container(
                                        height: 300,
                                        constraints: const BoxConstraints(
                                          maxWidth: 500,
                                        ),
                                        child: BarChart(
                                          loaded.dataset.barChartData,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    if (loaded.dataset.rides.isNotEmpty) ...[
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          "Corridas do Período",
                                          style: context.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      ListView.separated(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        itemCount: loaded.dataset.rides.length,
                                        separatorBuilder: (context, index) => const Divider(),
                                        itemBuilder: (context, index) {
                                          final ride = loaded.dataset.rides[index];
                                          final isMoto = ride.serviceName.toLowerCase().contains("moto");
                                          final iconData = isMoto ? Ionicons.bicycle : Ionicons.car;

                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: context.theme.colorScheme.primaryContainer,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Icon(
                                                    iconData,
                                                    color: context.theme.colorScheme.onPrimaryContainer,
                                                    size: 24,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        ride.serviceName,
                                                        style: context.titleSmall?.copyWith(
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        "De: ${ride.pickupAddress}",
                                                        style: context.bodySmall,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      Text(
                                                        "Para: ${ride.dropoffAddress}",
                                                        style: context.bodySmall,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        ride.createdAt.formatDateTime,
                                                        style: context.bodySmall?.copyWith(
                                                          color: Colors.grey,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  ride.amount.formatCurrency(loaded.dataset.currency),
                                                  style: context.titleSmall?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.green,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
