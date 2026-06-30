import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/extensions/extensions.dart';

/// Widget overlay para exibir zonas quentes no mapa do motorista
/// Mostra badge com contagem e detalhes das zonas
class DriverHeatmapOverlay extends StatefulWidget {
  final double driverLat;
  final double driverLng;
  final Function(List<HeatmapZone>)? onZonesLoaded;

  const DriverHeatmapOverlay({
    super.key,
    required this.driverLat,
    required this.driverLng,
    this.onZonesLoaded,
  });

  @override
  State<DriverHeatmapOverlay> createState() => _DriverHeatmapOverlayState();
}

class _DriverHeatmapOverlayState extends State<DriverHeatmapOverlay> {
  List<HeatmapZone> zones = [];
  bool isLoading = false;
  DateTime? lastFetch;
  RealtimeChannel? _surgeRealtimeChannel;

  @override
  void initState() {
    super.initState();
    _fetchHeatmap();
    _startSurgeRealtimeListener();
  }

  void _startSurgeRealtimeListener() {
    _surgeRealtimeChannel?.unsubscribe();
    _surgeRealtimeChannel = Supabase.instance.client
        .channel('public:surge_zones_heatmap')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'surge_zones',
          callback: (payload) {
            _fetchHeatmap();
          },
        );
    _surgeRealtimeChannel!.subscribe();
  }

  @override
  void didUpdateWidget(DriverHeatmapOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Força refresh se a localização mudou significativamente
    if ((oldWidget.driverLat - widget.driverLat).abs() > 0.005 ||
        (oldWidget.driverLng - widget.driverLng).abs() > 0.005) {
      _fetchHeatmap();
    }
  }

  @override
  void dispose() {
    _surgeRealtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchHeatmap() async {
    if (isLoading) return;
    setState(() => isLoading = true);

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'get-driver-heatmap',
        body: {'lat': widget.driverLat, 'lng': widget.driverLng},
      );

      final rawZones =
          response.data['hotspots'] as List<dynamic>? ??
          response.data['zones'] as List<dynamic>? ??
          [];
      final parsed = rawZones.map((z) => HeatmapZone.fromMap(z)).toList();

      setState(() {
        zones = parsed;
        lastFetch = DateTime.now();
        isLoading = false;
      });

      widget.onZonesLoaded?.call(zones);
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (zones.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ColorPalette.neutral20.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3F0E275D),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: ColorPalette.semanticgreen60,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${zones.length} ${zones.length == 1 ? 'zona quente' : 'zonas quentes'}',
            style: context.labelSmall?.copyWith(
              color: ColorPalette.neutral100,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dados de uma zona de calor
class HeatmapZone {
  final String zone;
  final double lat;
  final double lng;
  final double multiplier;
  final int openOrders;
  final int availableDrivers;
  final String intensity; // 'low' | 'medium' | 'high' | 'extreme'

  HeatmapZone({
    required this.zone,
    required this.lat,
    required this.lng,
    required this.multiplier,
    required this.openOrders,
    required this.availableDrivers,
    required this.intensity,
  });

  /// Raio visual estimado pela intensidade da zona
  double get radius {
    switch (intensity) {
      case 'extreme':
        return 800;
      case 'high':
        return 600;
      case 'medium':
        return 500;
      default:
        return 400;
    }
  }

  /// Cor da zona baseada no multiplicador — usando ColorPalette Uppi
  Color get zoneColor {
    if (multiplier >= 2.0) return ColorPalette.error40;
    if (multiplier >= 1.5) return ColorPalette.secondary40;
    return ColorPalette.secondary70;
  }

  /// Alinhado com o schema real do backend (getDriverHeatmap)
  factory HeatmapZone.fromMap(dynamic data) {
    final map = data as Map<String, dynamic>;
    return HeatmapZone(
      zone: map['zone'] as String? ?? '',
      lat: (map['lat'] as num?)?.toDouble() ?? 0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0,
      multiplier: (map['multiplier'] as num?)?.toDouble() ?? 1.0,
      openOrders: (map['openOrders'] as num?)?.toInt() ?? 0,
      availableDrivers: (map['availableDrivers'] as num?)?.toInt() ?? 0,
      intensity: map['intensity'] as String? ?? 'low',
    );
  }
}

/// Chip indicador de zona quente — padrão Uppi
class HotZoneChip extends StatelessWidget {
  final double multiplier;

  const HotZoneChip({super.key, required this.multiplier});

  @override
  Widget build(BuildContext context) {
    if (multiplier <= 1.0) return const SizedBox.shrink();

    final Color bgColor;
    final Color textColor;

    if (multiplier >= 2.0) {
      bgColor = ColorPalette.error40;
      textColor = ColorPalette.neutral100;
    } else if (multiplier >= 1.5) {
      bgColor = ColorPalette.secondary40;
      textColor = ColorPalette.neutral100;
    } else {
      bgColor = ColorPalette.secondary95;
      textColor = ColorPalette.secondary40;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Ionicons.flame, size: 14, color: textColor),
          const SizedBox(width: 3),
          Text(
            '${multiplier.toStringAsFixed(1)}x',
            style: context.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
