import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../utils/smooth_marker_interpolator.dart';

/// Widget que anima suavemente a posição e rotação de um marcador de veículo.
/// Use este widget para exibir o carro do motorista se movendo fluidamente no mapa.
class AnimatedVehicleMarker extends StatefulWidget {
  final LatLng currentPosition;
  final LatLng targetPosition;
  final Widget child;
  final Duration duration;

  const AnimatedVehicleMarker({
    super.key,
    required this.currentPosition,
    required this.targetPosition,
    required this.child,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  State<AnimatedVehicleMarker> createState() => _AnimatedVehicleMarkerState();
}

class _AnimatedVehicleMarkerState extends State<AnimatedVehicleMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  LatLng _fromPosition = const LatLng(0, 0);
  LatLng _toPosition = const LatLng(0, 0);
  double _fromBearing = 0;
  double _toBearing = 0;

  LatLng _displayPosition = const LatLng(0, 0);
  double _displayBearing = 0;

  @override
  void initState() {
    super.initState();
    _fromPosition = widget.currentPosition;
    _toPosition = widget.targetPosition;
    _displayPosition = _fromPosition;
    _toBearing = SmoothMarkerInterpolator.calculateBearing(
      _fromPosition,
      _toPosition,
    );
    _fromBearing = _toBearing;
    _displayBearing = _fromBearing;

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    _animation.addListener(_onAnimationTick);
  }

  void _onAnimationTick() {
    final t = _animation.value;
    setState(() {
      _displayPosition = SmoothMarkerInterpolator.interpolatePosition(
        _fromPosition,
        _toPosition,
        t,
      );
      _displayBearing = SmoothMarkerInterpolator.interpolateBearing(
        _fromBearing,
        _toBearing,
        t,
      );
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedVehicleMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetPosition != widget.targetPosition) {
      _fromPosition = _displayPosition;
      _fromBearing = _displayBearing;
      _toPosition = widget.targetPosition;
      _toBearing = SmoothMarkerInterpolator.calculateBearing(
        _fromPosition,
        _toPosition,
      );
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: _displayBearing * 3.14159265 / 180,
      child: widget.child,
    );
  }
}
