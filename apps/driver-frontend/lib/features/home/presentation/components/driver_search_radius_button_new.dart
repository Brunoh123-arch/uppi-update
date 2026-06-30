import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/blocs/auth_bloc.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/config/constants.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/enums/measurement_system.dart';
import 'package:ionicons/ionicons.dart';

import '../blocs/home.dart';

class DriverSearchRadiusButtonNew extends StatelessWidget {
  const DriverSearchRadiusButtonNew({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeBloc, HomeState>(
      builder: (context, state) {
        return state.driverStatus.maybeMap(
          orElse: () => const SizedBox(),
          online: (online) {
            if (online.orderRequests.isNotEmpty) {
              return const SizedBox();
            }
            return BlocBuilder<AuthBloc, AuthState>(
              bloc: locator<AuthBloc>(),
              builder: (context, stateAuth) {
                return stateAuth.maybeMap(
                  orElse: () => const SizedBox(),
                  authenticated: (authenticated) {
                    final radius = authenticated.profile.searchRadius;
                    return Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: ColorPalette.neutralVariant99,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1464748B),
                            blurRadius: 8,
                            offset: Offset(2, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                           CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: (radius ?? 0) > 99000
                                ? null
                                : () {
                                    const measurementSystem =
                                        Constants.defaultMeasurementSystem;
                                    if (measurementSystem ==
                                        MeasurementSystem.metric) {
                                      onRadiusChanged((radius ?? 0) + 1000);
                                    } else {
                                      onRadiusChanged((radius ?? 0) + 1609);
                                    }
                                  },
                            minimumSize: Size(0, 0),
                            child: Icon(
                              Ionicons.add_circle,
                              color: (radius ?? 0) > 99000
                                  ? ColorPalette.neutral80
                                  : ColorPalette.primary40,
                              size: 24,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            radius == null
                                ? '∞'
                                : (radius).toFormattedDistance(context),
                            style: context.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: ColorPalette.neutral20,
                            ),
                          ),
                          const SizedBox(height: 6),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: (radius ?? 0) < 1000
                                ? null
                                : () {
                                    const measurementSystem =
                                        Constants.defaultMeasurementSystem;
                                    if (measurementSystem ==
                                        MeasurementSystem.metric) {
                                      final newRadius = (radius ?? 0) - 1000;
                                      onRadiusChanged(newRadius < 1000 ? 1000 : newRadius);
                                    } else {
                                      final newRadius = (radius ?? 0) - 1609;
                                      onRadiusChanged(newRadius < 1609 ? 1609 : newRadius);
                                    }
                                  },
                            minimumSize: Size(0, 0),
                            child: Icon(
                              Ionicons.remove_circle,
                              color: (radius ?? 0) < 1000
                                  ? ColorPalette.neutral80
                                  : ColorPalette.primary40,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  void onRadiusChanged(int? radius) {
    locator<AuthBloc>().changeSearchRadius(radius);
  }
}
