import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/entities/driver_location.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:flutter_common/core/entities/payment_method_union.dart';
import 'package:flutter_common/core/presentation/waypoints_view/waypoints_view.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/features/home/presentation/blocs/home.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/core/entities/order_request.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:latlong2/latlong.dart';

class RidesRadarSheet extends StatefulWidget {
  final DriverLocation? driverLocation;

  // Notificador estático que expõe a corrida selecionada do radar para o mapa (HomeMapView)
  static final ValueNotifier<OrderRequestEntity?> selectedRadarRideNotifier = ValueNotifier<OrderRequestEntity?>(null);

  // Cache estático de rotas de percurso do radar para evitar chamadas de rede redundantes
  static final Map<String, List<LatLngEntity>> _radarRouteCache = {};

  const RidesRadarSheet({super.key, this.driverLocation});

  @override
  State<RidesRadarSheet> createState() => _RidesRadarSheetState();
}

class _RidesRadarSheetState extends State<RidesRadarSheet> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Stream<List<Map<String, dynamic>>>? _ridesStream;
  bool _accepting = false;
  String? _acceptingRideId;

  @override
  void initState() {
    super.initState();
    
    // Animação de pulso do radar
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Stream de tempo real do Supabase: escuta novas corridas solicitadas ('requested')
    // criadas nas últimas 2 horas
    final twoHoursAgo = DateTime.now().toUtc().subtract(const Duration(hours: 2)).toIso8601String();
    
    _ridesStream = Supabase.instance.client
        .from('rides')
        .stream(primaryKey: ['id'])
        .eq('status', 'requested')
        .map((events) {
          // Filtrar em memória corridas criadas nas últimas 2 horas
          final filtered = events.where((row) {
            final createdAtStr = row['created_at']?.toString();
            if (createdAtStr == null) return false;
            final createdAt = DateTime.tryParse(createdAtStr);
            if (createdAt == null) return false;
            return createdAt.toUtc().isAfter(DateTime.parse(twoHoursAgo));
          }).toList();

          // Deduplicar pelo id (evita duplicatas vindas de atualizações do realtime)
          final seenIds = <String>{};
          final deduplicated = filtered.where((row) {
            final id = row['id']?.toString();
            if (id == null) return false;
            return seenIds.add(id); // add retorna false se já existia
          }).toList();

          // Se a localização do motorista estiver disponível, calcula distâncias e ordena
          final driverLoc = widget.driverLocation;
          if (driverLoc != null) {
            for (var ride in deduplicated) {
              final pickupLat = (ride['pickup_lat'] as num?)?.toDouble();
              final pickupLng = (ride['pickup_lng'] as num?)?.toDouble();
              if (pickupLat != null && pickupLng != null) {
                ride['_distance_to_driver'] = _calculateDistance(
                  driverLoc.lat,
                  driverLoc.lng,
                  pickupLat,
                  pickupLng,
                );
              } else {
                ride['_distance_to_driver'] = 9999999.0;
              }
            }
            // Ordena por distância até o embarque (mais próximas primeiro)
            deduplicated.sort((a, b) {
              final distA = (a['_distance_to_driver'] as double? ?? 9999999.0);
              final distB = (b['_distance_to_driver'] as double? ?? 9999999.0);
              return distA.compareTo(distB);
            });
          }
          return deduplicated;
        });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    // Limpa a corrida do radar selecionada ao fechar o painel, removendo a rota do mapa
    RidesRadarSheet.selectedRadarRideNotifier.value = null;
    super.dispose();
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371000; // Raio da Terra em metros
    final double dLat = (lat2 - lat1) * (math.pi / 180.0);
    final double dLon = (lon2 - lon1) * (math.pi / 180.0);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180.0)) *
            math.cos(lat2 * (math.pi / 180.0)) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  List<LatLng> _decodePolyline(String polyline) {
    List<LatLng> points = [];
    int index = 0, len = polyline.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;
      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  Future<List<LatLngEntity>> _fetchRideRoute(Map<String, dynamic> ride) async {
    final rideId = ride['id'].toString();
    if (RidesRadarSheet._radarRouteCache.containsKey(rideId)) {
      return RidesRadarSheet._radarRouteCache[rideId]!;
    }
    
    final pickupLat = (ride['pickup_lat'] as num?)?.toDouble() ?? 0.0;
    final pickupLng = (ride['pickup_lng'] as num?)?.toDouble() ?? 0.0;
    final dropoffLat = (ride['dropoff_lat'] as num?)?.toDouble() ?? 0.0;
    final dropoffLng = (ride['dropoff_lng'] as num?)?.toDouble() ?? 0.0;
    
    List<LatLngEntity> routePoints = [];
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'get-directions',
        body: {
          'origin': '$pickupLat,$pickupLng',
          'destination': '$dropoffLat,$dropoffLng',
        },
      );
      if (response.status == 200 && response.data != null) {
        final data = response.data;
        if (data['status'] == 'OK' && data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final overviewPolyline = route['overview_polyline'];
          if (overviewPolyline != null && overviewPolyline['points'] != null) {
            final points = _decodePolyline(overviewPolyline['points'].toString());
            routePoints = points.map((p) => LatLngEntity(lat: p.latitude, lng: p.longitude)).toList();
          }
        }
      }
    } catch (e) {
      debugPrint('[RadarSheet] Erro ao buscar rota da Edge Function: $e');
    }
    
    if (routePoints.isEmpty) {
      routePoints = [
        LatLngEntity(lat: pickupLat, lng: pickupLng),
        LatLngEntity(lat: dropoffLat, lng: dropoffLng),
      ];
    }
    
    RidesRadarSheet._radarRouteCache[rideId] = routePoints;
    return routePoints;
  }

  void _selectRide(Map<String, dynamic> ride) async {
    final rideId = ride['id'].toString();
    
    final pickupLat = (ride['pickup_lat'] as num?)?.toDouble() ?? 0.0;
    final pickupLng = (ride['pickup_lng'] as num?)?.toDouble() ?? 0.0;
    final dropoffLat = (ride['dropoff_lat'] as num?)?.toDouble() ?? 0.0;
    final dropoffLng = (ride['dropoff_lng'] as num?)?.toDouble() ?? 0.0;
    
    final List<PlaceEntity> waypoints = [
      PlaceEntity(
        coordinates: LatLngEntity(lat: pickupLat, lng: pickupLng),
        address: ride['pickup_address']?.toString() ?? 'Origem',
      ),
      PlaceEntity(
        coordinates: LatLngEntity(lat: dropoffLat, lng: dropoffLng),
        address: ride['dropoff_address']?.toString() ?? 'Destino',
      ),
    ];
    
    // Busca rota e desenha no mapa principal
    final route = await _fetchRideRoute(ride);
    
    final paymentMethodStr = ride['payment_method']?.toString() ?? 'cash';
    final paymentMethod = paymentMethodStr == 'wallet'
        ? const PaymentMethodUnion.wallet()
        : const PaymentMethodUnion.cash();
        
    final entity = OrderRequestEntity(
      id: rideId,
      status: OrderStatus.requested,
      paymentMethod: paymentMethod,
      currency: 'BRL',
      fee: (ride['fare'] as num?)?.toDouble() ?? 0.0,
      providerShare: (ride['platform_fee'] as num?)?.toDouble() ?? 0.0,
      distance: (ride['distance_meters'] as num?)?.toInt() ?? 0,
      duration: (ride['duration_seconds'] as num?)?.toInt() ?? 0,
      serviceName: ride['service_type']?.toString() ?? "Standard",
      route: route,
      waypoints: waypoints,
      rideOptions: [],
      riderFirstName: 'Passageiro',
      riderLastName: '',
      riderPhotoUrl: null,
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
    
    if (mounted) {
      RidesRadarSheet.selectedRadarRideNotifier.value = entity;
    }
  }

  Future<void> _acceptRide(Map<String, dynamic> ride) async {
    if (_accepting) return;
    final rideId = ride['id'].toString();
    setState(() {
      _accepting = true;
      _acceptingRideId = rideId;
    });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'driver-flow-actions',
        body: {
          'action': 'accept-order',
          'orderId': rideId,
        },
      );

      if (response.status == 200) {
        if (mounted) {
          context.showSnackBar(message: 'Viagem aceita com sucesso!');
          Navigator.of(context).pop(); // Fecha o radar
          // Disparar refresh no HomeBloc para sincronizar estado imediato e entrar na viagem
          locator<HomeBloc>().onStarted(driverLocation: widget.driverLocation);
        }
      } else {
        final data = response.data;
        String errorMsg = 'Erro ao aceitar corrida.';
        if (data is Map) {
          errorMsg = data['error']?.toString() ?? data['message']?.toString() ?? errorMsg;
        }
        if (mounted) {
          context.showErrorSnackBar(errorMsg);
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Falha na conexão ao aceitar a corrida: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _accepting = false;
          _acceptingRideId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 15,
            spreadRadius: 2,
          )
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Alça superior da bottom sheet
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4.5,
                decoration: BoxDecoration(
                  color: ColorPalette.neutral90,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            // Cabeçalho do Radar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.orange.withOpacity(0.08 * _pulseAnimation.value),
                          border: Border.all(
                            color: Colors.orangeAccent.withOpacity(0.3 * _pulseAnimation.value),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          Ionicons.radio,
                          color: Colors.orangeAccent.withOpacity(_pulseAnimation.value),
                          size: 20,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Radar de Viagens',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Corridas pendentes na sua região',
                          style: TextStyle(
                            color: ColorPalette.neutral50,
                            fontSize: 12,
                          ),
                        )
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Ionicons.close_circle, color: ColorPalette.neutral80, size: 28),
                  )
                ],
              ),
            ),
            const Divider(height: 1, color: ColorPalette.neutral90),

            // Lista de Corridas do Stream
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.65,
                ),
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _ridesStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(color: ColorPalette.primary40),
                        ),
                      );
                    }

                    final List<Map<String, dynamic>> rides = snapshot.data ?? [];

                    if (rides.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Ionicons.sparkles_outline, size: 48, color: ColorPalette.neutral80),
                              const SizedBox(height: 12),
                              const Text(
                                'Tudo calmo por aqui!',
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Aguardando novas solicitações de corrida...',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: ColorPalette.neutral60,
                                  fontSize: 13,
                                ),
                              )
                            ],
                          ),
                        ),
                      );
                    }

                    // Se houver corridas e nenhuma selecionada ainda, seleciona a primeira por padrão
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final currentSelected = RidesRadarSheet.selectedRadarRideNotifier.value;
                      if (currentSelected == null || !rides.any((r) => r['id'].toString() == currentSelected.id)) {
                        _selectRide(rides.first);
                      }
                    });

                    return ValueListenableBuilder<OrderRequestEntity?>(
                      valueListenable: RidesRadarSheet.selectedRadarRideNotifier,
                      builder: (context, selectedRide, _) {
                        return ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: rides.length,
                          itemBuilder: (context, index) {
                            final ride = rides[index];
                            final rideId = ride['id'].toString();
                            final isThisSelected = selectedRide?.id == rideId;
                            final isThisAccepting = _accepting && _acceptingRideId == rideId;
                            final distanceToDriver = ride['_distance_to_driver'] as double?;

                            return RadarRideCard(
                              key: ValueKey(rideId),
                              ride: ride,
                              isSelected: isThisSelected,
                              accepting: _accepting,
                              isThisAccepting: isThisAccepting,
                              distanceToDriver: distanceToDriver,
                              onTap: () => _selectRide(ride),
                              onAccept: () => _acceptRide(ride),
                              onExpired: () {
                                // Se a corrida selecionada expirou na contagem regressiva local, limpa a seleção
                                if (isThisSelected) {
                                  RidesRadarSheet.selectedRadarRideNotifier.value = null;
                                }
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Card de Corrida customizado com seu próprio Timer para contagem regressiva de segundos
class RadarRideCard extends StatefulWidget {
  final Map<String, dynamic> ride;
  final bool isSelected;
  final VoidCallback onTap;
  final bool accepting;
  final bool isThisAccepting;
  final VoidCallback onAccept;
  final VoidCallback onExpired;
  final double? distanceToDriver;

  const RadarRideCard({
    super.key,
    required this.ride,
    required this.isSelected,
    required this.onTap,
    required this.accepting,
    required this.isThisAccepting,
    required this.onAccept,
    required this.onExpired,
    this.distanceToDriver,
  });

  @override
  State<RadarRideCard> createState() => _RadarRideCardState();
}

class _RadarRideCardState extends State<RadarRideCard> {
  Timer? _timer;
  int _remainingSeconds = 300;
  bool _isExpired = false;

  @override
  void initState() {
    super.initState();
    _calculateRemainingTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      _calculateRemainingTime();
    });
  }

  void _calculateRemainingTime() {
    final createdAtStr = widget.ride['created_at']?.toString();
    if (createdAtStr == null) {
      setState(() {
        _isExpired = true;
      });
      widget.onExpired();
      return;
    }
    final createdAt = DateTime.tryParse(createdAtStr)?.toLocal();
    if (createdAt == null) {
      setState(() {
        _isExpired = true;
      });
      widget.onExpired();
      return;
    }
    final now = DateTime.now();
    final elapsedSeconds = now.difference(createdAt).inSeconds;
    // O tempo limite para uma corrida no radar é de 5 minutos (300 segundos)
    final remaining = (300 - elapsedSeconds).clamp(0, 300);
    
    if (remaining <= 0 && !_isExpired) {
      setState(() {
        _remainingSeconds = 0;
        _isExpired = true;
      });
      _timer?.cancel();
      widget.onExpired();
    } else {
      setState(() {
        _remainingSeconds = remaining;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    if (_isExpired) {
      return const SizedBox.shrink();
    }

    final fare = (widget.ride['fare'] as num?)?.toDouble() ?? 0.0;
    final distance = (widget.ride['distance_meters'] as num?)?.toDouble() ?? 0.0;
    final durationSeconds = (widget.ride['duration_seconds'] as num?)?.toInt() ?? 0;

    final List<PlaceEntity> waypoints = [];
    final pickupAddress = widget.ride['pickup_address']?.toString() ?? 'Embarque';
    final dropoffAddress = widget.ride['dropoff_address']?.toString() ?? 'Destino';
    final pickupLat = (widget.ride['pickup_lat'] as num?)?.toDouble() ?? 0.0;
    final pickupLng = (widget.ride['pickup_lng'] as num?)?.toDouble() ?? 0.0;
    final dropoffLat = (widget.ride['dropoff_lat'] as num?)?.toDouble() ?? 0.0;
    final dropoffLng = (widget.ride['dropoff_lng'] as num?)?.toDouble() ?? 0.0;

    waypoints.add(
      PlaceEntity(
        coordinates: LatLngEntity(lat: pickupLat, lng: pickupLng),
        address: pickupAddress,
      ),
    );
    waypoints.add(
      PlaceEntity(
        coordinates: LatLngEntity(lat: dropoffLat, lng: dropoffLng),
        address: dropoffAddress,
      ),
    );

    // Duração máxima total para a barra de progresso (300s)
    final double progress = (_remainingSeconds / 300.0).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: widget.isSelected ? ColorPalette.primary50 : Colors.black.withOpacity(0.05),
            width: widget.isSelected ? 2.0 : 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(widget.isSelected ? 0.08 : 0.03),
              blurRadius: widget.isSelected ? 12 : 8,
              offset: const Offset(0, 3),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Topo do card: Serviço e Preço
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ColorPalette.primary95,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.ride['service_type']?.toString().toUpperCase() ?? 'STANDARD',
                    style: const TextStyle(
                      color: ColorPalette.primary40,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                Text(
                  fare.formatCurrency("BRL"),
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: ColorPalette.neutral20,
                  ),
                )
              ],
            ),
            const SizedBox(height: 12),

            // Waypoints da viagem
            WayPointsView(
              waypoints: waypoints,
            ),
            const Divider(height: 24, color: ColorPalette.neutral90),

            // Informações de distâncias
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Trajeto da Corrida',
                      style: TextStyle(
                        color: ColorPalette.neutral50,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatDistance(distance)} (${durationSeconds ~/ 60} min)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    )
                  ],
                ),
                if (widget.distanceToDriver != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Distância até Embarque',
                        style: TextStyle(
                          color: ColorPalette.neutral50,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatDistance(widget.distanceToDriver!),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFF10B981),
                        ),
                      )
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Cronômetro visual regressivo (contagem regressiva até expirar/sumir)
            Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: ColorPalette.neutral90,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _remainingSeconds <= 30
                              ? ColorPalette.error40
                              : ColorPalette.primary40,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_remainingSeconds}s',
                    style: TextStyle(
                      color: _remainingSeconds <= 30
                          ? ColorPalette.error40
                          : ColorPalette.neutral40,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Botão para Aceitar
            SizedBox(
              height: 44,
              child: AppPrimaryButton(
                onPressed: widget.accepting ? null : widget.onAccept,
                child: widget.isThisAccepting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'Aceitar Viagem',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
