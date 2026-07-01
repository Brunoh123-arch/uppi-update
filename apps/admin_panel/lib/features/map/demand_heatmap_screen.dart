import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
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
  final MapController _mapController = MapController();
  List<Map<String, dynamic>> _hotspots = [];
  bool _isLoading = true;
  bool _showDrivers = true;
  bool _showRides = true;
  String _selectedTimeFilter = '30m'; // 30m, 1h, 6h, 24h
  
  // Realtime lists to show count on overlay
  int _onlineDriversCount = 0;
  int _openRidesCount = 0;

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchHeatmapData();
    _fetchCounts();
    // Refresh heatmap and counts every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _fetchHeatmapData();
      _fetchCounts();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchHeatmapData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      // Usando centro operacional (Belém - PA: -1.4558, -48.5024)
      final response = await Supabase.instance.client.functions.invoke(
        'get-driver-heatmap',
        body: {
          'lat': -1.4558,
          'lng': -48.5024,
          'time_filter': _selectedTimeFilter,
        },
      );

      if (response.status == 200 && mounted) {
        final data = response.data;
        if (data != null && data['hotspots'] != null) {
          setState(() {
            _hotspots = List<Map<String, dynamic>>.from(data['hotspots']);
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados do heatmap: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchCounts() async {
    try {
      final client = Supabase.instance.client;

      // 1. Motoristas online
      final driversRes = await client
          .from('driver_locations')
          .select('driver_id')
          .eq('status', 'online');
      
      // 2. Corridas abertas/aguardando
      final ridesRes = await client
          .from('rides')
          .select('id')
          .inFilter('status', ['requested', 'searching']);

      if (mounted) {
        setState(() {
          _onlineDriversCount = driversRes.length;
          _openRidesCount = ridesRes.length;
        });
      }
    } catch (e) {
      debugPrint('Erro ao buscar estatísticas do heatmap: $e');
    }
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
                                  _mapController.move(LatLng(lat, lng), 14.5);
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
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: LatLng(-1.4558, -48.5024),
            initialZoom: 13.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.uppi.admin',
            ),
            
            // Heatmap circle overlays
            CircleLayer(
              circles: _hotspots.map((h) {
                final lat = (h['lat'] as num).toDouble();
                final lng = (h['lng'] as num).toDouble();
                final intensity = h['intensity']?.toString() ?? 'medium';

                return CircleMarker(
                  point: LatLng(lat, lng),
                  color: _getHeatmapColor(intensity),
                  borderStrokeWidth: 1.5,
                  borderColor: _getHeatmapColor(intensity).withOpacity(0.8),
                  useRadiusInMeter: true,
                  radius: 800, // Raio aproximado da zona quente
                );
              }).toList(),
            ),

            // Markers
            MarkerLayer(
              markers: [
                // Hotspot label tags
                ..._hotspots.map((h) {
                  final lat = (h['lat'] as num).toDouble();
                  final lng = (h['lng'] as num).toDouble();
                  final mult = (h['multiplier'] as num?)?.toDouble() ?? 1.0;
                  final intensity = h['intensity']?.toString() ?? 'medium';

                  return Marker(
                    point: LatLng(lat, lng),
                    width: 100,
                    height: 30,
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
                  );
                }),
              ],
            ),
          ],
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
