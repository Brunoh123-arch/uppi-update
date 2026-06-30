import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:uppi_motorista/core/entities/order.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';

import 'ride_history_details_screen.desktop.dart';
import 'ride_history_details_screen.mobile.dart';

@RoutePage(name: 'DriverRideHistoryDetailsRoute')
class RideHistoryDetailsScreen extends StatelessWidget {
  final OrderEntity entity;

  const RideHistoryDetailsScreen({super.key, required this.entity});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: context.responsive(
        RideHistoryDetailsScreenMobile(entity: entity),
        xl: RideHistoryDetailsScreenDesktop(entity: entity),
      ),
    );
  }
}
