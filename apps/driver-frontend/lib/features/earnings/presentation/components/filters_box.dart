import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/features/earnings/domain/enums/earnings_timeframe.dart';
import 'package:uppi_motorista/features/earnings/presentation/blocs/earnings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:ionicons/ionicons.dart';

class FiltersBox extends StatelessWidget {
  final VoidCallback? onTotalPressed;

  const FiltersBox({super.key, this.onTotalPressed});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 40),
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: BlocBuilder<EarningsBloc, EarningsState>(
              builder: (context, state) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SegmentedButton<EarningsTimeFrame?>(
                      onSelectionChanged: (value) =>
                          locator<EarningsBloc>().setTimeFrame(value.first!),
                      segments: [
                        ButtonSegment(
                          value: EarningsTimeFrame.monthly,
                          label: Text(context.translate.monthly),
                        ),
                        ButtonSegment(
                          value: EarningsTimeFrame.weekly,
                          label: Text(context.translate.weekly),
                        ),
                        ButtonSegment(
                          value: EarningsTimeFrame.daily,
                          label: Text(context.translate.daily),
                        ),
                      ],
                      selected: {state.timeframe},
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CupertinoButton(
                          onPressed: state.canGoBack
                              ? () =>
                                    locator<EarningsBloc>().previousTimeframe()
                              : null,
                          child: const Icon(Ionicons.chevron_back),
                        ),
                        Column(
                          children: [
                            Text(
                              "${state.startDate.formatDate(context)}-${state.endDate.formatDate(context)}",
                              style: context.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            state.pageState.maybeMap(
                              orElse: () => const SizedBox(),
                              loaded: (value) => CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: onTotalPressed,
                                child: Text(
                                  value.dataset.totalEarnings.formatCurrency(
                                    value.dataset.currency,
                                  ),
                                  style: context.headlineMedium,
                                ),
                              ),
                            ),
                          ],
                        ),
                        CupertinoButton(
                          onPressed: state.canGoForward
                              ? () => locator<EarningsBloc>().nextTimeframe()
                              : null,
                          child: const Icon(Ionicons.chevron_forward),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
