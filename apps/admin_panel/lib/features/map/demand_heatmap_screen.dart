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

      // 1. Fetch real rides for historical/recent demand heatmap
      final ridesResponse = await Supabase.instance.client
          .from('rides')
          .select('id, pickup_location, status, created_at')
          .gte('created_at', cutoff.toIso8601String());

      final List<Map<String, dynamic>> rides = List<Map<String, dynamic>>.from(ridesResponse);
      final List<Map<String, dynamic>> calculatedHotspots = [];

      // Cluster by approximate coordinates (to 3 decimal places ~110m)
      if (rides.isNotEmpty) {
        final Map<String, List<Map<String, dynamic>>> clusters = {};
        for (var r in rides) {
          final loc = r['pickup_location']?.toString();
          if (loc != null) {
            final coords = _parsePostGISPoint(loc);
            if (coords != null) {
              final key = "${(coords.latitude * 100).round() / 100}_${(coords.longitude * 100).round() / 100}";
              clusters.putIfAbsent(key, () => []).add(r);
            }
          }
        }

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
              'id': 'real_$key',
              'zone': 'Setor_${key.replaceAll('.', 'd')}',
              'lat': lat,
              'lng': lng,
              'intensity': intensity,
              'multiplier': mult,
              'openOrders': count,
              'availableDrivers': (count * 0.4).round() + 1,
              'is_simulated': false,
            });
          }
        });
      }

      // 2. Fetch active simulated hotspots from database
      try {
        final simulatedResponse = await Supabase.instance.client
            .from('simulated_hotspots')
            .select()
            .or('expires_at.is.null,expires_at.gt.${DateTime.now().toUtc().toIso8601String()}');
        
        final List<Map<String, dynamic>> simulated = List<Map<String, dynamic>>.from(simulatedResponse);
        for (final sh in simulated) {
          calculatedHotspots.add({
            'id': sh['id'].toString(),
            'zone': sh['name'] ?? 'Calor Simulado',
            'lat': (sh['latitude'] as num).toDouble(),
            'lng': (sh['longitude'] as num).toDouble(),
            'intensity': sh['intensity']?.toString() ?? 'medium',
            'multiplier': (sh['multiplier'] as num?)?.toDouble() ?? 1.0,
            'openOrders': 5,
            'availableDrivers': 1,
            'is_simulated': true,
          });
        }
      } catch (e) {
        debugPrint('[Heatmap] Tabela simulated_hotspots ainda nao criada: $e');
      }

      // Fallback fallback mock coordinates (Castanhal coordinates instead of Belem)
      if (calculatedHotspots.isEmpty) {
        _hotspots = [
          {
            'id': 'mock_1',
            'zone': 'Castanhal Centro',
            'lat': -1.2950,
            'lng': -47.9250,
            'intensity': 'high',
            'multiplier': 1.5,
            'openOrders': 8,
            'availableDrivers': 2,
            'is_simulated': false,
          },
          {
            'id': 'mock_2',
            'zone': 'Estrela',
            'lat': -1.3020,
            'lng': -47.9180,
            'intensity': 'medium',
            'multiplier': 1.3,
            'openOrders': 4,
            'availableDrivers': 3,
            'is_simulated': false,
          }
        ];
      } else {
        _hotspots = calculatedHotspots;
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

  void _showSimulateHotspotModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final simulatedHotspots = _hotspots.where((h) => h['is_simulated'] == true).toList();
            
            return Container(
              padding: EdgeInsets.only(
                top: 24,
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Simulação de Calor de Demanda',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: _kSubtext),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Posicione o mapa no local desejado (o centro do mapa será o ponto de calor) e clique abaixo para simular a demanda.',
                    style: TextStyle(color: _kSubtext, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.local_fire_department, color: Colors.white),
                    label: const Text('Forçar Ponto de Calor Aqui', style: TextStyle(color: Colors.white)),
                    onPressed: () async {
                      final created = await _showCreateHotspotDialog(context);
                      if (created == true) {
                        _fetchHeatmapData();
                        setModalState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Pontos de Calor Simulados Ativos:',
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  if (simulatedHotspots.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'Nenhum ponto de calor simulado ativo.',
                          style: TextStyle(color: _kSubtext, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: simulatedHotspots.length,
                        itemBuilder: (context, index) {
                          final h = simulatedHotspots[index];
                          final id = h['id']?.toString() ?? '';
                          final zone = h['zone']?.toString() ?? 'Sem nome';
                          final multiplier = h['multiplier']?.toString() ?? '1.0';
                          final intensity = h['intensity']?.toString() ?? 'medium';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: _kBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _getHeatmapColor(intensity).withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.local_fire_department, color: _getHeatmapColor(intensity)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        zone,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        'Multiplicador: ${multiplier}x | Intensidade: $intensity',
                                        style: const TextStyle(color: _kSubtext, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: _kSurface,
                                        title: const Text('Deletar Ponto de Calor', style: TextStyle(color: Colors.white)),
                                        content: const Text(
                                          'Tem certeza que deseja remover este ponto de calor simulado?',
                                          style: TextStyle(color: _kSubtext),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: const Text('Cancelar', style: TextStyle(color: _kSubtext)),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: const Text('Excluir', style: TextStyle(color: Colors.redAccent)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await Supabase.instance.client
                                          .from('simulated_hotspots')
                                          .delete()
                                          .eq('id', id);
                                      await _fetchHeatmapData();
                                      setModalState(() {});
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<bool?> _showCreateHotspotDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final multCtrl = TextEditingController(text: '1.5');
    final durationCtrl = TextEditingController(text: '60');
    String selectedIntensity = 'medium';

    final center = await _mapController?.getCenter() ?? const LatLng(-1.2950, -47.9250);

    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: _kSurface,
              title: const Text('Simular Ponto de Calor', style: TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Nome da Zona (Ex: Apeú)',
                        labelStyle: TextStyle(color: _kSubtext),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _kBorder)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedIntensity,
                      dropdownColor: _kSurface,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Intensidade',
                        labelStyle: TextStyle(color: _kSubtext),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _kBorder)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Baixa')),
                        DropdownMenuItem(value: 'medium', child: Text('Média')),
                        DropdownMenuItem(value: 'high', child: Text('Alta')),
                        DropdownMenuItem(value: 'extreme', child: Text('Extrema')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setStateDialog(() => selectedIntensity = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: multCtrl,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Multiplicador de Preço (Ex: 1.50)',
                        labelStyle: TextStyle(color: _kSubtext),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _kBorder)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: durationCtrl,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Duração (minutos)',
                        labelStyle: TextStyle(color: _kSubtext),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _kBorder)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar', style: TextStyle(color: _kSubtext)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final mult = double.tryParse(multCtrl.text) ?? 1.5;
                    final duration = int.tryParse(durationCtrl.text) ?? 60;

                    if (name.isEmpty) return;

                    try {
                      await Supabase.instance.client.from('simulated_hotspots').insert({
                        'name': name,
                        'latitude': center.latitude,
                        'longitude': center.longitude,
                        'intensity': selectedIntensity,
                        'multiplier': mult,
                        'expires_at': DateTime.now().toUtc().add(Duration(minutes: duration)).toIso8601String(),
                      });
                      Navigator.pop(ctx, true);
                    } catch (e) {
                      debugPrint('Erro ao criar ponto de calor simulado: $e');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
                      );
                    }
                  },
                  child: const Text('Salvar', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
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
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('Simular Calor de Demanda'),
                onPressed: () => _showSimulateHotspotModal(context),
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
            const LatLng(-1.2950, -47.9250),
            'Castanhal, PA',
            'Castanhal',
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
