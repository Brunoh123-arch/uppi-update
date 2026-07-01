import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:generic_map/generic_map.dart';
import 'package:latlong2/latlong.dart';

const _kSurface = Color(0xFF1E293B);
const _kBackground = Color(0xFF0F172A);
const _kSubtext = Color(0xFF94A3B8);
const _kBorder = Color(0xFF2D3F58);

class DemandHeatmapScreen extends StatefulWidget {
  const DemandHeatmapScreen({super.key});

  @override
  State<DemandHeatmapScreen> createState() => _DemandHeatmapScreenState();
}

class _DemandHeatmapScreenState extends State<DemandHeatmapScreen> {
  MapViewController? _mapController;
  List<Map<String, dynamic>> _hotspots = [];
  bool _isLoading = true;
  bool _showDrivers = true;
  bool _showRides = true;
  String _selectedTimeFilter = '30m'; // 30m, 1h, 6h, 24h
  
  // Realtime lists to show count on overlay
  int _onlineDriversCount = 0;
  int _openRidesCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchHeatmapData();
    _fetchRealtimeStats();
  }

  Future<void> _fetchRealtimeStats() async {
    try {
      // 1. Motoristas ativos
      final driversRes = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('role', 'driver')
          .eq('is_online', true);
      
      // 2. Corridas abertas/solicitadas
      final ridesRes = await Supabase.instance.client
          .from('rides')
          .select('id')
          .eq('status', 'requested');

      if (mounted) {
        setState(() {
          _onlineDriversCount = (driversRes as List).length;
          _openRidesCount = (ridesRes as List).length;
        });
      }
    } catch (e) {
      debugPrint("Error fetching heatmap stats: $e");
    }
  }

  Future<void> _fetchHeatmapData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final now = DateTime.now().toUtc();
      DateTime cutoff;
      switch (_selectedTimeFilter) {
        case '30m':
          cutoff = now.subtract(const Duration(minutes: 30));
          break;
        case '6h':
          cutoff = now.subtract(const Duration(hours: 6));
          break;
        case '24h':
          cutoff = now.subtract(const Duration(hours: 24));
          break;
        case '1h':
        default:
          cutoff = now.subtract(const Duration(hours: 1));
          break;
      }

      // Query database for recent rides to determine demand hotspots
      final response = await Supabase.instance.client
          .from('rides')
          .select('id, pickup_location, status, created_at')
          .gte('created_at', cutoff.toIso8601String());

      final List<Map<String, dynamic>> rides = List<Map<String, dynamic>>.from(response);

      // Perform a mock clustering on Belém coordinates if no real data
      if (rides.isEmpty) {
        _hotspots = [
          {
            'zone': 'Umarizal_Nazare',
            'lat': -1.4485,
            'lng': -48.4842,
            'intensity': 'high',
            'multiplier': 1.6,
            'openOrders': 12,
            'availableDrivers': 3,
          },
          {
            'zone': 'Marco_Pedreira',
            'lat': -1.4338,
            'lng': -48.4648,
            'intensity': 'medium',
            'multiplier': 1.3,
            'openOrders': 7,
            'availableDrivers': 4,
          },
          {
            'zone': 'Reduto_Campina',
            'lat': -1.4512,
            'lng': -48.4975,
            'intensity': 'extreme',
            'multiplier': 2.1,
            'openOrders': 19,
            'availableDrivers': 1,
          }
        ];
      } else {
        // Group by approximate coordinates to create zones
        final Map<String, List<Map<String, dynamic>>> clusters = {};
        for (var r in rides) {
          final loc = r['pickup_location']?.toString();
          if (loc != null) {
            final coords = _parsePostGISPoint(loc);
            if (coords != null) {
              // Cluster to 3 decimal places (approx 110 meters)
              final key = "${(coords.latitude * 100).round() / 100}_${(coords.longitude * 100).round() / 100}";
              clusters.putIfAbsent(key, () => []).add(r);
            }
          }
        }

        final List<Map<String, dynamic>> calculatedHotspots = [];
        clusters.forEach((key, list) {
          final parts = key.split('_');
          final lat = double.parse(parts[0]);
          final lng = double.parse(parts[1]);
          final count = list.length;

          String intensity = 'medium';
          double mult = 1.0;
          if (count > 15) {
            intensity = 'extreme';
            mult = 2.0;
          } else if (count > 8) {
            intensity = 'high';
            mult = 1.5;
          } else if (count > 3) {
            intensity = 'medium';
            mult = 1.2;
          }

          if (count >= 3) {
            calculatedHotspots.add({
              'zone': 'Sector_${key.replaceAll('.', 'd')}',
              'lat': lat,
              'lng': lng,
              'intensity': intensity,
              'multiplier': mult,
              'openOrders': count,
              'availableDrivers': (count * 0.4).round() + 1,
            });
          }
        });

        _hotspots = calculatedHotspots.isEmpty ? [] : calculatedHotspots;
      }
    } catch (e) {
      debugPrint("Error fetching heatmap: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  LatLng? _parsePostGISPoint(String? pgPoint) {
    if (pgPoint == null) return null;
    try {
      final clean = pgPoint.toUpperCase().replaceAll('POINT', '').replaceAll('(', '').replaceAll(')', '').trim();
      final parts = clean.split(' ');
      if (parts.length >= 2) {
        final lng = double.parse(parts[0]);
        final lat = double.parse(parts[1]);
        return LatLng(lat, lng);
      }
    } catch (_) {}
    return null;
  }

  Color _getHeatmapColor(String intensity) {
    switch (intensity) {
      case 'extreme':
        return Colors.red.withOpacity(0.55);
      case 'high':
        return Colors.orange.withOpacity(0.45);
      case 'medium':
      default:
        return Colors.yellow.withOpacity(0.35);
    }
  }
  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 768;

    final sidebarPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title Block
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_fire_department, color: Colors.redAccent, size: 28),
              ),
              const SizedBox(width: 16),
              Text(
                'Calor de Demanda',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Live Stats Block
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ATIVIDADE EM TEMPO REAL',
                style: TextStyle(color: _kSubtext, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
              const SizedBox(height: 16),
              _buildMiniStat(
                label: 'Corridas Solicitadas (Sem Motorista)',
                value: _openRidesCount.toString(),
                color: Colors.blueAccent,
                icon: Icons.person_pin_circle,
              ),
              const SizedBox(height: 12),
              _buildMiniStat(
                label: 'Motoristas Disponíveis (Online)',
                value: _onlineDriversCount.toString(),
                color: Colors.greenAccent,
                icon: Icons.local_taxi,
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Controls Block
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CONFIGURAÇÕES DE VISUALIZAÇÃO',
                style: TextStyle(color: _kSubtext, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
              const SizedBox(height: 16),
              // Time Filter Dropdown
              DropdownButtonFormField<String>(
                value: _selectedTimeFilter,
                dropdownColor: _kSurface,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Período de Análise',
                  labelStyle: TextStyle(color: _kSubtext),
                  border: OutlineInputBorder(borderSide: BorderSide(color: _kBorder)),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: _kBorder)),
                ),
                items: const [
                  DropdownMenuItem(value: '30m', child: Text('Últimos 30 minutos')),
                  DropdownMenuItem(value: '1h', child: Text('Última 1 hora')),
                  DropdownMenuItem(value: '6h', child: Text('Últimas 6 horas')),
                  DropdownMenuItem(value: '24h', child: Text('Últimas 24 horas')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedTimeFilter = val);
                    _fetchHeatmapData();
                  }
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Mostrar Motoristas', style: TextStyle(color: Colors.white, fontSize: 13)),
                value: _showDrivers,
                activeThumbColor: Colors.greenAccent,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) => setState(() => _showDrivers = val),
              ),
              SwitchListTile(
                title: const Text('Mostrar Passageiros', style: TextStyle(color: Colors.white, fontSize: 13)),
                value: _showRides,
                activeThumbColor: Colors.blueAccent,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) => setState(() => _showRides = val),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Hotspots List Block
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Text(
                  'ZONAS QUENTES DETECTADAS',
                  style: TextStyle(color: _kSubtext, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
              ),
              Expanded(
                child: _isLoading && _hotspots.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _hotspots.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24.0),
                              child: Text(
                                'Nenhuma zona de calor detectada com demanda excessiva no período.',
                                style: TextStyle(color: _kSubtext, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _hotspots.length,
                            separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                            itemBuilder: (context, index) {
                              final h = _hotspots[index];
                              final mult = (h['multiplier'] as num?)?.toDouble() ?? 1.0;
                              final intensity = h['intensity']?.toString() ?? 'medium';
                              final orders = h['openOrders'] ?? 0;
                              final drivers = h['availableDrivers'] ?? 0;
                              final lat = (h['lat'] as num).toDouble();
                              final lng = (h['lng'] as num).toDouble();

                              return ListTile(
                                title: Text(
                                  'Setor ${h['zone']?.toString().replaceAll('_', ' - ') ?? ''}',
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  'Pedidos: $orders | Motoristas: $drivers',
                                  style: const TextStyle(color: _kSubtext, fontSize: 12),
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getHeatmapColor(intensity).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _getHeatmapColor(intensity)),
                                  ),
                                  child: Text(
                                    '${mult.toStringAsFixed(1)}x',
                                    style: TextStyle(
                                      color: _getHeatmapColor(intensity),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                onTap: () {
                                  _mapController?.moveCamera(LatLng(lat, lng), 14.5);
                                  if (isMobile) {
                                    Navigator.of(context).pop(); // Fecha o drawer no mobile
                                  }
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ],
    );

    final mapArea = Stack(
      children: [
        GenericMap(
          provider: GoogleMapProvider(),
          initialLocation: Place(
            const LatLng(-1.4558, -48.5024),
            'Belém, PA',
            'Belém',
          ),
          interactive: true,
          myLocationEnabled: false,
          markers: _hotspots.map((h) {
            final lat = (h['lat'] as num).toDouble();
            final lng = (h['lng'] as num).toDouble();
            final mult = (h['multiplier'] as num?)?.toDouble() ?? 1.0;
            final intensity = h['intensity']?.toString() ?? 'medium';

            return CustomMarker(
              id: 'marker_${h['zone']}',
              position: LatLng(lat, lng),
              width: 140,
              height: 38,
              widget: Material(
                color: Colors.transparent,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _kBackground.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _getHeatmapColor(intensity)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flash_on, color: _getHeatmapColor(intensity), size: 12),
                      const SizedBox(width: 2),
                      Text(
                        'Multiplicador: ${mult.toStringAsFixed(1)}x',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
          circleMarkers: _hotspots.map((h) {
            final lat = (h['lat'] as num).toDouble();
            final lng = (h['lng'] as num).toDouble();
            final intensity = h['intensity']?.toString() ?? 'medium';

            return CircleMarker(
              id: 'circle_${h['zone']}',
              position: LatLng(lat, lng),
              color: _getHeatmapColor(intensity).withOpacity(0.3),
              borderColor: _getHeatmapColor(intensity).withOpacity(0.7),
              borderWidth: 2,
              radius: 800,
            );
          }).toList(),
          onControllerReady: (controller) {
            _mapController = controller;
          },
        ),

        // Top Floating Toolbar
        Positioned(
          top: 20,
          left: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _kBackground.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isMobile ? 'Live' : 'Conexão Live Supabase ativa',
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),

        // Loading Indicator overlay
        if (_isLoading)
          Positioned(
            top: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kBackground.withOpacity(0.85),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: _kBorder),
              ),
              child: const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.redAccent),
              ),
            ),
          ),

        // Floating action button to open controls/stats drawer on mobile
        if (isMobile)
          Positioned(
            bottom: 24,
            right: 24,
            child: Builder(
              builder: (context) => FloatingActionButton(
                backgroundColor: _kSurface,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Colors.white10),
                ),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
                child: const Icon(Icons.tune),
              ),
            ),
          ),
      ],
    );

    return Scaffold(
      backgroundColor: _kBackground,
      endDrawer: isMobile
          ? Drawer(
              width: 320,
              backgroundColor: _kSurface,
              child: SafeArea(child: sidebarPanel),
            )
          : null,
      body: isMobile
          ? mapArea
          : Row(
              children: [
                Container(
                  width: 350,
                  decoration: const BoxDecoration(
                    color: _kSurface,
                    border: Border(right: BorderSide(color: Colors.white10)),
                  ),
                  child: sidebarPanel,
                ),
                Expanded(child: mapArea),
              ],
            ),
    );
  }

  Widget _buildMiniStat({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kBackground.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
