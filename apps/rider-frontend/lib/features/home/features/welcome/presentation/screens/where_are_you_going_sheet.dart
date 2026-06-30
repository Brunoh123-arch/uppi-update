import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:flutter_common/core/theme/animation_duration.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:rider_flutter/core/blocs/auth_bloc.dart';
import 'package:rider_flutter/core/blocs/location.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/app_card_sheet.dart';
import 'package:rider_flutter/core/presentation/app_favorite_location_item.dart';
import 'package:flutter_common/core/presentation/card_handle.dart';
import 'package:rider_flutter/core/presentation/place_result_item.dart';
import 'package:rider_flutter/features/home/presentation/blocs/home.dart';
import 'package:rider_flutter/features/home/presentation/widgets/smart_route_suggestions.dart';
import 'package:flutter_common/core/presentation/common_skeletons.dart';
import 'package:flutter_common/core/utils/uppi_haptics.dart';
import 'package:rider_flutter/features/home/features/waypoints/presentation/blocs/selected_location_field.dart';
import 'package:flutter_common/config/constants.dart';

import '../../../../presentation/blocs/destination_suggestions.dart';
import '../components/where_are_you_going_button.dart';

class WhereAreYouGoingSheet extends StatefulWidget {
  final List<PlaceEntity?> waypoints;

  const WhereAreYouGoingSheet({
    super.key,
    required this.waypoints,
  });

  @override
  State<WhereAreYouGoingSheet> createState() => _WhereAreYouGoingSheetState();
}

class _WhereAreYouGoingSheetState extends State<WhereAreYouGoingSheet> {
  bool isExpanded = true;
  bool _isSearching = false;

