import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:generic_map/generic_map.dart';
import 'package:latlong2/latlong.dart';

class LiveDispatchScreen extends StatefulWidget {
  const LiveDispatchScreen({super.key});

  @override
  State<LiveDispatchScreen> createState() => _LiveDispatchScreenState();
}

class _LiveDispatchScreenState extends State<LiveDispatchScreen> {
  MapViewController? _mapController;
  
  List<Map<String, dynamic>> _activeRides = [];
  Map<String, dynamic>? _selectedRide;
  
  List<Map<String, dynamic>> _currentOffers = [];
  List<Map<String, dynamic>> _nearbyDrivers = [];
  
  bool _isLoadingRides = true;
  bool _isLoadingDrivers = false;
  
  StreamSubscription? _ridesSubscription;
  RealtimeChannel? _offersChannel;
  RealtimeChannel? _driversChannel;
  RealtimeChannel? _driverLocationsBroadcastChannel;
  final Map<String, LatLng> _driverLiveLocations = {};

  @override
  void initState() {
    super.initState();
    _startRidesRealtimeStream();
    _startDriverLocationsBroadcastListener();
  }

  @override
  void dispose() {
    _ridesSubscription?.cancel();
    _unsubscribeFromSelectedRide();
    _driverLocationsBroadcastChannel?.unsubscribe();
    super.dispose();
  }

  void _startDriverLocationsBroadcastListener() {
    try {
      _driverLocationsBroadcastChannel = Supabase.instance.client.channel('driver_locations');
      _driverLocationsBroadcastChannel!.onBroadcast(
        event: 'location_update',
        callback: (payload) {
          final driverId = payload['driver_id']?.toString() ?? '';
          final lat = (payload['lat'] as num?)?.toDouble();
          final lng = (payload['lng'] as num?)?.toDouble();
          
          if (driverId.isNotEmpty && lat != null && lng != null) {
            if (mounted) {
              setState(() {
                _driverLiveLocations[driverId] = LatLng(lat, lng);
              });
            }
          }
        },
      );
      _driverLocationsBroadcastChannel!.subscribe();
    } catch (e) {
      debugPrint("Error starting driver locations broadcast listener: $e");
    }
  }

  void _subscribeToSelectedRideRealtime(String rideId) {
    _unsubscribeFromSelectedRide();

    _offersChannel = Supabase.instance.client
        .channel('public:ride_offers')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ride_offers',
          callback: (payload) {
            _fetchActiveOffersForSelectedRide();
          },
        );
    _offersChannel!.subscribe();

