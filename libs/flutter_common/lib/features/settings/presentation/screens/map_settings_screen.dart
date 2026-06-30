import 'package:flutter/material.dart';
import 'package:flutter_common/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_top_bar.dart';
import 'package:generic_map/generic_map.dart';
import '../components/map_settings_item.dart';

class SharedMapSettingsScreen extends StatefulWidget {
  final MapProviderEnum selectedMapProvider;
  final void Function(MapProviderEnum mapProvider) onMapProviderChanged;
  final ImageProvider mapBoxImage;
  final ImageProvider openStreetMapImage;
  final ImageProvider googleMapsImage;

  const SharedMapSettingsScreen({
    super.key,
    required this.selectedMapProvider,
    required this.onMapProviderChanged,
    required this.mapBoxImage,
    required this.openStreetMapImage,
    required this.googleMapsImage,
  });

  @override
  State<SharedMapSettingsScreen> createState() => _SharedMapSettingsScreenState();
}

class _SharedMapSettingsScreenState extends State<SharedMapSettingsScreen> {
  PageController? pageController;
  int activeId = 0;

  List<String> _getBenefits(BuildContext context, String provider) {
    final isPt = Localizations.localeOf(context).languageCode == 'pt';
    switch (provider) {
      case 'mapbox':
        return isPt 
            ? ["Design atraente", "Bom desempenho"] 
            : ["Attractive design", "Good performance"];
      case 'osm':
        return isPt 
            ? ["Gratuito", "Bom desempenho"] 
            : ["Free", "Good performance"];
      case 'google':
        return isPt 
            ? ["Melhor cobertura de locais", "Bom custo-benefício"] 
            : ["Best location coverage", "Good pricing"];
      default:
        return [];
    }
  }

  List<String> _getShortComings(BuildContext context, String provider) {
    final isPt = Localizations.localeOf(context).languageCode == 'pt';
    switch (provider) {
      case 'mapbox':
        return isPt 
            ? ["Custo elevado"] 
            : ["Expensive"];
      case 'osm':
        return isPt 
            ? ["Interface menos atraente"] 
            : ["Less Attractive UI"];
      case 'google':
        return isPt 
            ? ["Sem suporte para web e desktop", "Alguns bugs e problemas de performance conhecidos"] 
            : ["No support for web and desktop", "Some known bugs and performance issues"];
      default:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    pageController ??= PageController(
      viewportFraction: context.responsive(0.8, xl: 0.3),
    );
    
    return Container(
      color: context.theme.scaffoldBackgroundColor,
      padding: EdgeInsets.symmetric(
        horizontal: context.responsive(16, xl: 24),
        vertical: context.responsive(16, xl: 24),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            context.responsive(
              const SizedBox(),
              xl: const SizedBox(height: 80),
            ),
            AppTopBar(title: context.t.mapSettings),
            const SizedBox(height: 24),
            Expanded(
              child: PageView(
                controller: pageController,
                onPageChanged: (newSelectedPage) {
                  setState(() {
                    activeId = newSelectedPage;
                  });
                },
                children: [
                  SharedMapSettingItem(
                    isActive: activeId == 0,
                    isSelected: widget.selectedMapProvider == MapProviderEnum.mapBox,
                    image: widget.mapBoxImage,
                    title: "MapBox",
                    benefits: _getBenefits(context, 'mapbox'),
                    shortComings: _getShortComings(context, 'mapbox'),
                    onPressed: () => widget.onMapProviderChanged(MapProviderEnum.mapBox),
                  ),
                  SharedMapSettingItem(
                    isActive: activeId == 1,
                    isSelected: widget.selectedMapProvider == MapProviderEnum.openStreetMaps,
                    image: widget.openStreetMapImage,
                    title: "OpenStreetMap",
                    benefits: _getBenefits(context, 'osm'),
                    shortComings: _getShortComings(context, 'osm'),
                    onPressed: () => widget.onMapProviderChanged(MapProviderEnum.openStreetMaps),
                  ),
                  SharedMapSettingItem(
                    isActive: activeId == 2,
                    isSelected: widget.selectedMapProvider == MapProviderEnum.googleMaps,
                    image: widget.googleMapsImage,
                    title: "Google Maps",
                    benefits: _getBenefits(context, 'google'),
                    shortComings: _getShortComings(context, 'google'),
                    onPressed: () => widget.onMapProviderChanged(MapProviderEnum.googleMaps),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
