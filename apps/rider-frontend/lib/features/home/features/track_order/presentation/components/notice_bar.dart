import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../presentation/blocs/home.dart';

class NoticeBar extends StatelessWidget {
  const NoticeBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        return state.maybeMap(
          orElse: () => const SizedBox(),
          rideInProgress: (value) {
            switch (value.order.status) {
              case OrderStatus.driverAccepted:
                return FutureBuilder<bool>(
                  future: _isDriverFinishingAnotherRide(value.order.driver?.mobileNumber, value.order.id),
                  builder: (context, finishingSnapshot) {
                    final isFinishingAnother = finishingSnapshot.data == true;
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            isFinishingAnother ? Ionicons.alert_circle : Ionicons.time,
                            color: isFinishingAnother ? ColorPalette.primary80 : ColorPalette.neutral70,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: isFinishingAnother
                                ? Text(
                                    "Terminando outra corrida antes de buscar você",
                                    style: context.labelMedium?.copyWith(
                                      color: ColorPalette.neutral99,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : StreamBuilder(
                                    stream: Stream.periodic(const Duration(seconds: 1)),
                                    builder: (BuildContext context,
                                        AsyncSnapshot<dynamic> snapshot) {
                                      return Text(
                                        value.order.etaPickup?.isAfter(DateTime.now()) ??
                                                false
                                            ? context.translate.driverShouldAriveInNotice
                                            : context
                                                .translate.driverShouldHaveArrivedNotice,
                                        style: context.labelMedium?.copyWith(
                                          color: ColorPalette.neutral99,
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          if (!isFinishingAnother) ...[
                            StreamBuilder(
                              stream: Stream.periodic(const Duration(seconds: 1)),
                              builder: (BuildContext context,
                                  AsyncSnapshot<dynamic> snapshot) {
                                if (value.order.etaPickup?.isBefore(DateTime.now()) ??
                                    true) {
                                  return const SizedBox();
                                }
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: ColorPalette.neutralVariant99,
                                    borderRadius: BorderRadius.circular(
                                      16,
                                    ),
                                  ),
                                  child: Text(
                                    _timeFromNow(
                                      context,
                                      value.order.etaPickup ?? DateTime.now(),
                                    ),
                                    style: context.labelSmall,
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    );
                  }
                );

              case OrderStatus.arrived:
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(
                        Ionicons.time,
                        color: ColorPalette.error60,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.translate.driverArrivedNotice,
                          style: context.labelMedium?.copyWith(
                            color: ColorPalette.neutral99,
                          ),
                        ),
                      ),
                    ],
                  ),
                );

              case OrderStatus.started:
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(
                        Ionicons.time,
                        color: ColorPalette.neutral70,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.translate.headingToDestination,
                          style: context.labelMedium?.copyWith(
                            color: ColorPalette.neutral99,
                          ),
                        ),
                      ),
                      if (value.order.etaPickup != null)
                        StreamBuilder(
                          stream: Stream.periodic(const Duration(seconds: 1)),
                          builder: (context, state) {
                            final arrivalTime = value.order.etaPickup!.add(
                              Duration(
                                minutes: value.order.duration ~/ 60,
                              ),
                            );
                            if (arrivalTime.isBefore(DateTime.now())) {
                              return const SizedBox();
                            }
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: ColorPalette.neutralVariant99,
                                borderRadius: BorderRadius.circular(
                                  16,
                                ),
                              ),
                              child: Text(
                                _timeFromNow(
                                  context,
                                  arrivalTime,
                                ),
                                style: context.labelSmall,
                              ),
                            );
                          },
                        )
                    ],
                  ),
                );

              default:
                return const SizedBox();
            }
          },
        );
      },
    );
  }

  String _timeFromNow(BuildContext context, DateTime dateTime) {
    final difference = dateTime.difference(DateTime.now());
    if (difference.inMinutes > 0) {
      return context.translate.minutesRange(difference.inMinutes.toString());
    } else {
      return context.translate.secondsRange(difference.inSeconds.toString());
    }
  }

  Future<bool> _isDriverFinishingAnotherRide(String? driverId, String currentRideId) async {
    if (driverId == null || driverId.isEmpty) return false;
    try {
      final supa = Supabase.instance.client;
      final res = await supa
          .from('rides')
          .select('id')
          .eq('driver_id', driverId)
          .inFilter('status', ['accepted', 'arrived', 'in_progress'])
          .neq('id', currentRideId)
          .limit(1);
      return res != null && res.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
