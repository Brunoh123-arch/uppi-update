import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:generic_map/generic_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';

class GlobalMapScreen extends StatefulWidget {
  const GlobalMapScreen({super.key});

  @override
  State<GlobalMapScreen> createState() => _GlobalMapScreenState();
}

class _GlobalMapScreenState extends State<GlobalMapScreen> {
  MapViewController? _mapController;
  
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

  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  
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
    // Refresh periódico a cada 30s apenas como safety net para o heatmap e posições
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_showHeatmap) _fetchHeatmap();
      _refreshLocations();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _locationSubscription?.cancel();
    _ridesSubscription?.cancel();
    _broadcastChannel?.unsubscribe();
    _surgeZonesRealtimeChannel?.unsubscribe();
    _refreshTimer?.cancel();
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

  // 1. Carrega posições iniciais
  void _startRealtimeLocationStream() {
    if (!mounted) return;
    
    // Carrega posições iniciais dos motoristas
    _refreshLocations();

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
          if (data.isNotEmpty) {
            for (var d in data) {
              final driverId = d['driver_id']?.toString() ?? '';
              if (driverId.isNotEmpty) {
                _driverPins[driverId] = d;
              }
            }
          } else {
            _loadFromProfiles();
          }
          _isLoading = false;
        });
        _autoCenterIfNeeded();
      }
    } catch (_) {
      _loadFromProfiles();
    }
  }

  void _autoCenterIfNeeded() {
    if (_hasCentered || _driverPins.isEmpty) return;
    
    // Centraliza no primeiro motorista encontrado
    final first = _driverPins.values.first;
    final lat = (first['lat'] as num?)?.toDouble() ?? 0;
    final lng = (first['lng'] as num?)?.toDouble() ?? 0;
    if (lat != 0 && lng != 0) {
      _hasCentered = true;
      _mapController?.moveCamera(LatLng(lat, lng), 14.0);
    }
  }

  Future<void> _showDriverDetailsDialog(String driverId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 1. Fetch profile details
      final profileRes = await Supabase.instance.client
          .from('profiles')
          .select('full_name, phone, phone_number, status')
          .eq('id', driverId)
          .maybeSingle();

      // 2. Fetch driver documents details (vehicle plate and model)
      final docRes = await Supabase.instance.client
          .from('driver_documents')
          .select('vehicle_plate, vehicle_model, vehicle_category')
          .eq('driver_id', driverId)
          .maybeSingle();

      if (mounted) Navigator.pop(context); // Dismiss loading spinner

      if (profileRes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Motorista nao encontrado.")));
        }
        return;
      }

      final name = profileRes['full_name']?.toString() ?? 'Motorista';
      final phone = profileRes['phone'] ?? profileRes['phone_number'] ?? 'Nao informado';
      final status = profileRes['status']?.toString() ?? 'online';
      
      final plate = docRes?['vehicle_plate']?.toString() ?? '';
      final model = docRes?['vehicle_model']?.toString() ?? '';
      final category = docRes?['vehicle_category']?.toString() ?? '';
      final vehicleText = model.isNotEmpty ? "$model ($plate)" : "Nao cadastrado";

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Row(
                children: [
                  const Icon(Icons.local_taxi, color: Colors.orangeAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("ID: $driverId", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 10),
                  Text("Celular: $phone", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  Text("Veiculo: $vehicleText", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (category.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text("Categoria: ${category.toUpperCase()}", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    "Status do Perfil: ${status.toUpperCase()}",
                    style: TextStyle(
                      color: (status == 'online' || status == 'approved' || status == 'active') ? Colors.greenAccent : Colors.orangeAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Fechar", style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (confirmCtx) => AlertDialog(
                        backgroundColor: const Color(0xFF1E293B),
                        title: const Text("Desconectar Motorista", style: TextStyle(color: Colors.white)),
                        content: const Text("Tem certeza que deseja forcar o motorista a ficar Offline?"),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(confirmCtx, false), child: const Text("Nao")),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: () => Navigator.pop(confirmCtx, true),
                            child: const Text("Sim, Forcar Offline"),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      try {
                        await Supabase.instance.client
                            .from('driver_locations')
                            .delete()
                            .eq('driver_id', driverId);
                        
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text("✅ Motorista desconectado do mapa com sucesso!"),
                            backgroundColor: Colors.green,
                          ));
                          _refreshLocations();
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Erro: $e"), backgroundColor: Colors.red));
                        }
                      }
                    }
                  },
                  child: const Text("Forcar Offline", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao carregar detalhes: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _showPassengerDetailsDialog(String rideId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final rideRes = await Supabase.instance.client
          .from('rides')
          .select('pickup_address, dropoff_address, fare, rider_id')
          .eq('id', rideId)
          .maybeSingle();

      if (mounted) Navigator.pop(context); // Dismiss loading spinner

      if (rideRes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Corrida nao encontrada.")));
        }
        return;
      }

      final riderId = rideRes['rider_id']?.toString() ?? '';
      Map<String, dynamic>? profileRes;
      if (riderId.isNotEmpty) {
        profileRes = await Supabase.instance.client
            .from('profiles')
            .select('full_name, phone, phone_number')
            .eq('id', riderId)
            .maybeSingle();
      }

      final name = profileRes?['full_name']?.toString() ?? 'Passageiro';
      final phone = profileRes?['phone'] ?? profileRes?['phone_number'] ?? 'Nao informado';
      final pickup = rideRes['pickup_address'] ?? 'Nao informado';
      final destination = rideRes['dropoff_address'] ?? 'Nao informado';
      final fare = (rideRes['fare'] as num?)?.toDouble() ?? 0.0;

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Row(
                children: [
                  const Icon(Icons.person, color: Colors.blueAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Celular: $phone", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 10),
                  Text("Origem: $pickup", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  Text("Destino: $destination", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  Text("Valor: R\$ ${fare.toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFF6C9F12), fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  const Text("Status: Aguardando Motorista", style: TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Fechar", style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (confirmCtx) => AlertDialog(
                        backgroundColor: const Color(0xFF1E293B),
                        title: const Text("Cancelar Corrida", style: TextStyle(color: Colors.white)),
                        content: const Text("Tem certeza que deseja cancelar esta corrida do passageiro?"),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(confirmCtx, false), child: const Text("Nao")),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: () => Navigator.pop(confirmCtx, true),
                            child: const Text("Sim, Cancelar"),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      try {
                        await Supabase.instance.client
                            .from('rides')
                            .update({'status': 'cancelled'})
                            .eq('id', rideId);
                        
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text("✅ Corrida cancelada com sucesso!"),
                            backgroundColor: Colors.green,
                          ));
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Erro: $e"), backgroundColor: Colors.red));
                        }
                      }
                    }
                  },
                  child: const Text("Cancelar Corrida", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao carregar detalhes: $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _performSearch(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    final q = query.toLowerCase();
    final results = <Map<String, dynamic>>[];

    _driverPins.forEach((id, d) {
      final name = (d['full_name'] ?? '').toString().toLowerCase();
      final phone = (d['phone'] ?? d['phone_number'] ?? '').toString().toLowerCase();
      if (name.contains(q) || phone.contains(q) || id.toLowerCase().contains(q)) {
        results.add({
          'type': 'driver',
          'id': id,
          'name': d['full_name'] ?? 'Motorista ($id)',
          'subtitle': 'Motorista • ${d['vehicle_type'] ?? "Carro"}',
          'lat': d['lat'],
          'lng': d['lng'],
        });
      }
    });

    _passengerPins.forEach((id, p) {
      if (id.toLowerCase().contains(q)) {
        results.add({
          'type': 'passenger',
          'id': id,
          'name': 'Passageiro (Corrida)',
          'subtitle': 'ID: ${id.substring(0, 8)}',
          'lat': p['lat'],
          'lng': p['lng'],
        });
      }
    });

    setState(() {
      _searchResults = results;
      _isSearching = true;
    });
  }

  void _zoomToResult(Map<String, dynamic> res) {
    final lat = res['lat'] as double;
    final lng = res['lng'] as double;
    _mapController?.moveCamera(LatLng(lat, lng), 15.5);
    
    _searchController.clear();
    setState(() {
      _searchResults = [];
      _isSearching = false;
    });

    if (res['type'] == 'driver') {
      _showDriverDetailsDialog(res['id']);
    } else {
      _showPassengerDetailsDialog(res['id']);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 768;
    final activeDrivers = _driverPins.values.where((d) {
      final lat = (d['lat'] as num?)?.toDouble() ?? 0;
      final lng = (d['lng'] as num?)?.toDouble() ?? 0;
      return lat != 0 && lng != 0;
    }).toList();

    final List<CustomMarker> customMarkers = [];
    final List<CircleMarker> circleMarkers = [];

    // 1. Drivers
    for (final d in activeDrivers) {
      final lat = (d['lat'] as num).toDouble();
      final lng = (d['lng'] as num).toDouble();
      final vehicleType = d['vehicle_type']?.toString() ?? 'carro';
      final driverId = d['driver_id']?.toString() ?? '?';
      final name = d['full_name']?.toString() ?? (driverId.length > 8 ? driverId.substring(0, 8) : driverId);
      
      customMarkers.add(CustomMarker(
        id: 'driver_$driverId',
        position: LatLng(lat, lng),
        width: 48,
        height: 48,
        widget: GestureDetector(
          onTap: () => _showDriverDetailsDialog(driverId),
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
        ),
      ));
    }

    // 2. Passenger Pins
    for (final entry in _passengerPins.entries) {
      final p = entry.value;
      final lat = (p['lat'] as num).toDouble();
      final lng = (p['lng'] as num).toDouble();
      
      customMarkers.add(CustomMarker(
        id: 'passenger_${entry.key}',
        position: LatLng(lat, lng),
        width: 48,
        height: 48,
        widget: GestureDetector(
          onTap: () => _showPassengerDetailsDialog(entry.key),
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
        ),
      ));
    }

    // 3. Heatmap circles
    if (_showHeatmap) {
      for (int i = 0; i < _hotspots.length; i++) {
        final h = _hotspots[i];
        final lat = (h['lat'] as num).toDouble();
        final lng = (h['lng'] as num).toDouble();
        final intensity = h['intensity']?.toString() ?? 'medium';
        
        Color color = Colors.yellow.withOpacity(0.3);
        if (intensity == 'high') color = Colors.orange.withOpacity(0.4);
        if (intensity == 'extreme') color = Colors.red.withOpacity(0.5);

        circleMarkers.add(CircleMarker(
          id: 'heatmap_$i',
          position: LatLng(lat, lng),
          radius: 1000.0, // ~1km
          color: color,
          borderColor: Colors.transparent,
          borderWidth: 0,
        ));
      }
    }

    // 4. Surge Zones circles and labels
    for (final zone in _surgeZones) {
      final points = _getSurgeZonePoints(zone);
      if (points.isEmpty) continue;
      final centroid = _calculateCentroid(points);
      
      final distance = const Distance();
      final double radius = distance.as(LengthUnit.Meter, centroid, points.first);
      
      final name = zone['name'] ?? 'Zona';
      final mult = (zone['multiplier'] as num?)?.toDouble() ?? 1.0;
      final zoneId = zone['id']?.toString() ?? 'zone_${DateTime.now().millisecondsSinceEpoch}';

      circleMarkers.add(CircleMarker(
        id: 'surge_circle_$zoneId',
        position: centroid,
        radius: radius > 0 ? radius : 1000.0,
        color: _getSurgeColor(mult),
        borderColor: _getSurgeBorderColor(mult),
        borderWidth: 3.0,
      ));

      customMarkers.add(CustomMarker(
        id: 'surge_label_$zoneId',
        position: centroid,
        width: 140,
        height: 36,
        widget: Container(
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
      ));
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Map Layer
          GenericMap(
            provider: GoogleMapProvider(),
            initialLocation: Place(
              const LatLng(-1.2950, -47.9250),
              'Castanhal, PA',
              'Castanhal',
            ),
            interactive: true,
            myLocationEnabled: false,
            markers: customMarkers,
            circleMarkers: circleMarkers,
            onControllerReady: (controller) {
              _mapController = controller;
            },
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

          // Floating Command Center Search
          Positioned(
            top: 90,
            left: isMobile ? 16 : 32,
            right: isMobile ? 16 : null,
            child: Container(
              width: isMobile ? null : 360,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: _performSearch,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Buscar motorista no mapa...',
                      hintStyle: const TextStyle(color: Colors.white30),
                      prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white54, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                _performSearch('');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  if (_isSearching && _searchResults.isNotEmpty) ...[
                    const Divider(color: Colors.white10, height: 1),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final res = _searchResults[index];
                          return ListTile(
                            dense: true,
                            title: Text(res['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            subtitle: Text(res['subtitle'], style: const TextStyle(color: Colors.white54)),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 10, color: Colors.white30),
                            onTap: () => _zoomToResult(res),
                          );
                        },
                      ),
                    ),
                  ],
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
                      _mapController?.moveCamera(
                        LatLng(
                          (first['lat'] as num).toDouble(),
                          (first['lng'] as num).toDouble(),
                        ),
                        14.0,
                      );
                    } else {
                      _mapController?.moveCamera(const LatLng(-1.2950, -47.9250), 13.0);
                    }
                  },
                ),
                const SizedBox(width: 12),
                _ControlButton(
                  icon: Icons.flash_on,
                  label: 'Tarifa Dinâmica',
                  color: Colors.amberAccent,
                  onTap: () => _showSurgeManagementModal(context),
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

  String _generateCircularWkt(double centerLat, double centerLng, double radiusInMeters) {
    const int pointsCount = 32;
    final List<String> coordinates = [];
    
    for (int i = 0; i <= pointsCount; i++) {
      final double angle = (i * 2 * math.pi) / pointsCount;
      final double deltaLat = (radiusInMeters * math.cos(angle)) / 111320.0;
      final double latRad = centerLat * math.pi / 180.0;
      final double deltaLng = (radiusInMeters * math.sin(angle)) / (111320.0 * math.cos(latRad));
      
      final double pointLat = centerLat + deltaLat;
      final double pointLng = centerLng + deltaLng;
      
      coordinates.add('${pointLng.toStringAsFixed(6)} ${pointLat.toStringAsFixed(6)}');
    }
    
    return 'POLYGON((${coordinates.join(', ')}))';
  }

  Future<bool?> _showCreateSurgeDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final multCtrl = TextEditingController(text: '1.25');
    final radiusCtrl = TextEditingController(text: '1000');
    final durationCtrl = TextEditingController(text: '60');
    
    final center = await _mapController?.getCenter() ?? const LatLng(-1.2950, -47.9250);
    
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Nova Zona Dinâmica', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Nome da Zona (Ex: Centro Castanhal)',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
                TextField(
                  controller: multCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Multiplicador (Ex: 1.50)',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
                TextField(
                  controller: radiusCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Raio de Alcance (metros)',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
                TextField(
                  controller: durationCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duração Ativa (minutos)',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF096EFF)),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final mult = double.tryParse(multCtrl.text) ?? 1.25;
                final radius = double.tryParse(radiusCtrl.text) ?? 1000.0;
                final duration = int.tryParse(durationCtrl.text) ?? 60;
                
                if (name.isEmpty) return;
                
                final wkt = _generateCircularWkt(center.latitude, center.longitude, radius);
                
                try {
                  await Supabase.instance.client.from('surge_zones').insert({
                    'name': name,
                    'multiplier': mult,
                    'boundary': wkt,
                    'is_active': true,
                    'expires_at': DateTime.now().toUtc().add(Duration(minutes: duration)).toIso8601String(),
                  });
                  Navigator.pop(ctx, true);
                } catch (e) {
                  debugPrint('Erro ao criar surge zone: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('Criar Zona', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showSurgeManagementModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                        'Gestão de Tarifa Dinâmica (Surge)',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white60),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF096EFF),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Criar Nova Zona Dinâmica', style: TextStyle(color: Colors.white)),
                    onPressed: () async {
                      final created = await _showCreateSurgeDialog(context);
                      if (created == true) {
                        _fetchSurgeZones();
                        setModalState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Zonas Ativas no Mapa:',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  if (_surgeZones.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('Nenhuma zona de tarifa dinâmica ativa.', style: TextStyle(color: Colors.white38)),
                    )
                  else
                    Container(
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _surgeZones.length,
                        itemBuilder: (context, index) {
                          final zone = _surgeZones[index];
                          final id = zone['id']?.toString() ?? '';
                          final name = zone['name']?.toString() ?? 'Sem nome';
                          final multiplier = zone['multiplier']?.toString() ?? '1.0';
                          final expiresAt = zone['expires_at'] != null 
                              ? DateTime.parse(zone['expires_at'].toString()).toLocal()
                              : null;
                              
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.flash_on, color: Colors.amberAccent),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      Text(
                                        'Multiplicador: ${multiplier}x' + 
                                        (expiresAt != null ? ' | Expira: ${expiresAt.hour.toString().padLeft(2, '0')}:${expiresAt.minute.toString().padLeft(2, '0')}' : ''),
                                        style: const TextStyle(color: Colors.white70, fontSize: 13),
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
                                        backgroundColor: const Color(0xFF1E293B),
                                        title: const Text('Deletar Zona', style: TextStyle(color: Colors.white)),
                                        content: const Text('Tem certeza que deseja remover esta zona de preço dinâmico?', style: TextStyle(color: Colors.white70)),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: const Text('Cancelar', style: TextStyle(color: Colors.white38)),
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
                                          .from('surge_zones')
                                          .delete()
                                          .eq('id', id);
                                      _fetchSurgeZones();
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
