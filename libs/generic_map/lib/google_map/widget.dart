import 'package:flutter/material.dart';
import 'package:generic_map/google_map/provider.dart';
import 'package:generic_map/interfaces/interfaces.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:generic_map/extensions.dart';
import 'package:generic_map/google_map/controller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as latlong;

/// Google Maps dark mode style JSON (same palette used by 99/Uber at night).
const String _darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#182335"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#707b89"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#121b28"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#2f3f56"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#94a3b8"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#cbd5e1"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#1e293b"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#64748b"}]},
  {"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#141d2b"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#475569"}]},
  {"featureType":"poi.park","elementType":"labels.text.stroke","stylers":[{"color":"#0f172a"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#243142"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#1a2433"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#94a3b8"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#2a3b52"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#324661"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#1a2433"}]},
  {"featureType":"road.highway.controlled_access","elementType":"geometry","stylers":[{"color":"#384f6e"}]},
  {"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#64748b"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#243142"}]},
  {"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#707b89"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1626"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3b4e6b"}]}
]
''';

/// Google Maps light mode style JSON (used to hide clickable POIs during day).
const String _lightMapStyle = '''
[
  {
    "featureType": "poi",
    "elementType": "labels",
    "stylers": [
      {"visibility": "off"}
    ]
  }
]
''';

class GoogleMapView extends StatefulWidget {
  final MapViewMode mode;
  final bool interactive;
  final GoogleMapProvider provider;
  final Function(Place?)? onMapMoved;
  final Place initialLocation;
  final List<PolyLineLayer> polylines;
  final List<CustomMarker> markers;
  final List<CircleMarker> circleMarkers;
  final Function(MapViewController)? onControllerReady;
  final EdgeInsets padding;

  final AddressResolver? addressResolver;
  final bool goToCurrentLocation;
  final bool myLocationEnabled;
  final bool animateMarkers;
  final bool isDarkMode;

  const GoogleMapView({
    super.key,
    required this.initialLocation,
    required this.polylines,
    required this.mode,
    this.onControllerReady,
    required this.onMapMoved,
    required this.interactive,
    required this.padding,
    required this.markers,
    required this.addressResolver,
    required this.circleMarkers,
    required this.provider,
    required this.goToCurrentLocation,
    required this.myLocationEnabled,
    this.animateMarkers = true,
    this.isDarkMode = false,
  });


  @override
  State<GoogleMapView> createState() => _GoogleMapMapViewState();
}

class _GoogleMapMapViewState extends State<GoogleMapView>
    with SingleTickerProviderStateMixin {
  final GoogleMapsController controller = GoogleMapsController();
  CameraPosition? cameraPosition;
  late List<GlobalKey> markerKeys;
  Set<Marker> markers = {};

  // Animação de marcadores: o Google Maps nativo não interpola a posição do
  // Marker — sem isso o chevron do motorista "teleporta" a cada fix de GPS.
  // Interpolamos posição/rotação no Dart entre o conjunto anterior e o novo.
  late final AnimationController _markerAnim;
  Map<MarkerId, Marker> _animFrom = {};
  Map<MarkerId, Marker> _animTo = {};
  // Guarda de geração: _loadMarkers é async e roda a cada fix; sem isso um
  // resultado antigo pode chegar depois e sobrescrever o mais novo.
  int _markersGen = 0;

  Set<Circle> _parsedCircles = {};
  Set<Polyline> _parsedPolylines = {};

  bool _areMarkersEqual(List<CustomMarker> a, List<CustomMarker> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final ma = a[i];
      final mb = b[i];
      if (ma.id != mb.id ||
          ma.position != mb.position ||
          ma.rotation != mb.rotation ||
          ma.width != mb.width ||
          ma.height != mb.height ||
          ma.alignment != mb.alignment ||
          ma.flat != mb.flat ||
          ma.fallbackAssetPath != mb.fallbackAssetPath) {
        return false;
      }
    }
    return true;
  }

  bool _areCircleMarkersEqual(List<CircleMarker> a, List<CircleMarker> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final ca = a[i];
      final cb = b[i];
      if (ca.position != cb.position ||
          ca.radius != cb.radius ||
          ca.color != cb.color ||
          ca.borderColor != cb.borderColor ||
          ca.borderWidth != cb.borderWidth) {
        return false;
      }
    }
    return true;
  }

  bool _arePolylinesEqual(List<PolyLineLayer> a, List<PolyLineLayer> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final pa = a[i];
      final pb = b[i];
      if (pa.color != pb.color ||
          pa.width != pb.width ||
          pa.strokeCap != pb.strokeCap ||
          pa.strokeJoin != pb.strokeJoin ||
          pa.borderStrokeWidth != pb.borderStrokeWidth ||
          pa.borderColor != pb.borderColor ||
          !_arePointsEqual(pa.points, pb.points) ||
          !_areColorsEqual(pa.gradientColors, pb.gradientColors)) {
        return false;
      }
    }
    return true;
  }

  bool _arePointsEqual(List<latlong.LatLng> a, List<latlong.LatLng> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _areColorsEqual(List<Color> a, List<Color> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    cameraPosition = CameraPosition(
      target: widget.initialLocation.latLng.toGoogleMapLatLng(),
      zoom: 16,
      tilt: widget.mode == MapViewMode.picker ? 0.0 : 55.0,
    );
    controller.currentCameraPosition = cameraPosition;
    markerKeys = widget.markers.map((e) => GlobalKey()).toList();
    _markerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..addListener(_applyMarkerAnimation);
    
    _parsedCircles = widget.provider.parseCircleMarkers(widget.circleMarkers).toSet();
    _parsedPolylines = widget.provider.parsePolyLines(widget.polylines).toSet();
    
    _loadMarkers();
  }

  @override
  void didUpdateWidget(GoogleMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_areMarkersEqual(widget.markers, oldWidget.markers)) {
      _loadMarkers();
    }
    if (!_areCircleMarkersEqual(widget.circleMarkers, oldWidget.circleMarkers)) {
      setState(() {
        _parsedCircles = widget.provider.parseCircleMarkers(widget.circleMarkers).toSet();
      });
    }
    if (!_arePolylinesEqual(widget.polylines, oldWidget.polylines)) {
      setState(() {
        _parsedPolylines = widget.provider.parsePolyLines(widget.polylines).toSet();
      });
    }
    if (widget.isDarkMode != oldWidget.isDarkMode) {
      controller.mapController.future.then((gmController) {
        _applyMapStyle(gmController);
      });
    }
  }

  double _lerpAngle(double a, double b, double t) {
    double diff = (b - a) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return ((a + diff * t) + 360) % 360;
  }

  void _applyMarkerAnimation() {
    if (!mounted) return;
    final t = _markerAnim.value;
    final Set<Marker> frame = {};
    _animTo.forEach((id, to) {
      final from = _animFrom[id];
      if (from == null ||
          (from.position == to.position && from.rotation == to.rotation)) {
        frame.add(to);
        return;
      }
      frame.add(to.copyWith(
        positionParam: LatLng(
          from.position.latitude +
              (to.position.latitude - from.position.latitude) * t,
          from.position.longitude +
              (to.position.longitude - from.position.longitude) * t,
        ),
        rotationParam: _lerpAngle(from.rotation, to.rotation, t),
      ));
    });
    setState(() => markers = frame);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (controller.mapController.isCompleted) {
      controller.mapController.future.then((value) {
        _applyMapStyle(value);
      });
    }
  }

  void _loadMarkers() async {
    if (!mounted) return;

    final gen = ++_markersGen;
    final loaded = await Future.wait(widget.provider.parseMarkers(widget.markers));

    // Resultado obsoleto (outra carga mais nova já começou) → descarta.
    if (!mounted || gen != _markersGen) return;

    final target = {for (final m in loaded) m.markerId: m};

    if (markers.isEmpty || !widget.animateMarkers) {
      // Primeira carga ou animação desativada: aplica direto, sem animação.
      _animFrom = target;
      _animTo = target;
      setState(() => markers = loaded.toSet());
      return;
    }

    _animFrom = {for (final m in markers) m.markerId: m};
    _animTo = target;
    _markerAnim
      ..stop()
      ..value = 0
      ..forward();
  }

  /// Apply map style based on active app theme brightness or night time.
  void _applyMapStyle(GoogleMapController gmController) {
    // Modo noturno automático ou manual baseado em isDarkMode
    final hour = DateTime.now().hour;
    final isNight = hour >= 18 || hour < 5;
    if (widget.isDarkMode || isNight) {
      gmController.setMapStyle(_darkMapStyle);
    } else {
      gmController.setMapStyle(_lightMapStyle); // Desabilita POIs clicáveis no modo diurno
    }
  }

  @override
  void dispose() {
    _markerAnim.dispose();
    controller.mapController.future.then((value) => value.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          padding: widget.padding,
          scrollGesturesEnabled: widget.interactive,
          zoomGesturesEnabled: widget.interactive,
          myLocationButtonEnabled: false,
          myLocationEnabled: widget.myLocationEnabled,
          zoomControlsEnabled: false,
          compassEnabled: false,
          mapToolbarEnabled: false,
          tiltGesturesEnabled: true,
          minMaxZoomPreference: const MinMaxZoomPreference(3, 20),
          rotateGesturesEnabled: true,
          webCameraControlEnabled: false,
          trafficEnabled: true,
          buildingsEnabled: false,
          onMapCreated: (controller) {
            // Apply dark style if needed
            _applyMapStyle(controller);
            if (widget.onControllerReady != null) {
              widget.onControllerReady!(this.controller);
            }
            this.controller.mapController.complete(controller);
            if (widget.goToCurrentLocation) {
              Geolocator.requestPermission().then((value) {
                if (value == LocationPermission.denied ||
                    value == LocationPermission.deniedForever) {
                  Geolocator.openAppSettings();
                }
                Geolocator.getCurrentPosition().then((value) {
                  controller.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: LatLng(value.latitude, value.longitude),
                        zoom: 18,
                        tilt: 55.0,
                      ),
                    ),
                  );
                });
              });
            }
          },
          onCameraMoveStarted: () => widget.onMapMoved?.call(null),
          onCameraIdle: () async {
            if (cameraPosition == null) return;
            final reverseGeocodeResult = await widget.addressResolver?.call(
              MapProviderEnum.googleMaps,
              cameraPosition!.target.toLatLng(),
            );
            widget.onMapMoved?.call(reverseGeocodeResult);
          },
          onCameraMove: (position) {
            cameraPosition = position;
            controller.currentCameraPosition = position;
          },
          markers: markers,
          circles: _parsedCircles,
          polylines: _parsedPolylines,
          initialCameraPosition: CameraPosition(
            target: widget.initialLocation.latLng.toGoogleMapLatLng(),
            zoom: 16,
            tilt: widget.mode == MapViewMode.picker ? 0.0 : 55.0,
          ),
        ),
      ],
    );
  }
}