  @override
  Widget build(BuildContext context) {
    return AppCardSheet(
      child: BlocProvider.value(
        value: locator<DestinationSuggestionsCubit>(),
        child: BlocListener<AuthBloc, AuthState>(
          listener: (context, state) {
            state.mapOrNull(
              authenticated: (authenticated) =>
                  locator<DestinationSuggestionsCubit>().onStarted(),
            );
          },
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                CardHandle(
                  onPressed: () {
                    setState(() {
                      isExpanded = !isExpanded;
                    });
                  },
                ),
                Text(
                  context.translate.whereAreYouGoing,
                  style: context.headlineSmall,
                ),
                const SizedBox(height: 16),
                WhereAreYouGoingButton(
                  onPressed: () {
                    UppiHaptics.selection();
                    locator<SelectedLocationFieldCubit>()
                        .onLocationFieldSelected(1);
                    final currentWaypoints = List<PlaceEntity?>.from(widget.waypoints);
                    final defaultPartida = locator<LocationCubit>().state.place ?? Constants.defaultLocation;
                    if (currentWaypoints.isEmpty) {
                      currentWaypoints.add(defaultPartida);
                      currentWaypoints.add(null);
                    } else if (currentWaypoints[0] == null) {
                      currentWaypoints[0] = defaultPartida;
                    }
                    locator<HomeCubit>()
                        .showWaypoints(waypoints: currentWaypoints);
                  },
                ),
                const SizedBox(height: 16),
                NotificationListener<ScrollNotification>(
                    onNotification: (ScrollNotification notification) {
                      if (notification is ScrollUpdateNotification) {
                        final pixels = notification.metrics.pixels;
                        if (pixels < -45 && !_isSearching) {
                          _isSearching = true;
                          UppiHaptics.selection();
                          locator<SelectedLocationFieldCubit>()
                              .onLocationFieldSelected(1);
                          final currentWaypoints = List<PlaceEntity?>.from(widget.waypoints);
                          final defaultPartida = locator<LocationCubit>().state.place ?? Constants.defaultLocation;
                          if (currentWaypoints.isEmpty) {
                            currentWaypoints.add(defaultPartida);
                            currentWaypoints.add(null);
                          } else if (currentWaypoints[0] == null) {
                            currentWaypoints[0] = defaultPartida;
                          }
                          locator<HomeCubit>()
                              .showWaypoints(waypoints: currentWaypoints);
                        }
                      }
                      return false;
                    },
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 🧠 Sugestões inteligentes de rota (casa, trabalho, destinos frequentes)
                          SmartRouteSuggestions(
                            onSuggestionTap: (suggestion) {
                              final pickupLocation =
                                  widget.waypoints.firstOrNull ??
                                      locator<LocationCubit>().state.place;
                              final lat = (suggestion['lat'] as num?)?.toDouble();
                              final lng = (suggestion['lng'] as num?)?.toDouble();
                              final addr = suggestion['address']?.toString() ?? '';
                              final name = suggestion['name']?.toString() ?? addr;
                              if (lat == null || lng == null) return;

                              final destination = PlaceEntity(
                                title: name,
                                address: addr,
                                coordinates: LatLngEntity(lat: lat, lng: lng),
                              );

                              if (pickupLocation == null) {
                                context.showSnackBar(
                                  message: context.translate.pickupLocationNotFound,
                                );
                                locator<HomeCubit>().showWaypoints(
                                  waypoints: [null, destination],
                                );
                                return;
                              }
                              locator<HomeCubit>().showPreview(
                                waypoints: [
                                  pickupLocation,
                                  destination,
                                ],
                                directions: [],
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          AnimatedCrossFade(
                            duration: AnimationDuration.pageStateTransitionMobile,
                            crossFadeState: isExpanded
                                ? CrossFadeState.showFirst
                                : CrossFadeState.showSecond,
                            secondChild: const SizedBox.shrink(),
                            firstChild: BlocBuilder<DestinationSuggestionsCubit,
                                DestinationSuggestionsState>(
                              builder: (context, state) => AnimatedSwitcher(
                                duration: AnimationDuration.pageStateTransitionMobile,
                                child: state.maybeMap(
                                  orElse: () => const SizedBox.shrink(),
                                  loading: (value) => const DestinationSuggestionsSkeleton(),
                                  error: (value) => Text(value.message),
                                  loaded: (value) => Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Container(
                                        constraints: const BoxConstraints(maxHeight: 100),
                                        child: ListView.separated(
                                          shrinkWrap: true,
                                          padding: EdgeInsets.zero,
                                          itemBuilder: (context, index) {
                                            final item = value.recents[index];
                                            return PlaceResultItem(
                                                subtitle: item.address,
                                                title: item.title,
                                                isRecent: true,
                                                onPressed: () {
                                                  final pickupLocation =
                                                      widget.waypoints.firstOrNull ??
                                                          locator<LocationCubit>()
                                                              .state
                                                              .place;
                                                  if (pickupLocation == null) {
                                                    context.showSnackBar(
                                                      message: context.translate
                                                          .pickupLocationNotFound,
                                                    );
                                                    locator<HomeCubit>().showWaypoints(
                                                      waypoints: [null, item],
                                                    );
                                                    return;
                                                  }
                                                  locator<HomeCubit>().showPreview(
                                                    waypoints: [
                                                      pickupLocation,
                                                      item,
                                                    ],
                                                    directions: [],
                                                  );
                                                });
                                          },
                                          separatorBuilder: (context, index) =>
                                              const Divider(indent: 42),
                                          itemCount: value.recents.length,
                                        ),
                                      ),
                                      if (value.favorites.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        Text(
                                          context.translate.favoriteLocations,
                                          style: context.titleMedium,
                                        ),
                                        const SizedBox(height: 12),
                                        SizedBox(
                                          height: 130,
                                          child: ListView.separated(
                                            shrinkWrap: true,
                                            padding: EdgeInsets.zero,
                                            dragStartBehavior: DragStartBehavior.down,
                                            itemBuilder: (context, index) {
                                              final item = value.favorites[index];
                                              return AppFavoriteLocationItem(
                                                type: item.type,
                                                address: item,
                                                onPressed: () {
                                                  final pickupLocation =
                                                      widget.waypoints.firstOrNull ??
                                                          locator<LocationCubit>()
                                                              .state
                                                              .place;
                                                  if (pickupLocation == null) {
                                                    context.showSnackBar(
                                                      message: context.translate
                                                          .pickupLocationNotFound,
                                                    );
                                                    locator<HomeCubit>().showWaypoints(
                                                      waypoints: [null, item.place],
                                                    );
                                                    return;
                                                  }
                                                  locator<HomeCubit>().showPreview(
                                                    waypoints: [
                                                      pickupLocation,
                                                      item.place,
                                                    ],
                                                    directions: [],
                                                  );
                                                },
                                              );
                                            },
                                            separatorBuilder: (context, index) =>
                                                const Divider(indent: 42),
                                            itemCount: value.favorites.length,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
