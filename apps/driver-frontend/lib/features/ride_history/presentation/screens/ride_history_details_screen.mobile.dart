import 'package:flutter_common/core/blocs/settings.dart';
import 'package:uppi_motorista/core/presentation/app_generic_map.dart';
import 'package:uppi_motorista/features/ride_history/presentation/dialogs/report_issue_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/buttons/app_bordered_button.dart';
import 'package:generic_map/generic_map.dart';
import 'package:uppi_motorista/core/entities/order.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_top_bar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:ionicons/ionicons.dart';
import 'package:latlong2/latlong.dart';
import 'post_ride_chat_screen.dart';

import '../components/details_sheet.dart';

class RideHistoryDetailsScreenMobile extends StatefulWidget {
  final OrderEntity entity;

  const RideHistoryDetailsScreenMobile({super.key, required this.entity});

  @override
  State<RideHistoryDetailsScreenMobile> createState() => _RideHistoryDetailsScreenMobileState();
}

class _RideHistoryDetailsScreenMobileState extends State<RideHistoryDetailsScreenMobile> {
  bool _reopeningChat = false;

  List<PolyLineLayer> _routePolylines = [];

  @override
  void initState() {
    super.initState();
    _loadRouteGeometry();
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(
        lat / 1E5,
        lng / 1E5,
      ));
    }
    return points;
  }

  Future<void> _loadRouteGeometry() async {
    try {
      final wps = widget.entity.waypoints;
      if (wps.length < 2) return;

      List<LatLng> points = [];

      // 1. Tentar obter a polilinha de rota salva no banco de dados para a corrida atual
      try {
        final res = await Supabase.instance.client
            .from('rides')
            .select('route_polyline')
            .eq('id', widget.entity.id)
            .maybeSingle();
        if (res != null && res['route_polyline'] != null) {
          final polyList = res['route_polyline'] as List<dynamic>;
          if (polyList.isNotEmpty) {
            points = polyList
                .map((e) => LatLng(
                      (e['lat'] as num).toDouble(),
                      (e['lng'] as num).toDouble(),
                    ))
                .toList();
          }
        }
      } catch (e) {
        debugPrint('[Google-History-Mobile-Driver] Error loading route_polyline from DB: $e');
      }

      // 2. Tentar obter rotas da Google Directions API via Edge Function segura
      if (points.isEmpty) {
        try {
          final idToken = Supabase.instance.client.auth.currentSession?.accessToken;
          if (idToken != null) {
            final origin = '${wps[0].coordinates.lat},${wps[0].coordinates.lng}';
            final destination = '${wps[wps.length - 1].coordinates.lat},${wps[wps.length - 1].coordinates.lng}';
            final intermediates = wps.length > 2
                ? wps.sublist(1, wps.length - 1)
                    .map((w) => 'via:${w.coordinates.lat},${w.coordinates.lng}')
                    .join('|')
                : '';

            final response = await Supabase.instance.client.functions.invoke(
              'get-directions',
              body: {
                'origin': origin,
                'destination': destination,
                'waypoints': intermediates,
              },
            );

            if (response.status == 200 && response.data != null) {
              final data = response.data as Map<String, dynamic>;
              if (data['status'] == 'OK' && data['routes'] != null && (data['routes'] as List).isNotEmpty) {
                final route = data['routes'][0];
                final overviewPolyline = route['overview_polyline'];
                if (overviewPolyline != null && overviewPolyline['points'] != null) {
                  points = _decodePolyline(overviewPolyline['points'].toString());
                }
              }
            }
          }
        } catch (e) {
          debugPrint('[Google-History-Mobile-Driver] Exception: $e');
        }
      }

      // 3. Fallback para OSRM se o Google Maps falhar ou não retornar pontos
      if (points.isEmpty) {
        try {
          String osrmBaseUrl = 'https://router.project-osrm.org';
          try {
            final configRow = await Supabase.instance.client
                .from('app_settings')
                .select('value')
                .eq('key', 'osrm_routing_url')
                .maybeSingle();
            if (configRow != null && configRow['value'] != null && configRow['value'].toString().isNotEmpty) {
              osrmBaseUrl = configRow['value'].toString().replaceAll(RegExp(r'/$'), '');
            }
          } catch (_) {}

          final coords = wps.map((w) => '${w.coordinates.lng},${w.coordinates.lat}').join(';');
          final url = '$osrmBaseUrl/route/v1/driving/$coords?overview=full&geometries=geojson';
          final response = await http.get(
            Uri.parse(url),
            headers: {
              'User-Agent': 'UppiApp/1.0 (contact@uppi.com)'
            },
          ).timeout(const Duration(seconds: 6));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final routes = data['routes'] as List<dynamic>?;
            if (routes != null && routes.isNotEmpty) {
              final geometry = routes[0]['geometry']?['coordinates'] as List<dynamic>?;
              if (geometry != null && geometry.isNotEmpty) {
                points = geometry
                    .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
                    .toList();
              }
            }
          }
        } catch (e) {
          debugPrint('[OSRM-History-Mobile-Driver] Exception: $e');
        }
      }

      if (points.isNotEmpty && mounted) {
        setState(() {
          _routePolylines = [
            PolyLineLayer(
              points: points,
              width: 8,
              color: const Color(0xFF33CCFF),
              gradientColors: const [Color(0xFF33CCFF), Color(0xFF33CCFF)],
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
              borderStrokeWidth: 1.2,
              borderColor: const Color(0xFF0D5F7A),
            ),
          ];
        });
      } else if (mounted) {
        setState(() {
          _routePolylines = [
            wps.map((w) => w.coordinates).toList().toPolyLineLayer,
          ];
        });
      }
    } catch (_) {
      if (_routePolylines.isEmpty && mounted) {
        setState(() {
          _routePolylines = [
            widget.entity.waypoints.map((w) => w.coordinates).toList().toPolyLineLayer,
          ];
        });
      }
    }
  }

  Future<void> _handleReopenChat() async {
    setState(() => _reopeningChat = true);
    try {
      final idToken = Supabase.instance.client.auth.currentSession?.accessToken;
      if (idToken == null) throw Exception("Sessão inválida. Faça login novamente.");

      final response = await http.post(
        Uri.parse('${dotenv.env['SUPABASE_URL']}/functions/v1/reopen-ride-chat'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'ride_id': widget.entity.id,
        }),
      );

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body);
        throw Exception(body['message'] ?? body['error'] ?? 'Erro desconhecido');
      }

      if (mounted) {
        context.showSnackBar(message: 'Chat reaberto! Você pode falar com o passageiro.');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostRideChatScreen(
              rideId: widget.entity.id,
              riderName: widget.entity.riderFullName,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString().replaceAll('Exception: ', '');
        context.showSnackBar(
          message: errorMsg.contains('expirou') || errorMsg.contains('limite')
              ? errorMsg
              : 'Não foi possível reabrir o chat: $errorMsg',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _reopeningChat = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final finishAt = widget.entity.finishAt;
    final isWithin24Hours = finishAt != null && now.difference(finishAt).inHours < 24;

    return Container(
      color: context.theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTopBar(title: context.translate.rideDetails),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(
                      height: 250,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BlocBuilder<SettingsCubit, SettingsState>(
                          buildWhen: (previous, current) =>
                              previous.mapProvider != current.mapProvider,
                          builder: (context, settingsState) {
                            return AppGenericMap(
                              interactive: true,
                              mode: MapViewMode.static,
                              initialLocation:
                                  widget.entity.waypoints.first.toGenericMapPlace,
                              polylines: _routePolylines,
                              padding:
                                  settingsState.mapProvider ==
                                      MapProviderEnum.googleMaps
                                  ? EdgeInsets.zero
                                  : const EdgeInsets.symmetric(
                                      vertical: 80,
                                      horizontal: 150,
                                    ),
                              markers: widget.entity.waypoints.markers,
                              onControllerReady: (controller) {
                                controller.fitBounds(widget.entity.waypoints.latLngs);
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    RideHistoryDetailsSheet(entity: widget.entity),
                  ],
                ),
              ),
            ),
            if (isWithin24Hours) ...[
              SizedBox(
                width: double.infinity,
                child: AppBorderedButton(
                  isDisabled: _reopeningChat,
                  icon: Ionicons.chatbubble_ellipses,
                  onPressed: _handleReopenChat,
                  title: _reopeningChat
                      ? 'Abrindo chat...'
                      : 'Contatar Passageiro (Objeto Esquecido)',
                  isPrimary: true,
                  textColor: ColorPalette.primary30,
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: AppBorderedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    useSafeArea: false,
                    builder: (context) {
                      return ReportIssueFormDialog(orderId: widget.entity.id);
                    },
                  );
                },
                title: context.translate.reportAnIssue,
                isPrimary: true,
                textColor: ColorPalette.error40,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
