import 'package:ionicons/ionicons.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/app_card_sheet.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:rider_flutter/core/presentation/place_result_item.dart';
import 'package:rider_flutter/features/home/presentation/blocs/home.dart';
import 'package:rider_flutter/features/home/presentation/blocs/place_confirm.dart';
import 'package:rider_flutter/features/home/presentation/components/home_map.dart';

class PlaceConfirmSheet extends StatefulWidget {
  final List<PlaceEntity?> waypoints;
  final PlaceEntity selectedLocation;
  final int index;

  const PlaceConfirmSheet({
    super.key,
    required this.waypoints,
    required this.index,
    required this.selectedLocation,
  });

  @override
  State<PlaceConfirmSheet> createState() => _PlaceConfirmSheetState();
}

class _PlaceConfirmSheetState extends State<PlaceConfirmSheet> {
  bool _isAmplified = false;

  @override
  void dispose() {
    HomeMap.confirmLocationZoom.value = null;
    super.dispose();
  }

  void _amplify() {
    setState(() {
      _isAmplified = true;
    });
    HomeMap.confirmLocationZoom.value = 18.5;
  }

  void _confirmAndSubmit(PlaceEntity location) {
    final newWaypoints = widget.waypoints
        .mapIndexed((index, element) =>
            index == widget.index ? location : element)
        .toList();
    locator<HomeCubit>().showWaypoints(waypoints: newWaypoints);
  }

  @override
  Widget build(BuildContext context) {
    return AppCardSheet(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isAmplified ? "Selecione o local exato" : context.translate.dragToSelect,
                style: context.titleMedium,
                textAlign: TextAlign.start,
              ),
              const SizedBox(
                height: 8,
              ),
              BlocBuilder<PlaceConfirmCubit, PlaceConfirmState>(
                builder: (context, state) {
                  return Container(
                    constraints: const BoxConstraints(minHeight: 60),
                    child: Row(
                      children: [
                        Expanded(
                          child: PlaceResultItem(
                            subtitle: state.map(
                              loading: (value) => "",
                              loaded: (loaded) => loaded.data.address,
                            ),
                            title: state.map(
                              loading: (value) => "",
                              loaded: (loaded) => loaded.data.title,
                            ),
                            onPressed: null,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              if (!_isAmplified) ...[
                const SizedBox(height: 16),
                TextField(
                  onTap: () {
                    locator<HomeCubit>().showWaypoints(waypoints: widget.waypoints);
                  },
                  readOnly: true,
                  decoration: InputDecoration(
                    hintText: widget.index == 0
                        ? context.translate.searchForPickupLocation
                        : context.translate.searchForDropoffLocation,
                    fillColor: Colors.transparent,
                    prefixIcon: const Icon(
                      Ionicons.search,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    widget.index == 0
                        ? "Amplie o mapa para encontrar seu local exato de embarque"
                        : "Amplie o mapa para encontrar seu local exato de destino",
                    style: context.bodyMedium?.copyWith(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              BlocBuilder<PlaceConfirmCubit, PlaceConfirmState>(
                builder: (context, state) {
                  final currentPlace = state.maybeMap(
                    orElse: () => null,
                    loaded: (value) => value.data,
                  );
                  final isButtonDisabled = currentPlace == null;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: AppPrimaryButton(
                          isDisabled: isButtonDisabled,
                          onPressed: () {
                            if (!_isAmplified) {
                              _amplify();
                            } else {
                              if (currentPlace != null) {
                                _confirmAndSubmit(currentPlace);
                              }
                            }
                          },
                          child: Text(
                            !_isAmplified
                                ? "Ampliar a amostra"
                                : "Confirmar local",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSecondaryButton(
                        title: "Salvar endereço como favorito",
                        onPressed: isButtonDisabled
                            ? null
                            : () {
                                _confirmAndSubmit(currentPlace);
                              },
                      ),
                    ],
                  );
                },
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton({
    required String title,
    required VoidCallback? onPressed,
  }) {
    final bool disabled = onPressed == null;
    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.black54,
            width: 1.2,
          ),
        ),
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          child: Center(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
