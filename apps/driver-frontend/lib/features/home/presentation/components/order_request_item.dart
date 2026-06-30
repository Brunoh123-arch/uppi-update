import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_common/core/entities/driver_location.dart';
import 'package:generic_map/generic_map.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/entities/order_request.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/features/home/presentation/blocs/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/blocs/settings.dart';
import 'package:flutter_common/core/enums/map_provider_enum.prod.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/enums/ride_option_icon.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/waypoints_view/waypoints_view.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/presentation/small_chip.dart';

class OrderRequestItem extends StatefulWidget {
  final OrderRequestEntity request;
  final DriverLocation? driverLocation;

  const OrderRequestItem({
    super.key,
    required this.request,
    this.driverLocation,
  });

  @override
  State<OrderRequestItem> createState() => _OrderRequestItemState();
}

class _OrderRequestItemState extends State<OrderRequestItem> {
  List<LatLng> _approachRoute = [];
  LatLng? _lastFetchedDriverLoc;

  // Contagem regressiva da oferta (expires_at do ride_offers): mostra quanto
  // tempo resta para aceitar e remove o card sozinho quando expira.
  Timer? _countdownTimer;
  Duration? _initialRemaining;
  Duration _remaining = Duration.zero;
  bool _expiredHandled = false;

  // Cache estático de chaves e URLs de configuração para evitar queries frequentes ao Supabase
  static String? _cachedGoogleApiKey;
  static String? _cachedOsrmUrl;

  @override
  void initState() {
    super.initState();
    _fetchApproachRoute();
    _startCountdown();
  }

