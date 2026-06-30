import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:flutter_common/core/presentation/app_menu_item.dart';
import 'package:flutter_common/core/presentation/buttons/app_bordered_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:ionicons/ionicons.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

class LaunchMapDialog extends StatefulWidget {
  final PlaceEntity place;

  const LaunchMapDialog({super.key, required this.place});

  @override
  State<LaunchMapDialog> createState() => _LaunchMapDialogState();
}

class _LaunchMapDialogState extends State<LaunchMapDialog> {
  Future<List<AvailableMap>> maps = MapLauncher.installedMaps;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return AppResponsiveDialog(
      type: context.responsive(DialogType.bottomSheet, xl: DialogType.dialog),
      header: (
        Ionicons.navigate_circle,
        "Abrir Mapa",
        "Use um dos mapas instalados para navegar até o destino",
      ),
      primaryButton: AppBorderedButton(
        onPressed: () => Navigator.pop(context),
        title: "Cancelar",
      ),
      onBackPressed: () => Navigator.of(context).pop(),
      child: FutureBuilder(
        future: maps,
        builder: (context, snapshot) {
          final List<Widget> items = [];

          // Add native maps if any are installed
          final installedMaps = snapshot.data ?? [];
          if (installedMaps.isNotEmpty) {
            for (final map in installedMaps) {
              items.add(
                AppMenuItem(
                  onPressed: () async {
                    Navigator.pop(context);
                    await map.showDirections(
                      destination: Coords(
                        widget.place.latLng2.latitude,
                        widget.place.latLng2.longitude,
                      ),
                      destinationTitle: widget.place.address,
                      directionsMode: DirectionsMode.driving,
                    );
                  },
                  icon: Ionicons.map,
                  title: map.mapName,
                ),
              );
            }
          } else {
            // Web fallbacks ONLY when no native maps are detected (e.g. Web or simulator tests)
            // Google Maps Web Navigation
            items.add(
              AppMenuItem(
                onPressed: () async {
                  Navigator.pop(context);
                  final url = "https://www.google.com/maps/dir/?api=1&destination=${widget.place.latLng2.latitude},${widget.place.latLng2.longitude}";
                  await launchUrlString(
                    url,
                    mode: LaunchMode.externalApplication,
                  );
                },
                icon: Ionicons.navigate_circle,
                title: "Google Maps (Navegador)",
              ),
            );

            // Waze Web Navigation
            items.add(
              AppMenuItem(
                onPressed: () async {
                  Navigator.pop(context);
                  final url = "https://waze.com/ul?ll=${widget.place.latLng2.latitude},${widget.place.latLng2.longitude}&navigate=yes";
                  await launchUrlString(
                    url,
                    mode: LaunchMode.externalApplication,
                  );
                },
                icon: Ionicons.compass,
                title: "Waze (Navegador)",
              ),
            );
          }

          return ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) => items[index],
          );
        },
      ),
    );
  }
}
