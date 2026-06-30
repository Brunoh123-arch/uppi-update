import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/my_location_button.dart'
    as button;
import 'package:ionicons/ionicons.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/blocs/location.dart';
import 'package:flutter_common/core/blocs/settings.dart';
import 'package:rider_flutter/core/datasources/geo_datasource.dart';
import 'package:rider_flutter/features/home/features/track_order/presentation/screens/order_in_progress_sheet.dart';
import 'package:rider_flutter/features/home/presentation/components/home_map.dart';

import '../blocs/home.dart';

class AppMyLocationButton extends StatelessWidget {
  const AppMyLocationButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        return state.maybeMap(
          orElse: () => const SizedBox.shrink(),
          welcome: (_) => button.MyLocationButton(
            onPressed: () async {
              final settingsState = locator<SettingsCubit>().state;
              final location =
                  await locator<GeoDatasource>().getCurrentLocation(
                language: settingsState.locale,
                mapProvider: settingsState.mapProviderEnum,
              );
              location.fold((l) {
                final myLocation = locator<LocationCubit>().state.place;
                if (myLocation != null) {
                  locator<HomeCubit>().onMapMoved(selectedLocation: myLocation);
                  HomeMap.centerOnUserLocationTrigger.value++;
                }
              }, (r) {
                locator<HomeCubit>().onMapMoved(selectedLocation: r);
                HomeMap.centerOnUserLocationTrigger.value++;
              });
            },
          ),
          rideInProgress: (value) {
            if (value.driverLocation == null) return const SizedBox.shrink();
            return CupertinoButton(
              onPressed: () {
                HomeMap.trackDriverTrigger.value++;
                try {
                  OrderInProgressSheet.isMinimizedNotifier.value = true;
                } catch (_) {}
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: ColorPalette.neutral99,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1464748B),
                      blurRadius: 8,
                      offset: Offset(2, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Ionicons.car_sport,
                      color: ColorPalette.neutral30,
                      size: 20,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Rastrear motorista',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: ColorPalette.neutral30,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
