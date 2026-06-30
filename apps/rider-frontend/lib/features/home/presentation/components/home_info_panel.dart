import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/theme/animation_duration.dart';
import 'package:flutter_common/core/presentation/app_card_sheet.dart';
import 'package:rider_flutter/features/home/features/rate_order/presentation/screens/rate_your_ride_sheet.dart';
import 'package:rider_flutter/features/home/features/waypoints/presentation/screens/waypoints_input_sheet.dart';
import 'package:rider_flutter/features/home/features/welcome/presentation/screens/where_are_you_going_sheet.dart';
import 'package:flutter_common/core/presentation/common_skeletons.dart';

import '../../features/order_preview/presentation/screens/order_preview_sheet.dart';
import '../../features/place_confirm/presentation/screens/place_confirm_sheet.dart';
import '../../features/track_order/presentation/screens/track_order_sheet.dart';
import '../blocs/home.dart';

class HomeInfoPanel extends StatelessWidget {
  const HomeInfoPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        return AnimatedSwitcher(
          duration: AnimationDuration.pageStateTransitionMobile,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final slideAnimation = Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ));
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: slideAnimation,
                child: child,
              ),
            );
          },
          child: state.map(
            loading: (_) => const AppCardSheet(
              child: TransitionCardSkeleton(),
            ),
            welcome: (welcome) => WhereAreYouGoingSheet(
              waypoints: welcome.waypoints,
            ),
            inputWaypoints: (inputWaypoints) => WaypointsInputSheet(
              waypoints: inputWaypoints.waypoints,
            ),
            confirmLocation: (confirmLocation) => PlaceConfirmSheet(
              waypoints: confirmLocation.waypoints,
              index: confirmLocation.index,
              selectedLocation: confirmLocation.selectedLocation,
            ),
            ridePreview: (ridePreview) => OrderPreviewSheet(
              wayPoints: ridePreview.waypoints,
            ),
            rideInProgress: (rideInProgress) => TrackOrderSheet(
              order: rideInProgress.order,
              driverLocation: rideInProgress.driverLocation,
            ),
            rateDriver: (value) => RateYourRideSheet(
              order: value.order,
            ),
            error: (error) => Text(error.error),
          ),
        );
      },
    );
  }
}