    _driversChannel = Supabase.instance.client
        .channel('public:profiles')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          callback: (payload) {
            _fetchNearbyDriversForSelectedRide();
          },
        );
    _driversChannel!.subscribe();
  }

  void _unsubscribeFromSelectedRide() {
    if (_offersChannel != null) {
      Supabase.instance.client.removeChannel(_offersChannel!);
      _offersChannel = null;
    }
    if (_driversChannel != null) {
      Supabase.instance.client.removeChannel(_driversChannel!);
      _driversChannel = null;
    }
  }

  // Stream active rides
  void _startRidesRealtimeStream() {
    _ridesSubscription?.cancel();
    _ridesSubscription = Supabase.instance.client
        .from('rides')
        .stream(primaryKey: ['id'])
        .listen((List<Map<String, dynamic>> data) {
          if (mounted) {
            setState(() {
              _activeRides = data.where((r) {
                final status = r['status'];
                return status == 'requested' || status == 'searching';
              }).toList();
              
              _isLoadingRides = false;
              
              // Maintain selected ride updated if status changes
              if (_selectedRide != null) {
                final updated = data.firstWhere(
                  (r) => r['id'] == _selectedRide!['id'],
                  orElse: () => <String, dynamic>{},
                );
                if (updated.isNotEmpty) {
                  final newStatus = updated['status'];
                  if (newStatus != 'requested' && newStatus != 'searching') {
                    _selectedRide = null;
                    _currentOffers.clear();
                    _nearbyDrivers.clear();
                    _unsubscribeFromSelectedRide();
                  } else {
                    _selectedRide = updated;
                  }
                } else {
                  _selectedRide = null;
                  _currentOffers.clear();
                  _nearbyDrivers.clear();
                  _unsubscribeFromSelectedRide();
                }
              }
            });
          }
        }, onError: (err) {
          debugPrint("Error streaming active rides: $err");
          if (mounted) setState(() => _isLoadingRides = false);
        });
  }

  // Fetch active offers and nearby drivers for the selected ride
  Future<void> _fetchActiveOffersForSelectedRide() async {
    if (_selectedRide == null) return;
    final rideId = _selectedRide!['id'];
    
    try {
      // 1. Fetch offers
      final offersData = await Supabase.instance.client
          .from('ride_offers')
          .select('*, profiles:driver_id(full_name, phone_number, current_location)')
          .eq('ride_id', rideId)
          .order('created_at', ascending: false);
          
      if (mounted) {
        setState(() {
          _currentOffers = List<Map<String, dynamic>>.from(offersData);
        });
      }
    } catch (e) {
      debugPrint("Error loading ride offers: $e");
    }
  }

  Future<void> _fetchNearbyDriversForSelectedRide() async {
    if (_selectedRide == null) return;
    setState(() => _isLoadingDrivers = true);
    
    try {
      // Fetch online drivers
      final driversData = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, phone_number, current_location, status')
          .eq('role', 'driver')
          .eq('status', 'online');
          
      if (mounted) {
        setState(() {
          _nearbyDrivers = List<Map<String, dynamic>>.from(driversData);
          _isLoadingDrivers = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading online drivers: $e");
      if (mounted) setState(() => _isLoadingDrivers = false);
    }
  }

  // Manual dispatch override call
  Future<void> _forceDispatchToDriver(String driverId) async {
    if (_selectedRide == null) return;
    final rideId = _selectedRide!['id'];
    
    // Display confirmation
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Confirmar Intervenção", style: TextStyle(color: Colors.white)),
        content: const Text(
          "Deseja forçar a atribuição imediata desta corrida para este motorista? O loop automático será cancelado.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar", style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF096EFF)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Confirmar", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    try {
      // Force assign driver RPC
      await Supabase.instance.client.rpc('assign_driver_to_ride', params: {
        'p_ride_id': rideId,
        'p_driver_id': driverId,
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Despacho manual efetuado com sucesso!"),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _selectedRide = null;
          _currentOffers.clear();
          _nearbyDrivers.clear();
          _unsubscribeFromSelectedRide();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erro no despacho manual: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  LatLng? _parsePostGISPoint(String? loc) {
    if (loc == null || !loc.toUpperCase().contains('POINT')) return null;
    try {
      final match = RegExp(r'POINT\s*\(\s*([^\)]+)\s*\)', caseSensitive: false).firstMatch(loc);
      if (match != null) {
        final content = match.group(1)?.trim() ?? '';
        final coords = content.split(RegExp(r'\s+'));
        if (coords.length >= 2) {
          final lng = double.tryParse(coords[0]);
          final lat = double.tryParse(coords[1]);
          if (lat != null && lng != null) {
            return LatLng(lat, lng);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    LatLng? pickupLatLng;
    LatLng? dropoffLatLng;
    
    if (_selectedRide != null) {
      pickupLatLng = _parsePostGISPoint(_selectedRide!['pickup_location']?.toString());
      dropoffLatLng = _parsePostGISPoint(_selectedRide!['dropoff_location']?.toString());
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 768;

    final sidebarPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          color: const Color(0xFF0F172A),
          child: Row(
            children: [
              const Icon(Icons.flash_on, color: Color(0xFF096EFF), size: 28),
              const SizedBox(width: 12),
              Text(
                "Uppi Live Dispatch",
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        
        // Header status info
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: const Color(0xFF1E293B),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "CORRIDAS AGUARDANDO",
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "${_activeRides.length} ativas",
                  style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              )
            ],
          ),
        ),
        
        // Rides List
        Expanded(
          child: _isLoadingRides
              ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Color(0xFF096EFF))))
              : _activeRides.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, color: const Color(0xFF6C9F12).withOpacity(0.5), size: 48),
                          const SizedBox(height: 12),
                          const Text("Nenhuma corrida pendente", style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _activeRides.length,
                      itemBuilder: (context, index) {
                        final ride = _activeRides[index];
                        final isSelected = _selectedRide != null && _selectedRide!['id'] == ride['id'];
                        final status = ride['status']?.toString().toUpperCase() ?? 'REQUESTED';
                        
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF334155) : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF096EFF) : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            title: Text(
                              ride['pickup_address'] ?? "Ponto de Partida",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  "Destino: ${ride['dropoff_address'] ?? 'Não informado'}",
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "R\$ ${double.tryParse(ride['fare']?.toString() ?? '0')?.toStringAsFixed(2)}",
                                      style: const TextStyle(color: Color(0xFF6C9F12), fontWeight: FontWeight.bold),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: status == 'SEARCHING' ? const Color(0xFF096EFF).withOpacity(0.1) : Colors.amber.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(
                                          color: status == 'SEARCHING' ? const Color(0xFF096EFF) : Colors.amber,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            onTap: () {
                              setState(() {
                                _selectedRide = ride;
                              });
                              _fetchActiveOffersForSelectedRide();
                              _fetchNearbyDriversForSelectedRide();
                              _subscribeToSelectedRideRealtime(ride['id'].toString());
                              
                              if (pickupLatLng != null) {
                                _mapController?.moveCamera(pickupLatLng, 14.5);
                              }
                              if (isMobile) {
                                Navigator.of(context).pop(); // Close drawer on mobile
                              }
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );

    // Build markers list for GenericMap
    final List<CustomMarker> markers = [];
    if (pickupLatLng != null) {
      markers.add(CustomMarker(
        id: 'pickup',
        position: pickupLatLng,
        width: 54,
        height: 54,
        widget: const Material(
          color: Colors.transparent,
          child: Tooltip(
            message: "Embarque (Passageiro)",
            child: Icon(Icons.person_pin_circle, color: Colors.blueAccent, size: 45),
          ),
        ),
      ));
    }
    if (dropoffLatLng != null) {
      markers.add(CustomMarker(
        id: 'dropoff',
        position: dropoffLatLng,
        width: 54,
        height: 54,
        widget: const Material(
          color: Colors.transparent,
          child: Tooltip(
            message: "Desembarque",
            child: Icon(Icons.location_on, color: Colors.redAccent, size: 45),
          ),
        ),
      ));
    }

    if (_currentOffers.isNotEmpty) {
      for (final offer in _currentOffers.where((offer) => offer['status'] == 'offered')) {
        final driver = offer['profiles'];
        final driverId = driver?['id']?.toString() ?? '';
        LatLng? loc;
        if (driverId.isNotEmpty && _driverLiveLocations.containsKey(driverId)) {
          loc = _driverLiveLocations[driverId];
        } else {
          loc = driver != null ? _parsePostGISPoint(driver['current_location']?.toString()) : null;
        }
        final driverName = driver != null ? driver['full_name']?.toString() ?? 'Motorista' : 'Motorista';
        
        if (loc != null) {
          markers.add(CustomMarker(
            id: 'driver_$driverId',
            position: loc,
            width: 80,
            height: 65,
            widget: Material(
              color: Colors.transparent,
              child: Tooltip(
                message: "OFERTA ATIVA: $driverName",
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C9F12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text("15s OFFER", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                    const Icon(Icons.local_taxi, color: Colors.greenAccent, size: 36),
                  ],
                ),
              ),
            ),
          ));
        }
      }
    }

    final mapArea = Stack(
      children: [
        // Map Area
        GenericMap(
          provider: GoogleMapProvider(),
          initialLocation: Place(
            const LatLng(-1.4558, -48.5024),
            'Belém, PA',
            'Belém',
          ),
          interactive: true,
          myLocationEnabled: false,
          markers: markers,
          onControllerReady: (controller) {
            _mapController = controller;
          },
        ),
        
        // Floating active matching loop state panel
        if (_selectedRide != null)
          Positioned(
            top: isMobile ? null : 20,
            right: isMobile ? 10 : 20,
            left: isMobile ? 10 : null,
            bottom: isMobile ? 10 : 20,
            child: Container(
              width: isMobile ? null : 420,
              height: isMobile ? MediaQuery.of(context).size.height * 0.45 : null,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.92),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF334155), width: 1.5),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 15, offset: Offset(0, 5))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header close button
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            "Detalhes do Matching Loop",
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => setState(() {
                            _selectedRide = null;
                            _currentOffers.clear();
                            _nearbyDrivers.clear();
                            _unsubscribeFromSelectedRide();
                          }),
                        )
                      ],
                    ),
                  ),
                  
                  // Dispatch summary
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: const Color(0xFF0F172A),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Embarque: ${_selectedRide!['pickup_address'] ?? 'Não informado'}",
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Tarifa: R\$ ${double.tryParse(_selectedRide!['fare']?.toString() ?? '0')?.toStringAsFixed(2)}",
                          style: const TextStyle(color: Color(0xFF6C9F12), fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  
                  // Active dispatch loop status
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "STATUS DA FILA DE MATCHING",
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        if (_currentOffers.isEmpty)
                          const Text("Nenhuma oferta despachada ainda. Procurando...", style: TextStyle(color: Colors.white60, fontSize: 13))
                        else
                          ..._currentOffers.take(isMobile ? 1 : 3).map((offer) {
                            final driver = offer['profiles'];
                            final driverName = driver != null ? driver['full_name']?.toString() ?? 'Motorista' : 'Motorista';
                            final status = offer['status']?.toString().toUpperCase() ?? 'PENDING';
                            
                            Color statusColor = Colors.orangeAccent;
                            if (status == 'ACCEPTED') statusColor = const Color(0xFF6C9F12);
                            if (status == 'EXPIRED') statusColor = Colors.redAccent;
                            if (status == 'REJECTED') statusColor = Colors.grey;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(driverName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                        const SizedBox(height: 2),
                                        Text(
                                          "Expirado em: ${offer['expires_at'] != null ? DateTime.parse(offer['expires_at']).toLocal().toString().substring(11, 19) : '-'}",
                                          style: const TextStyle(color: Colors.white30, fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      status,
                                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                  
                  // Manual Override - Online drivers list
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text(
                                  "INTERVENÇÃO MANUAL (DRIVERS ONLINE)",
                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.refresh, color: Color(0xFF096EFF), size: 18),
                                onPressed: _fetchNearbyDriversForSelectedRide,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _isLoadingDrivers
                                ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Color(0xFF096EFF))))
                                : _nearbyDrivers.isEmpty
                                    ? const Center(child: Text("Nenhum motorista online no momento", style: TextStyle(color: Colors.white30, fontSize: 12)))
                                    : ListView.builder(
                                        itemCount: _nearbyDrivers.length,
                                        itemBuilder: (context, index) {
                                          final driver = _nearbyDrivers[index];
                                          final driverName = driver['full_name'] ?? 'Sem Nome';
                                          final driverPhone = driver['phone_number'] ?? '-';
                                          
                                          return Container(
                                            margin: const EdgeInsets.only(bottom: 8),
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF0F172A).withOpacity(0.6),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: Colors.white.withOpacity(0.04)),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(driverName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                                      const SizedBox(height: 2),
                                                      Text("Celular: $driverPhone", style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                                                    ],
                                                  ),
                                                ),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: const Color(0xFF096EFF),
                                                    foregroundColor: Colors.white,
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                  ),
                                                  onPressed: () => _forceDispatchToDriver(driver['id']),
                                                  child: const Text("FORÇAR", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                )
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                          )
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
        // Floating action button to open controls/queues drawer on mobile
        if (isMobile && _selectedRide == null)
          Positioned(
            bottom: 24,
            right: 24,
            child: Builder(
              builder: (context) => FloatingActionButton(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Colors.white10),
                ),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
                child: const Icon(Icons.menu),
              ),
            ),
          ),
      ],
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      endDrawer: isMobile
          ? Drawer(
              width: 320,
              backgroundColor: const Color(0xFF1E293B),
              child: SafeArea(child: sidebarPanel),
            )
          : null,
      body: isMobile
          ? mapArea
          : Row(
              children: [
                Container(
                  width: 380,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E293B),
                    border: Border(right: BorderSide(color: Color(0xFF334155), width: 1)),
                  ),
                  child: sidebarPanel,
                ),
                Expanded(child: mapArea),
              ],
            ),
    );
  }
}
