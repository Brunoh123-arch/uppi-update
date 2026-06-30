import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:ionicons/ionicons.dart';

import '../blocs/home.dart';
import '../dialogs/launch_map_dialog.dart';

class NavigateButton extends StatelessWidget {
  const NavigateButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeBloc, HomeState>(
      builder: (context, state) {
        return state.driverStatus.maybeMap(
          orElse: () => const SizedBox(),
          onTrip: (onTripState) {
            final order = onTripState.order;
            final status = order.status;

            if (status == OrderStatus.driverCanceled ||
                status == OrderStatus.riderCanceled ||
                status == OrderStatus.finished ||
                status == OrderStatus.expired) {
              return const SizedBox();
            }

            if (order.waypoints.isEmpty) return const SizedBox();

            final PlaceEntity targetPlace;
            if (status == OrderStatus.driverAccepted || status == OrderStatus.arrived) {
              targetPlace = order.waypoints.first;
            } else {
              final index = order.destinationArrivedTo;
              if (index == null) {
                targetPlace = order.waypoints.first;
              } else if (index + 1 < order.waypoints.length) {
                targetPlace = order.waypoints[index + 1];
              } else {
                targetPlace = order.waypoints.last;
              }
            }

            return FloatingActionButton(
              heroTag: 'navigate_external_map',
              onPressed: () {
                showDialog(
                  context: context,
                  useSafeArea: false,
                  builder: (context) => LaunchMapDialog(place: targetPlace),
                );
              },
              backgroundColor: Colors.white,
              elevation: 4,
              shape: const CircleBorder(),
              child: const Icon(
                Ionicons.navigate,
                color: ColorPalette.primary40,
                size: 24,
              ),
            );
          },
        );
      },
    );
  }
}
