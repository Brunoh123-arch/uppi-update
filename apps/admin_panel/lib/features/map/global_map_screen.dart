import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';

class GlobalMapScreen extends StatefulWidget {
  const GlobalMapScreen({super.key});

  @override
  State<GlobalMapScreen> createState() => _GlobalMapScreenState();
}

class _GlobalMapScreenState extends State<GlobalMapScreen> {
  final MapController _mapController = MapController();
  
  // Dados de motoristas vindos da tabela driver_locations (persistido)
  final Map<String, Map<String, dynamic>> _driverPins = {};
  
  // Passageiros pedindo corrida em realtime
  final Map<String, Map<String, dynamic>> _passengerPins = {};
  
  // Zonas de calor (Heatmap) vindas da Edge Function
  List<Map<String, dynamic>> _hotspots = [];
  bool _showHeatmap = true;

  // Zonas de surge ativas
  List<Map<String, dynamic>> _surgeZones = [];

  bool _isLoading = true;
  bool _hasCentered = false;
  
  StreamSubscription? _locationSubscription;
  StreamSubscription? _ridesSubscription;
  RealtimeChannel? _broadcastChannel;
  RealtimeChannel? _surgeZonesRealtimeChannel;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _startRealtimeLocationStream();
    _startBroadcastListener();
    _startSurgeZonesListener();
    _fetchHeatmap();
    _fetchSurgeZones();
    // Refresh periódico a cada 30s apenas como safety net para o heatmap
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_showHeatmap) _fetchHeatmap();
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _ridesSubscription?.cancel();
    _broadcastChannel?.unsubscribe();
    _surgeZonesRealtimeChannel?.unsubscribe();
    _refreshTimer?.cancel();
    _streamReconnectTimer?.cancel();
    _broadcastReconnectTimer?.cancel();
    super.dispose();
  }

  void _startSurgeZonesListener() {
    _surgeZonesRealtimeChannel?.unsubscribe();
    _surgeZonesRealtimeChannel = Supabase.instance.client
        .channel('public:surge_zones')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'surge_zones',
          callback: (payload) {
            _fetchSurgeZones();
            if (_showHeatmap) _fetchHeatmap();
          },
        );
    _surgeZonesRealtimeChannel!.subscribe();
  }

  // 0. Fetch Heatmap
  Future<void> _fetchHeatmap() async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'get-driver-heatmap',
        body: {'lat': -1.4558, 'lng': -48.5024},
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
      debugPrint('Error loading heatmap: $e');
    }
  }

  // 0.1 Fetch Active Surge Zones
  Future<void> _fetchSurgeZones() async {
    try {
      final data = await Supabase.instance.client
          .from('vw_surge_zones')
          .select()
          .eq('is_active', true);
      
      final activeZones = List<Map<String, dynamic>>.from(data).where((z) {
        final expiresAtStr = z['expires_at'] as String?;
        if (expiresAtStr == null) return true;
        final expiresAt = DateTime.tryParse(expiresAtStr);
        if (expiresAt == null) return true;
        return expiresAt.isAfter(DateTime.now());
      }).toList();

      if (mounted) {
        setState(() {
          _surgeZones = activeZones;
        });
      }
    } catch (e) {
      debugPrint('Error loading surge zones on map: $e');
    }
  }

  // Helper colors for surge zones based on multiplier
  Color _getSurgeColor(double multiplier) {
    if (multiplier < 1.5) {
      return Colors.yellow.withOpacity(0.2);
    } else if (multiplier < 2.0) {
      return Colors.orange.withOpacity(0.2);
    } else {
      return Colors.red.withOpacity(0.25);
    }
  }

  Color _getSurgeBorderColor(double multiplier) {
    if (multiplier < 1.5) {
      return Colors.yellowAccent;
    } else if (multiplier < 2.0) {
      return Colors.orangeAccent;
    } else {
      return Colors.redAccent;
    }
  }

  List<LatLng> _parseWKT(String wkt) {
    try {
      final match = RegExp(r'POLYGON\s*\(\((.*?)\)\)', caseSensitive: false).firstMatch(wkt);
      if (match == null) return [];
      final coordsStr = match.group(1)!;
      final points = coordsStr.split(',').map((coord) {
        final parts = coord.trim().split(RegExp(r'\s+'));
        final lng = double.parse(parts[0]);
        final lat = double.parse(parts[1]);
        return LatLng(lat, lng);
      }).toList();
      if (points.length > 1 && points.first == points.last) {
        points.removeLast(); // remove duplicate closing point
      }
      return points;
    } catch (e) {
      debugPrint('Erro ao parsear WKT no mapa: $e');
      return [];
    }
  }

  List<LatLng> _getSurgeZonePoints(Map<String, dynamic> zone) {
    final wkt = zone['boundary_wkt'] as String? ?? '';
    if (wkt.isNotEmpty) {
      final points = _parseWKT(wkt);
      if (points.isNotEmpty) return points;
    }

    final coords = zone['polygon_coords'] as List?;
    if (coords != null && coords.isNotEmpty) {
      try {
        final points = coords.map((p) {
          if (p is List && p.length >= 2) {
            final lng = (p[0] as num).toDouble();
            final lat = (p[1] as num).toDouble();
            return LatLng(lat, lng);
          }
          return null;
        }).whereType<LatLng>().toList();
        return points;
      } catch (e) {
        debugPrint('Erro ao parsear polygon_coords: $e');
      }
    }
    return [];
  }

  LatLng _calculateCentroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0, 0);
    double latSum = 0;
    double lngSum = 0;
    for (final p in points) {
      latSum += p.latitude;
      lngSum += p.longitude;
    }
    return LatLng(latSum / points.length, lngSum / points.length);
  }

  // 1. Stream da tabela driver_locations (INSERT/UPDATE) com reconexão exponencial
  Timer? _streamReconnectTimer;
  int _streamReconnectDelay = 2; // Começa com 2s

  void _startRealtimeLocationStream() {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    _locationSubscription?.cancel();
    _locationSubscription = Supabase.instance.client
        .from('driver_locations')
        .stream(primaryKey: ['driver_id'])
        .listen((List<Map<String, dynamic>> data) {
          _streamReconnectDelay = 2; // Reseta no sucesso
          if (mounted) {
            setState(() {
              for (var d in data) {
                final driverId = d['driver_id']?.toString() ?? '';
                if (driverId.isNotEmpty) {
                  _driverPins[driverId] = d;
                }
              }
              _isLoading = false;
            });
            _autoCenterIfNeeded();
          }
        }, onError: (error) {
          debugPrint('Error loading realtime driver locations: $error');
          if (mounted) setState(() => _isLoading = false);
          
          // Fallback: tenta carregar do profiles
          _loadFromProfiles();

          // Reconexão exponencial
          _streamReconnectTimer?.cancel();
          if (mounted) {
            _streamReconnectTimer = Timer(Duration(seconds: _streamReconnectDelay), () {
              _streamReconnectDelay = (_streamReconnectDelay * 2).clamp(2, 30);
              _startRealtimeLocationStream();
            });
          }
        });

    _ridesSubscription?.cancel();
    _ridesSubscription = Supabase.instance.client
        .from('rides')
        .stream(primaryKey: ['id'])
        .listen((List<Map<String, dynamic>> data) {
          if (mounted) {
            setState(() {
              _passengerPins.clear();
              for (var d in data) {
                final status = d['status'];
                if (status == 'requested' || status == 'searching') {
                  final rideId = d['id']?.toString() ?? '';
                  final loc = d['pickup_location']?.toString() ?? '';
                  if (rideId.isNotEmpty && loc.toUpperCase().contains('POINT')) {
                    // Parsing robusto de POINT(lng lat) do PostGIS WKT
                    final match = RegExp(r'POINT\s*\(\s*([^\)]+)\s*\)', caseSensitive: false).firstMatch(loc);
                    if (match != null) {
                      final content = match.group(1)?.trim() ?? '';
                      final coords = content.split(RegExp(r'\s+'));
                      if (coords.length >= 2) {
                        final lng = double.tryParse(coords[0]);
                        final lat = double.tryParse(coords[1]);
                        if (lat != null && lng != null) {
                          _passengerPins[rideId] = {
                            'id': rideId,
                            'lng': lng,
                            'lat': lat,
                            'status': status,
                          };
                        }
                      }
                    }
                  }
                }
              }
            });
          }
        }, onError: (error) {
          debugPrint('Error loading realtime rides: $error');
        });
  }

  // 2. Broadcast Realtime (em memória — com reconexão ativa e exponencial)
  Timer? _broadcastReconnectTimer;
  int _broadcastReconnectDelay = 2; // Começa com 2s

  void _startBroadcastListener() {
    if (!mounted) return;
    try {
      if (_broadcastChannel != null) {
        try {
          Supabase.instance.client.removeChannel(_broadcastChannel!);
        } catch (_) {}
      }

      _broadcastChannel = Supabase.instance.client.channel('driver_locations');
      
      _broadcastChannel!.onBroadcast(
        event: 'location_update',
        callback: (payload) {
          final driverId = payload['driver_id']?.toString() ?? '';
          if (driverId.isEmpty) return;
          
          if (mounted) {
            setState(() {
              final existing = _driverPins[driverId];
              _driverPins[driverId] = {
                'driver_id': driverId,
                'lat': payload['lat'],
                'lng': payload['lng'],
                'heading': payload['heading'],
                'vehicle_type': payload['vehicle_type'] ?? existing?['vehicle_type'] ?? 'carro',
                'marker_url': payload['marker_url'] ?? existing?['marker_url'],
                'updated_at': DateTime.now().toIso8601String(),
              };
            });
            _autoCenterIfNeeded();
          }
        },
      );

      _broadcastChannel!.subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          _broadcastReconnectDelay = 2; // Reseta no sucesso
        } else if (status == RealtimeSubscribeStatus.channelError || 
                   status == RealtimeSubscribeStatus.timedOut) {
          // Tenta restabelecer canal usando reconexão exponencial reativa
          _broadcastReconnectTimer?.cancel();
          if (mounted) {
            _broadcastReconnectTimer = Timer(Duration(seconds: _broadcastReconnectDelay), () {
              _broadcastReconnectDelay = (_broadcastReconnectDelay * 2).clamp(2, 30);
              _startBroadcastListener();
            });
          }
        }
      });
    } catch (e) {
      debugPrint('Broadcast listener error: $e');
    }
  }

  // 3. Fallback: busca profiles com status online
  Future<void> _loadFromProfiles() async {
    try {
      final profiles = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, status, current_location')
          .eq('role', 'driver')
          .eq('status', 'online');
      
      if (mounted && profiles.isNotEmpty) {
        setState(() {
          for (var p in profiles) {
            // current_location é um PostGIS point: "SRID=4326;POINT(lng lat)"
            final loc = p['current_location']?.toString() ?? '';
            if (loc.contains('POINT')) {
              final coords = loc.replaceAll(RegExp(r'[^0-9.\-\s]'), '').trim().split(RegExp(r'\s+'));
              if (coords.length >= 2) {
                _driverPins[p['id']] = {
                  'driver_id': p['id'],
                  'lng': double.tryParse(coords[0]) ?? 0,
                  'lat': double.tryParse(coords[1]) ?? 0,
                  'vehicle_type': 'carro',
                  'full_name': p['full_name'],
                };
              }
            }
          }
          _isLoading = false;
        });
        _autoCenterIfNeeded();
      }
    } catch (e) {
      debugPrint('Fallback profiles load error: $e');
    }
  }

  // 4. Refresh periódico
  Future<void> _refreshLocations() async {
    try {
      final data = await Supabase.instance.client
          .from('driver_locations')
          .select()
          .order('updated_at', ascending: false)
          .limit(200);
      
      if (mounted) {
        setState(() {
          for (var d in data) {
            final driverId = d['driver_id']?.toString() ?? '';
            if (driverId.isNotEmpty) {
              _driverPins[driverId] = d;
            }
          }
        });
      }
    } catch (_) {}
  }

  void _autoCenterIfNeeded() {
    if (_hasCentered || _driverPins.isEmpty) return;
    
    // Centraliza no primeiro motorista encontrado
    final first = _driverPins.values.first;
    final lat = (first['lat'] as num?)?.toDouble() ?? 0;
    final lng = (first['lng'] as num?)?.toDouble() ?? 0;
    if (lat != 0 && lng != 0) {
      _hasCentered = true;
      _mapController.move(LatLng(lat, lng), 14.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeDrivers = _driverPins.values.where((d) {
      final lat = (d['lat'] as num?)?.toDouble() ?? 0;
      final lng = (d['lng'] as num?)?.toDouble() ?? 0;
      return lat != 0 && lng != 0;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Map Layer
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              // Centraliza em Belém-PA (onde está a operação Uppi)
              initialCenter: LatLng(-1.4558, -48.5024),
              initialZoom: 13.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.uppi.admin',
              ),
              if (_showHeatmap)
                CircleLayer(
                  circles: _hotspots.map((h) {
                    final lat = (h['lat'] as num).toDouble();
                    final lng = (h['lng'] as num).toDouble();
                    final intensity = h['intensity']?.toString() ?? 'medium';
                    
                    Color color = Colors.yellow.withOpacity(0.3);
                    if (intensity == 'high') color = Colors.orange.withOpacity(0.4);
                    if (intensity == 'extreme') color = Colors.red.withOpacity(0.5);

                    return CircleMarker(
                      point: LatLng(lat, lng),
                      color: color,
                      borderStrokeWidth: 0,
                      useRadiusInMeter: true,
                      radius: 1000, // ~1km zone
                    );
                  }).toList(),
                ),
              PolygonLayer(
                polygons: _surgeZones.map((zone) {
                  final points = _getSurgeZonePoints(zone);
                  if (points.length < 3) return null;
                  final mult = (zone['multiplier'] as num?)?.toDouble() ?? 1.0;
                  return Polygon(
                    points: points,
                    color: _getSurgeColor(mult),
                    borderColor: _getSurgeBorderColor(mult),
                    borderStrokeWidth: 3,
                    isFilled: true,
                  );
                }).whereType<Polygon>().toList(),
              ),
              MarkerLayer(
                markers: [
                  ...activeDrivers.map((d) {
                    final lat = (d['lat'] as num).toDouble();
                    final lng = (d['lng'] as num).toDouble();
                    final vehicleType = d['vehicle_type']?.toString() ?? 'carro';
                    final driverId = d['driver_id']?.toString() ?? '?';
                    final name = d['full_name']?.toString() ?? driverId.substring(0, 8);
                    
                    return Marker(
                      point: LatLng(lat, lng),
                      width: 48,
                      height: 48,
                      child: Tooltip(
                        message: '$name ($vehicleType)',
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.orange.shade800,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orangeAccent.withOpacity(0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.local_taxi,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    );
                  }),
                  ..._passengerPins.values.map((p) {
                    final lat = (p['lat'] as num).toDouble();
                    final lng = (p['lng'] as num).toDouble();
                    return Marker(
                      point: LatLng(lat, lng),
                      width: 48,
                      height: 48,
                      child: Tooltip(
                        message: 'Passageiro aguardando motorista',
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blueAccent.withOpacity(0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.person_pin_circle,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    );
                  }),
                  ..._surgeZones.map((zone) {
                    final points = _getSurgeZonePoints(zone);
                    if (points.isEmpty) return null;
                    final centroid = _calculateCentroid(points);
                    final name = zone['name'] ?? 'Zona';
                    final mult = (zone['multiplier'] as num?)?.toDouble() ?? 1.0;
                    return Marker(
                      point: centroid,
                      width: 140,
                      height: 36,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withOpacity(0.85),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _getSurgeBorderColor(mult), width: 1.5),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black54,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.flash_on, color: _getSurgeBorderColor(mult), size: 14),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '$name: ${mult.toStringAsFixed(2)}x',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).whereType<Marker>().toList(),
                ],
              ),
            ],
          ),

          // Top Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0F172A).withOpacity(0.95),
                    const Color(0xFF0F172A).withOpacity(0.0),
                  ],
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'Mapa Operacional em Tempo Real',
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  const _InfoChip(
                    icon: Icons.circle,
                    label: 'Realtime ativo',
                    color: Colors.greenAccent,
                  ),
                  const SizedBox(width: 12),
                  _InfoChip(
                    icon: Icons.flash_on,
                    label: '${_surgeZones.length} zonas de surge',
                    color: Colors.amberAccent,
                  ),
                  const SizedBox(width: 12),
                  _InfoChip(
                    icon: Icons.person_search,
                    label: '${_passengerPins.length} buscando motorista',
                    color: Colors.blueAccent,
                  ),
                  const SizedBox(width: 12),
                  _InfoChip(
                    icon: Icons.local_taxi,
                    label: '${activeDrivers.length} motoristas no mapa',
                    color: Colors.orangeAccent,
                  ),
                ],
              ),
            ),
          ),

          // Empty state
          if (!_isLoading && activeDrivers.isEmpty)
            Center(
              child: Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_off, size: 64, color: Colors.white24),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhum motorista online no momento',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        color: Colors.white54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Quando motoristas ficarem online, eles aparecerão aqui em tempo real.',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

          // Bottom Control Panel
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: Row(
              children: [
                _ControlButton(
                  icon: Icons.shield_outlined,
                  label: 'Anti-Fraude',
                  color: Colors.redAccent,
                  onTap: () => _showAntiFraudModal(context),
                ),
                const SizedBox(width: 12),
                _ControlButton(
                  icon: Icons.history,
                  label: 'Auditoria',
                  color: Colors.amber,
                  onTap: () => _showAuditLogModal(context),
                ),
                const SizedBox(width: 12),
                _ControlButton(
                  icon: _showHeatmap ? Icons.map_outlined : Icons.map,
                  label: _showHeatmap ? 'Ocultar Heatmap' : 'Ver Heatmap',
                  color: Colors.deepOrangeAccent,
                  onTap: () {
                    setState(() {
                      _showHeatmap = !_showHeatmap;
                    });
                    if (_showHeatmap && _hotspots.isEmpty) {
                      _fetchHeatmap();
                    }
                  },
                ),
                const SizedBox(width: 12),
                _ControlButton(
                  icon: Icons.refresh,
                  label: 'Atualizar',
                  color: ColorPalette.primary50,
                  onTap: () {
                    _refreshLocations();
                    _loadFromProfiles();
                    _fetchSurgeZones();
                    if (_showHeatmap) _fetchHeatmap();
                  },
                ),
                const SizedBox(width: 12),
                _ControlButton(
                  icon: Icons.center_focus_strong,
                  label: 'Centralizar',
                  color: Colors.blueAccent,
                  onTap: () {
                    if (activeDrivers.isNotEmpty) {
                      final first = activeDrivers.first;
                      _mapController.move(
                        LatLng(
                          (first['lat'] as num).toDouble(),
                          (first['lng'] as num).toDouble(),
                        ),
                        14.0,
                      );
                    } else {
                      _mapController.move(const LatLng(-1.4558, -48.5024), 13.0);
                    }
                  },
                ),
              ],
            ),
          ),

          // Loading overlay
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  // ========== ANTI-FRAUD MODAL ==========
  void _showAntiFraudModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            width: 700,
            constraints: const BoxConstraints(maxHeight: 600),
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield, color: Colors.redAccent, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Monitoramento Anti-Fraude',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Motoristas com taxa de cancelamento superior a 30% (minimo 5 corridas)',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: Supabase.instance.client
                        .from('high_risk_drivers')
                        .stream(primaryKey: ['driver_id'])
                        .order('cancellation_rate', ascending: false),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final drivers = snapshot.data as List? ?? [];
                      if (drivers.isEmpty) {
                        return const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified_user, color: Colors.greenAccent, size: 64),
                              SizedBox(height: 16),
                              Text(
                                'Nenhum motorista de alto risco detectado',
                                style: TextStyle(color: Colors.white70, fontSize: 16),
                              ),
                            ],
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: drivers.length,
                        separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                        itemBuilder: (context, index) {
                          final d = drivers[index];
                          final rate = (d['cancellation_rate'] as num?)?.toDouble() ?? 0;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.redAccent.withOpacity(0.2),
                              child: const Icon(Icons.warning_amber, color: Colors.redAccent),
                            ),
                            title: Text(
                              d['full_name']?.toString() ?? 'Motorista ${d['driver_id']?.toString().substring(0, 8)}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Corridas: ${d['total_rides']} | Canceladas: ${d['canceled_rides']}',
                              style: const TextStyle(color: Colors.white54),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                              ),
                              child: Text(
                                '${rate.toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ========== AUDIT LOG MODAL ==========
  void _showAuditLogModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            width: 800,
            constraints: const BoxConstraints(maxHeight: 600),
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.history, color: Colors.amber, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Log de Auditoria Administrativa',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Registro completo de todas as acoes administrativas realizadas',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: Supabase.instance.client
                        .from('admin_audit_log')
                        .stream(primaryKey: ['id'])
                        .order('created_at', ascending: false)
                        .limit(50),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final logs = snapshot.data ?? [];
                      if (logs.isEmpty) {
                        return const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 64),
                              SizedBox(height: 16),
                              Text(
                                'Nenhuma acao registrada ainda',
                                style: TextStyle(color: Colors.white70, fontSize: 16),
                              ),
                            ],
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: logs.length,
                        separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                        itemBuilder: (context, index) {
                          final log = logs[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.amber.withOpacity(0.15),
                              child: const Icon(Icons.gavel, color: Colors.amber, size: 20),
                            ),
                            title: Text(
                              log['action_type']?.toString() ?? 'Acao desconhecida',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              'Admin: ${log['admin_id']?.toString().substring(0, 8) ?? '?'} | Alvo: ${log['target_user_id']?.toString().substring(0, 8) ?? '-'}',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            trailing: Text(
                              log['created_at']?.toString().substring(0, 16) ?? '',
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ========== HELPER WIDGETS ==========

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withOpacity(0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