  @override
  void didUpdateWidget(covariant OrderRequestItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Só recalcula a rota se a localização mudou e ainda não temos uma rota carregada
    if (_approachRoute.isEmpty && widget.driverLocation != oldWidget.driverLocation) {
      _fetchApproachRoute();
    }
    if (widget.request.id != oldWidget.request.id) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _expiredHandled = false;
    final expiresAt = widget.request.expiresAt;
    if (expiresAt == null) {
      _initialRemaining = null;
      return;
    }
    var left = expiresAt.difference(DateTime.now());
    if (left.isNegative) left = Duration.zero;
    _remaining = left;
    _initialRemaining = left;
    _countdownTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      var rem = expiresAt.difference(DateTime.now());
      if (rem.isNegative) rem = Duration.zero;
      setState(() => _remaining = rem);
      if (rem == Duration.zero && !_expiredHandled) {
        _expiredHandled = true;
        _countdownTimer?.cancel();
        // Reativa o envio de rejeição ativa para o servidor expirar a corrida no banco e limpar a tela localmente
        locator<HomeBloc>().add(
          HomeEvent.onRejectOrder(request: widget.request),
        );
        debugPrint('[OrderRequestItem] Corrida ${widget.request.id} expirada localmente. Enviando rejeicao ativa ao servidor.');
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchApproachRoute() async {
    final driverLoc = widget.driverLocation;
    if (driverLoc == null) return;
    
    final pickup = widget.request.waypoints.first.coordinates;
    final currentLoc = LatLng(driverLoc.lat, driverLoc.lng);
    
    // Evitar chamadas redundantes se o motorista não se moveu significativamente
    if (_lastFetchedDriverLoc != null &&
        (_lastFetchedDriverLoc!.latitude - currentLoc.latitude).abs() < 0.0001 &&
        (_lastFetchedDriverLoc!.longitude - currentLoc.longitude).abs() < 0.0001) {
      return;
    }
    
    _lastFetchedDriverLoc = currentLoc;
    
    try {
      bool success = false;
      List<LatLng> routePoints = [];

      // Extrai a polyline da resposta da Google Directions API (proxy ou direta).
      bool parseGoogleDirections(dynamic data) {
        if (data is! Map) return false;
        if (data['status'] != 'OK' || data['routes'] == null || (data['routes'] as List).isEmpty) {
          return false;
        }
        final route = data['routes'][0];
        final overviewPolyline = route['overview_polyline'];
        if (overviewPolyline != null && overviewPolyline['points'] != null) {
          routePoints = _decodePolyline(overviewPolyline['points'].toString());
          return routePoints.isNotEmpty;
        }
        return false;
      }

      final mapProvider = locator<SettingsCubit>().state.mapProviderEnum;

      if (mapProvider == MapProviderEnum.googleMaps) {
        // 1ª opção: Edge Function get-directions (chave fica no servidor).
        try {
          final res = await Supabase.instance.client.functions.invoke(
            'get-directions',
            body: {
              'origin': '${currentLoc.latitude},${currentLoc.longitude}',
              'destination': '${pickup.lat},${pickup.lng}',
            },
          ).timeout(const Duration(seconds: 5));
          success = parseGoogleDirections(res.data);
        } catch (_) {}

        // 2ª opção (transitória): chamada direta com a chave do app_settings,
        // até a Edge Function estar publicada para todos os clientes.
        if (!success) {
          String googleApiKey = _cachedGoogleApiKey ?? '';
          if (googleApiKey.isEmpty) {
            try {
              // 1. Tentar obter a chave da coluna google_map_api_key no registro global_config (formato novo)
              final configRow = await Supabase.instance.client
                  .from('app_settings')
                  .select('google_map_api_key')
                  .eq('key', 'global_config')
                  .maybeSingle();
              if (configRow != null && configRow['google_map_api_key'] != null) {
                googleApiKey = configRow['google_map_api_key'].toString();
                _cachedGoogleApiKey = googleApiKey;
              }
            } catch (_) {}
          }

          if (googleApiKey.isEmpty) {
            try {
              // 2. Fallback: tentar obter do formato antigo (chave-valor)
              final configRow = await Supabase.instance.client
                  .from('app_settings')
                  .select('value')
                  .eq('key', 'google_map_api_key')
                  .maybeSingle();
              if (configRow != null && configRow['value'] != null) {
                googleApiKey = configRow['value'].toString();
                _cachedGoogleApiKey = googleApiKey;
              }
            } catch (_) {}
          }

          if (googleApiKey.isNotEmpty) {
            try {
              final url = 'https://maps.googleapis.com/maps/api/directions/json?origin=${currentLoc.latitude},${currentLoc.longitude}&destination=${pickup.lat},${pickup.lng}&key=$googleApiKey';
              // Não logar a URL completa: ela contém a chave da API.
              debugPrint('[Google-Driver-Req] Requesting approach route (origin=${currentLoc.latitude},${currentLoc.longitude})');
              final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
              if (response.statusCode == 200) {
                success = parseGoogleDirections(json.decode(response.body));
              }
            } catch (_) {}
          }
        }
      } else {
        // OSRM
        debugPrint('[OSRM-Driver-Req] Requesting OSRM approach route');
        String osrmBaseUrl = _cachedOsrmUrl ?? 'https://router.project-osrm.org';
        if (_cachedOsrmUrl == null) {
          try {
            final configRow = await Supabase.instance.client
                .from('app_settings')
                .select('value')
                .eq('key', 'osrm_routing_url')
                .maybeSingle();
            if (configRow != null && configRow['value'] != null && configRow['value'].toString().isNotEmpty) {
              osrmBaseUrl = configRow['value'].toString().replaceAll(RegExp(r'/$'), '');
              _cachedOsrmUrl = osrmBaseUrl;
            }
          } catch (_) {}
        }

        final coordinates = '${driverLoc.lng},${driverLoc.lat};${pickup.lng},${pickup.lat}';
        final url = Uri.parse('$osrmBaseUrl/route/v1/driving/$coordinates?overview=full&geometries=geojson');
        
        try {
          final response = await http.get(
            url,
            headers: {'User-Agent': 'UppiDriverApp/3.2.8'},
          ).timeout(const Duration(seconds: 5));
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            final routes = data['routes'] as List?;
            if (routes != null && routes.isNotEmpty) {
              final geometry = routes.first['geometry'];
              final coordinatesList = geometry['coordinates'] as List?;
              if (coordinatesList != null) {
                routePoints = coordinatesList.map((c) {
                  final lng = (c[0] as num).toDouble();
                  final lat = (c[1] as num).toDouble();
                  return LatLng(lat, lng);
                }).toList();
                success = true;
              }
            }
          }
        } catch (_) {}
      }

      if (success && mounted) {
        setState(() {
          _approachRoute = routePoints;
        });
      }
    } catch (e) {
      debugPrint('[OrderRequestItem] Erro ao buscar rota de aproximação: $e');
    }
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

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371000;
    final double dLat = (lat2 - lat1) * math.pi / 180.0;
    final double dLon = (lon2 - lon1) * math.pi / 180.0;
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('UPPI BRASIL - OrderRequestItem waypoints: ${widget.request.waypoints.map((e) => "${e.title} -> ${e.address}").toList()}');
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white, // iOS-style original light background
        border: Border.all(
          color: Colors.black.withOpacity(0.06),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.request.isDangerZone)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [ColorPalette.error50, ColorPalette.error30],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: ColorPalette.error40.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Ionicons.warning,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "ÁREA DE RISCO MAPEADA! Destino: ${widget.request.dangerZoneName ?? 'Zona de Risco'}",
                      style: context.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ) ?? const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.request.serviceName.isNotEmpty
                            ? (widget.request.serviceName[0].toUpperCase() +
                                widget.request.serviceName.substring(1))
                            : "",
                        style: context.titleMedium?.copyWith(
                          color: ColorPalette.neutral20,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                      Text(
                        widget.request.paymentMethod.map(
                          paymentGateway: (_) => "Pagamento Online",
                          savedPaymentMethod: (_) => "Pago pelo App",
                          cash: (_) => "Dinheiro",
                          wallet: (_) => "Carteira Virtual",
                        ),
                        style: context.bodyMedium?.copyWith(
                          color: ColorPalette.neutralVariant40,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  widget.request.fee.formatCurrency(widget.request.currency),
                  style: context.titleLarge?.copyWith(
                    color: ColorPalette.neutral20,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
              color: ColorPalette.neutralVariant99, // iOS light background secondary
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (widget.driverLocation != null)
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SmallChip(
                              text: 'Embarque: ${_formatDistance(_calculateDistance(widget.driverLocation!.lat, widget.driverLocation!.lng, widget.request.waypoints.first.coordinates.lat, widget.request.waypoints.first.coordinates.lng))}',
                              icon: const Icon(Ionicons.car_sport, color: Color(0xFF10B981), size: 14),
                            ),
                          ),
                        ),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SmallChip(
                            text: 'Distância: ${widget.request.distance.toFormattedDistance(context)}',
                            icon: const Icon(Ionicons.map, color: Color(0xFF3B82F6), size: 14),
                          ),
                        ),
                      ),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SmallChip(
                            text: 'Tempo: ${context.translate.durationInMinutes(widget.request.duration ~/ 60)}',
                            icon: const Icon(Ionicons.time, color: Colors.orangeAccent, size: 14),
                          ),
                        ),
                      )
                    ],
                  ),
                  const Divider(
                    height: 12,
                    color: ColorPalette.neutral90,
                  ),
                  SizedBox(
                    height: 130,
                    child: SingleChildScrollView(
                      child: WayPointsView(
                        waypoints: widget.request.waypoints,
                      ),
                    ),
                  ),
                  if (widget.request.rideOptions.isNotEmpty) ...[
                    const Divider(
                      height: 12,
                      color: ColorPalette.neutral90,
                    ),
                    Row(
                      children: [
                        Text(
                          context.translate.preferences,
                          style: context.bodyMedium?.copyWith(color: ColorPalette.neutral30),
                        ),
                        Expanded(
                            child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            for (final preference in widget.request.rideOptions)
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.black.withOpacity(0.06),
                                  ),
                                  color: Colors.black.withOpacity(0.02),
                                ),
                                child: Icon(
                                  preference.icon.icon,
                                  color: ColorPalette.primary30,
                                  size: 16,
                                ),
                              )
                          ],
                        ))
                      ],
                    ),
                  ],
                  const SizedBox(
                    height: 12,
                  ),
                  // Tempo restante da oferta (expira sozinha no servidor)
                  if (_initialRemaining != null && _initialRemaining!.inMilliseconds > 0) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: (_remaining.inMilliseconds /
                                        _initialRemaining!.inMilliseconds)
                                    .clamp(0.0, 1.0),
                                minHeight: 6,
                                backgroundColor: ColorPalette.neutral90,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _remaining.inSeconds <= 5
                                      ? ColorPalette.error40
                                      : ColorPalette.primary40,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_remaining.inSeconds}s',
                            style: context.labelMedium?.copyWith(
                              color: _remaining.inSeconds <= 5
                                  ? ColorPalette.error40
                                  : ColorPalette.neutral40,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Row(
                    children: [
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ColorPalette.neutral40,
                            side: const BorderSide(color: ColorPalette.neutral90),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          onPressed: () {
                            locator<HomeBloc>().add(
                              HomeEvent.onRejectOrder(request: widget.request),
                            );
                          },
                          child: Text(context.translate.decline),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: AppPrimaryButton(
                            onPressed: () {
                              locator<HomeBloc>().onAcceptOrder(widget.request);
                            },
                            child: Text(
                              context.translate.acceptOrder,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
