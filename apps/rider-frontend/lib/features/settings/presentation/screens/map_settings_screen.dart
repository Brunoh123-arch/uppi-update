import 'package:auto_route/auto_route.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:generic_map/generic_map.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:flutter_common/core/blocs/settings.dart';
import 'package:flutter_common/features/settings/presentation/screens/map_settings_screen.dart';
import 'package:rider_flutter/gen/assets.gen.dart';

@RoutePage()
class MapSettingsScreen extends StatelessWidget {
  const MapSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      buildWhen: (previous, current) => previous.mapProvider != current.mapProvider,
      builder: (context, state) {
        return SharedMapSettingsScreen(
          selectedMapProvider: state.mapProvider ?? MapProviderEnum.googleMaps,
          onMapProviderChanged: (provider) => locator<SettingsCubit>().changeMapProvider(provider),
          mapBoxImage: Assets.images.backgroundDotted.provider(),
          openStreetMapImage: Assets.images.backgroundDotted.provider(),
          googleMapsImage: Assets.images.backgroundDotted.provider(),
        );
      },
    );
  }
}
