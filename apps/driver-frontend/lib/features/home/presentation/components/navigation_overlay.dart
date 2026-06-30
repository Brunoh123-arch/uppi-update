import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'dart:ui';
import 'package:uppi_motorista/core/utils/driver_speed.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:flutter_common/core/blocs/connectivity_cubit.dart';

import 'package:flutter_common/core/entities/driver_location.dart';
import 'package:flutter_common/core/enums/order_status.dart';
import 'package:uppi_motorista/features/home/presentation/blocs/home.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter_common/core/blocs/settings.dart';
import 'package:flutter_common/core/enums/map_provider_enum.prod.dart';

class RouteStep {
  final double distance; // em metros
  final double duration; // em segundos
  final String name;
  final String maneuverType;
  final String modifier;
  final LatLng location;
  final String instruction;
  final bool isGoogle;

  RouteStep({
    required this.distance,
    required this.duration,
    required this.name,
    required this.maneuverType,
    required this.modifier,
    required this.location,
    required this.instruction,
    this.isGoogle = false,
  });

  factory RouteStep.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString() ?? '';
    final distance = (json['distance'] as num?)?.toDouble() ?? 0.0;
    final duration = (json['duration'] as num?)?.toDouble() ?? 0.0;
    
    final maneuver = json['maneuver'] as Map<String, dynamic>? ?? {};
    final type = maneuver['type']?.toString() ?? 'turn';
    final modifier = maneuver['modifier']?.toString() ?? 'straight';
    
    final locList = maneuver['location'] as List? ?? [0.0, 0.0];
    final location = LatLng(
      (locList[1] as num).toDouble(),
      (locList[0] as num).toDouble(),
    );

    final rawInstruction = maneuver['instruction']?.toString() ?? '';

    return RouteStep(
      distance: distance,
      duration: duration,
      name: name,
      maneuverType: type,
      modifier: modifier,
      location: location,
      instruction: rawInstruction,
    );
  }

  factory RouteStep.fromGoogleJson(Map<String, dynamic> json) {
    final distance = (json['distance']['value'] as num?)?.toDouble() ?? 0.0;
    final duration = (json['duration']['value'] as num?)?.toDouble() ?? 0.0;
    
    final googleManeuver = json['maneuver']?.toString() ?? 'turn';
    String type = 'turn';
    String modifier = 'straight';
    
    if (googleManeuver.contains('left')) {
      modifier = 'left';
    } else if (googleManeuver.contains('right')) {
      modifier = 'right';
    } else if (googleManeuver.contains('uturn')) {
      modifier = 'uturn';
    } else if (googleManeuver.contains('straight')) {
      modifier = 'straight';
    }

    if (googleManeuver.startsWith('roundabout')) {
      type = 'roundabout';
    } else if (googleManeuver.startsWith('merge')) {
      type = 'merge';
    } else if (googleManeuver.startsWith('ramp')) {
      type = 'ramp';
    } else if (googleManeuver.startsWith('fork')) {
      type = 'fork';
    }

    final startLoc = json['start_location'] as Map<String, dynamic>? ?? {};
    final location = LatLng(
      (startLoc['lat'] as num?)?.toDouble() ?? 0.0,
      (startLoc['lng'] as num?)?.toDouble() ?? 0.0,
    );

    final rawInstruction = json['html_instructions']?.toString() ?? '';
    final cleanInstruction = rawInstruction.replaceAll(RegExp(r'<[^>]*>'), '');

    // O Google não manda o nome da via num campo próprio, mas ele vem em
    // <b>...</b> dentro da instrução ("Vire à direita na <b>Av. X</b>").
    // Usamos o último trecho em negrito como nome da via do passo — alimenta
    // a pílula de "rua atual" e a estimativa de limite de velocidade.
    String roadName = '';
    final boldMatches = RegExp(r'<b>(.*?)</b>').allMatches(rawInstruction);
    if (boldMatches.isNotEmpty) {
      roadName = (boldMatches.last.group(1) ?? '')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .trim();
    }

    return RouteStep(
      distance: distance,
      duration: duration,
      name: roadName,
      maneuverType: type,
      modifier: modifier,
      location: location,
      instruction: cleanInstruction,
      isGoogle: true,
    );
  }

  String getInstruction(BuildContext context) {
    // When step comes from Google Directions, preserve the original instruction
    // text instead of replacing it with generic translations.
    if (isGoogle && instruction.isNotEmpty) {
      return instruction;
    }
    final streetName = name.isEmpty || name == 'null' ? context.translate.navStreetDefault : name;
    switch (maneuverType) {
      case 'depart':
        return context.translate.navDepart(streetName);
      case 'arrive':
        return context.translate.navArrive;
      case 'merge':
        return context.translate.navMerge(streetName);
      case 'ramp':
        return context.translate.navRamp(streetName);
      case 'roundabout':
        return context.translate.navRoundabout(streetName);
      case 'fork':
        return context.translate.navFork(streetName);
      case 'turn':
        switch (modifier) {
          case 'left':
            return context.translate.navTurnLeft(streetName);
          case 'right':
            return context.translate.navTurnRight(streetName);
          case 'sharp left':
            return context.translate.navTurnSharpLeft(streetName);
          case 'sharp right':
            return context.translate.navTurnSharpRight(streetName);
          case 'slight left':
            return context.translate.navTurnSlightLeft(streetName);
          case 'slight right':
            return context.translate.navTurnSlightRight(streetName);
          case 'straight':
            return context.translate.navTurnStraight(streetName);
          case 'uturn':
            return context.translate.navTurnUturn(streetName);
          default:
            return context.translate.navTurnDefault(streetName);
        }
      case 'new name':
        return context.translate.navNewName(streetName);
      default:
        return instruction.isNotEmpty ? instruction : context.translate.navDefault;
    }
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

class HomeNavigationOverlay extends StatefulWidget {
  final DriverLocation? driverLocation;
  final OnTripDriverStatus onTripStatus;

  static final ValueNotifier<List<LatLng>> activeRouteNotifier = ValueNotifier<List<LatLng>>([]);

  /// Liga/desliga a voz das instruções (botão de mudo). Global para persistir
  /// entre reconstruções do overlay.
  static final ValueNotifier<bool> voiceEnabledNotifier = ValueNotifier<bool>(true);

  /// Distância e duração restantes para o destino em tempo real (em metros e segundos)
  static final ValueNotifier<double> remainingDistanceNotifier = ValueNotifier<double>(0.0);
  static final ValueNotifier<double> remainingDurationNotifier = ValueNotifier<double>(0.0);

  /// Próxima manobra de curva/direção ativa para exibir no mapa
  static final ValueNotifier<RouteStep?> nextManeuverNotifier = ValueNotifier<RouteStep?>(null);

  /// Distância restante até a próxima manobra (metros).
  static final ValueNotifier<double> distanceToNextManeuverNotifier = ValueNotifier<double>(0.0);

  /// Limite de velocidade em tempo real da via atual.
  /// [double.infinity] = limite desconhecido (nunca alertar com base em chute).
  static final ValueNotifier<double> speedLimitNotifier = ValueNotifier<double>(double.infinity);

  /// Nome da via em que o motorista está agora (pílula azul estilo Google
  /// Maps na parte de baixo do mapa). Vazio quando desconhecido.
  static final ValueNotifier<String> currentRoadNotifier = ValueNotifier<String>('');

  /// Índice atual do motorista na polilinha da rota
  static final ValueNotifier<int> driverIdxNotifier = ValueNotifier<int>(0);

  /// Índice da próxima manobra na polilinha da rota
  static final ValueNotifier<int> nextManeuverIdxNotifier = ValueNotifier<int>(0);

  const HomeNavigationOverlay({
    super.key,
    required this.driverLocation,
    required this.onTripStatus,
  });

  static IconData getManeuverIcon(String type, String modifier) {
    if (type == 'arrive') {
      return Icons.flag_rounded;
    }
    if (type == 'depart') {
      return Icons.navigation_rounded;
    }
    if (type == 'roundabout') {
      return Icons.roundabout_right_rounded;
    }
    if (type == 'fork') {
      return modifier.contains('left') ? Icons.fork_left_rounded : Icons.fork_right_rounded;
    }
    if (type == 'merge') {
      return Icons.merge_rounded;
    }
    if (type == 'ramp') {
      return modifier.contains('left') ? Icons.ramp_left_rounded : Icons.ramp_right_rounded;
    }

    switch (modifier) {
      case 'left':
        return Icons.turn_left_rounded;
      case 'right':
        return Icons.turn_right_rounded;
      case 'sharp left':
        return Icons.turn_sharp_left_rounded;
      case 'sharp right':
        return Icons.turn_sharp_right_rounded;
      case 'slight left':
        return Icons.turn_slight_left_rounded;
      case 'slight right':
        return Icons.turn_slight_right_rounded;
      case 'uturn':
        return Icons.u_turn_left_rounded;
      case 'straight':
      default:
        return Icons.arrow_upward_rounded; // Bolder and identical to Google Maps straight arrow
    }
  }

  @override
  State<HomeNavigationOverlay> createState() => _HomeNavigationOverlayState();
}

class _HomeNavigationOverlayState extends State<HomeNavigationOverlay> {
  List<RouteStep> _steps = [];
  int _currentStepIndex = 0;
  bool _isLoading = false;
  bool _isRecalculating = false;
  String? _loadedRideId;
  int? _loadedWaypointIndex;
  OrderStatus? _loadedStatus;

  String? _loadingRideId;
  int? _loadingWaypointIndex;
  OrderStatus? _loadingStatus;
  
  double _distanceToNextManeuver = 0.0;

  // Voz de navegação (TTS).
  FlutterTts? _tts;
  bool _ttsReady = false;
  // Guarda quais avisos já foram falados (chave por passo+fase) para não repetir.
  final Set<String> _spoken = {};
  
  // Anti-spam throttling do recálculo
  DateTime? _lastRecalculateTime;

  // Chave de persistência do mudo (lembra a escolha entre sessões).
  static const String _voicePrefKey = 'nav_voice_enabled';

  // Índice da rota para map-matching ("grudar na rua"):
  // geometria completa, comprimento acumulado por ponto, comprimento total
  // e a distância (ao longo da rota) de cada manobra.
  List<LatLng> _routeGeom = [];
  List<double> _cumLen = [];
  double _routeLength = 0.0;
  List<double> _stepsAlong = [];
  List<int> _stepsIndices = [];

  // Última distância acumulada (along) onde o motorista foi "grudado" na rota.
  // Usada como âncora de continuidade do map-matching: sem ela, em rotas que
  // passam duas vezes perto do mesmo lugar (retorno, ida e volta na mesma via)
  // o snap pula para o trecho errado.
  double? _lastMatchAlong;

  // Variáveis para tratamento de erros offline e anti-spam de fala
  bool _isOfflineError = false;
  // A última falha foi por falta de internet (true) ou erro de rota (false)?
  bool _failureWasOffline = false;
  Timer? _reconnectTimer;
  String? _lastSpokenText;
  DateTime? _lastSpokenTime;
  DateTime? _lastSpeakRecalculateTime;
  DateTime? _lastSpeedAlertTime;
  DateTime? _lastRouteLoadedTime;

  @override
  void initState() {
    super.initState();
    _restoreVoicePref();
    _initTts();
    _fetchStepsIfNeeded();
  }

  /// Restaura a preferência de voz (ligada/mudo) salva entre sessões.
  void _restoreVoicePref() {
    try {
      final v = HydratedBloc.storage.read(_voicePrefKey);
      if (v is bool) HomeNavigationOverlay.voiceEnabledNotifier.value = v;
    } catch (_) {}
  }

  @override
  void dispose() {
    HomeNavigationOverlay.activeRouteNotifier.value = [];
    HomeNavigationOverlay.remainingDistanceNotifier.value = 0.0;
    HomeNavigationOverlay.remainingDurationNotifier.value = 0.0;
    HomeNavigationOverlay.nextManeuverNotifier.value = null;
    HomeNavigationOverlay.distanceToNextManeuverNotifier.value = 0.0;
    HomeNavigationOverlay.currentRoadNotifier.value = '';
    HomeNavigationOverlay.driverIdxNotifier.value = 0;
    HomeNavigationOverlay.nextManeuverIdxNotifier.value = 0;
    _reconnectTimer?.cancel();
    _tts?.stop();
    super.dispose();
  }

  Future<void> _initTts() async {
    try {
      final tts = FlutterTts();
      // Seleciona o motor Google TTS explicitamente no Android para melhor
      // qualidade de voz em português.
      if (Platform.isAndroid) {
        await tts.setEngine('com.google.android.tts');
      }
      await tts.setLanguage('pt-BR');
      await tts.setSpeechRate(0.5); // ritmo claro
      await tts.setVolume(1.0);
      // Voz feminina pt-BR (igual Google Maps). Tentamos selecionar uma voz
      // feminina explicitamente; se o aparelho não expuser, o tom (pitch) um
      // pouco mais alto reforça a percepção feminina como fallback.
      await _applyFemaleVoice(tts);
      await tts.setPitch(1.1);
      _tts = tts;
      _ttsReady = true;
    } catch (e) {
      debugPrint('[NavVoice] Falha ao iniciar TTS: $e');
    }
  }

  /// Procura e fixa uma voz feminina em português no motor TTS do aparelho.
  /// É tolerante a falhas: se a lista de vozes não estiver disponível, mantém
  /// o idioma pt-BR já configurado.
  Future<void> _applyFemaleVoice(FlutterTts tts) async {
    try {
      final dynamic raw = await tts.getVoices;
      if (raw is! List) return;

      final ptVoices = <Map<String, dynamic>>[];
      for (final v in raw) {
        if (v is Map) {
          final m = Map<String, dynamic>.from(v);
          final locale = (m['locale'] ?? '').toString().toLowerCase();
          if (locale.startsWith('pt')) ptVoices.add(m);
        }
      }
      if (ptVoices.isEmpty) return;

      // 1ª escolha: alguma voz marcada/nomeada como feminina.
      Map<String, dynamic>? chosen;
      for (final v in ptVoices) {
        final name = (v['name'] ?? '').toString().toLowerCase();
        final gender = (v['gender'] ?? '').toString().toLowerCase();
        if (gender.contains('female') ||
            name.contains('female') ||
            name.contains('woman') ||
            name.contains('#female') ||
            name.contains('-afs')) {
          chosen = v;
          break;
        }
      }

      // Fallback: prioriza pt-BR (sobre pt-PT) se nada vier marcado.
      chosen ??= ptVoices.firstWhere(
        (v) => (v['locale'] ?? '').toString().toLowerCase() == 'pt-br',
        orElse: () => ptVoices.first,
      );

      await tts.setVoice({
        'name': (chosen['name'] ?? '').toString(),
        'locale': (chosen['locale'] ?? 'pt-BR').toString(),
      });
    } catch (_) {
      // Mantém pt-BR padrão como fallback seguro.
    }
  }

  /// Fala um texto (se a voz estiver ligada). Interrompe a fala anterior.
  /// Evita repetir a mesma instrução se dita em menos de 15 segundos (anti-spam de recálculo).
  /// Antes de falar, expande abreviações comuns de logradouro para o TTS
  /// pronunciar corretamente.
  Future<void> _speak(String text) async {
    if (!_ttsReady || _tts == null) return;
    if (!HomeNavigationOverlay.voiceEnabledNotifier.value) return;

    final now = DateTime.now();
    if (_lastSpokenText == text && _lastSpokenTime != null && now.difference(_lastSpokenTime!) < const Duration(seconds: 15)) {
      debugPrint('[NavVoice] Ignorando fala repetida em menos de 15s: "$text"');
      return;
    }
    _lastSpokenText = text;
    _lastSpokenTime = now;

    // Expande abreviações de logradouro para pronúncia natural no TTS.
    final abbreviations = {
      r'\bav\b\.?': 'Avenida',
      r'\br\b\.?': 'Rua',
      r'\btrav\b\.?': 'Travessa',
      r'\brod\b\.?': 'Rodovia',
      r'\bpç\b\.?': 'Praça',
      r'\bal\b\.?': 'Alameda',
      r'\best\b\.?': 'Estrada',
      r'\bbr\b\.?': 'BR',
    };
    String spokenText = text;
    for (final entry in abbreviations.entries) {
      spokenText = spokenText.replaceAll(
        RegExp(entry.key, caseSensitive: false),
        entry.value,
      );
    }

    try {
      await _tts!.stop();
      await _tts!.speak(spokenText);
    } catch (_) {}
  }

  /// Converte distância em metros para texto falado natural em português.
  /// Exemplos: "50 metros", "200 metros", "1 quilômetro", "2 quilômetros e meio".
  String _formatSpokenDistance(double meters) {
    if (meters < 100) {
      final rounded = (meters / 10).round() * 10;
      return '$rounded metros';
    } else if (meters < 1000) {
      final rounded = (meters / 50).round() * 50;
      return '$rounded metros';
    } else {
      final km = meters / 1000;
      if ((km - km.round()).abs() < 0.1) {
        return '${km.round()} quilômetro${km.round() > 1 ? 's' : ''}';
      } else if ((km * 2 - (km * 2).round()).abs() < 0.2) {
        final half = km.round();
        return '$half quilômetro${half > 1 ? 's' : ''} e meio';
      } else {
        final wholeKm = km.floor();
        final remainMeters = ((meters - wholeKm * 1000) / 100).round() * 100;
        if (remainMeters > 0) {
          return '$wholeKm quilômetro${wholeKm > 1 ? 's' : ''} e $remainMeters metros';
        }
        return '$wholeKm quilômetro${wholeKm > 1 ? 's' : ''}';
      }
    }
  }

  /// Decide se deve anunciar a manobra atual por voz, com base na distância.
  /// Fala uma vez aos ~300 m ("Em 250 metros, vire à direita") e uma vez
  /// ao se aproximar (~80 m, só a instrução). Anuncia chegada ao destino.
  void _maybeAnnounce() {
    if (!mounted || _steps.isEmpty) return;
    if (!HomeNavigationOverlay.voiceEnabledNotifier.value) return;

    final idx = _currentStepIndex;
    final step = _steps[idx];
    final d = _distanceToNextManeuver;
    final instruction = step.getInstruction(context);

    if (step.maneuverType == 'arrive') {
      if (d <= 40 && _spoken.add('arrive')) {
        _speak(context.translate.navArrive);
      }
      return;
    }

    // Aproximação (~300 m)
    if (d <= 300 && d > 90 && _spoken.add('a$idx')) {
      // Prefixo "Em X metros" só em pt; em outros idiomas evita misturar
      // (a instrução já vem traduzida).
      final isPt = Localizations.localeOf(context).languageCode == 'pt';
      _speak(isPt ? 'Em ${_formatSpokenDistance(d)}, $instruction' : instruction);
      return;
    }

    // Iminente (~90 m): só a instrução
    if (d <= 90 && _spoken.add('n$idx')) {
      _speak(instruction);
    }
  }

  void _maybeAnnounceSpeedLimit(double limit) {
    if (!limit.isFinite) return; // limite desconhecido → sem alerta
    if (!mounted || !HomeNavigationOverlay.voiceEnabledNotifier.value) return;
    final kmh = DriverSpeed.kmh.value;
    if (kmh > limit) {
      final now = DateTime.now();
      if (_lastSpeedAlertTime == null || now.difference(_lastSpeedAlertTime!) >= const Duration(seconds: 120)) {
        _lastSpeedAlertTime = now;
        _speak("Atenção: limite de velocidade excedido");
      }
    }
  }

  void _speakRecalculating() {
    if (!mounted || !HomeNavigationOverlay.voiceEnabledNotifier.value) return;
    final now = DateTime.now();
    if (_lastSpeakRecalculateTime == null || now.difference(_lastSpeakRecalculateTime!) >= const Duration(seconds: 60)) {
      _lastSpeakRecalculateTime = now;
      _speak("Recalculando rota");
    }
  }

  /// Atualiza o notifier global da próxima manobra para que o mapa desenhe
  /// o balãozinho azul de indicação de manobra exatamente sobre a coordenada da curva.
  void _updateNextManeuverNotifier() {
    if (_steps.isNotEmpty && _currentStepIndex < _steps.length) {
      final step = _steps[_currentStepIndex];
      // Mostra apenas curvas/rotatórias relevantes, não o ponto de partida ou chegada inicial
      if (step.maneuverType != 'depart') {
        HomeNavigationOverlay.nextManeuverNotifier.value = step;
        return;
      }
    }
    HomeNavigationOverlay.nextManeuverNotifier.value = null;
  }

  @override
  void didUpdateWidget(covariant HomeNavigationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Se a corrida ou o waypoint ativo mudaram, buscar novas instruções
    final currentOrder = widget.onTripStatus.order;
    
    if (_loadedRideId != currentOrder.id || 
        _loadedWaypointIndex != currentOrder.destinationArrivedTo ||
        _loadedStatus != currentOrder.status) {
      _fetchStepsIfNeeded();
    } else if (widget.driverLocation != null) {
      if (_steps.isNotEmpty) {
        _processLocationUpdate();
      } else if (!_isLoading && !_isRecalculating) {
        // Se a rota falhou anteriormente (ficou vazia), tenta buscar novamente com cooldown
        final now = DateTime.now();
        if (_lastRecalculateTime == null || now.difference(_lastRecalculateTime!) >= const Duration(seconds: 15)) {
          _lastRecalculateTime = now;
          debugPrint('[Navigation] Retrying to fetch route since steps list is empty.');
          _fetchStepsIfNeeded();
        }
      }
    }
  }

  Future<void> _fetchStepsIfNeeded() async {
    final order = widget.onTripStatus.order;
    final waypoints = order.waypoints;
    final driverLoc = widget.driverLocation;
    
    if (waypoints.isEmpty) return;

    if (_isLoading && 
        _loadingRideId == order.id && 
        _loadingWaypointIndex == order.destinationArrivedTo && 
        _loadingStatus == order.status) {
      debugPrint('[Navigation] Already loading route for ride: ${order.id}, status: ${order.status}');
      return;
    }

    final isRerouting = _loadedRideId == order.id && 
        _loadedWaypointIndex == order.destinationArrivedTo && 
        _loadedStatus == order.status;

    setState(() {
      _isLoading = true;
      _loadingRideId = order.id;
      _loadingWaypointIndex = order.destinationArrivedTo;
      _loadingStatus = order.status;
      if (!isRerouting) {
        _steps = [];
        _currentStepIndex = 0;
      }
    });

    if (!isRerouting) {
      HomeNavigationOverlay.activeRouteNotifier.value = [];
      HomeNavigationOverlay.remainingDistanceNotifier.value = 0.0;
      HomeNavigationOverlay.remainingDurationNotifier.value = 0.0;
      HomeNavigationOverlay.nextManeuverNotifier.value = null;
      HomeNavigationOverlay.driverIdxNotifier.value = 0;
      HomeNavigationOverlay.nextManeuverIdxNotifier.value = 0;
    }

    try {
      final List<LatLng> coordsList = [];
      
      // Adicionar ponto inicial (driver current location ou primeiro waypoint)
      if (driverLoc != null) {
        coordsList.add(LatLng(driverLoc.lat, driverLoc.lng));
      } else {
        coordsList.add(LatLng(waypoints.first.coordinates.lat, waypoints.first.coordinates.lng));
      }

      // Adicionar destinos seguintes
      if (order.status == OrderStatus.driverAccepted || order.status == OrderStatus.arrived) {
        // Rota para o pickup (primeiro waypoint)
        coordsList.add(LatLng(waypoints.first.coordinates.lat, waypoints.first.coordinates.lng));
      } else if (order.status == OrderStatus.started) {
        // Rota para o próximo destino intermediário/final (suporta multi-stops)
        // Se destinationArrivedTo for null, a próxima parada é a primeira de destino (índice 1 dos waypoints)
        final index = order.destinationArrivedTo != null
            ? order.destinationArrivedTo! + 2
            : 1;
        if (index >= 0 && index < waypoints.length) {
          coordsList.add(LatLng(waypoints[index].coordinates.lat, waypoints[index].coordinates.lng));
        } else {
          coordsList.add(LatLng(waypoints.last.coordinates.lat, waypoints.last.coordinates.lng));
        }
      } else {
        coordsList.add(LatLng(waypoints.last.coordinates.lat, waypoints.last.coordinates.lng));
      }

      bool success = false;
      List<RouteStep> parsedSteps = [];
      List<LatLng> routePoints = [];

      // Interpreta a resposta da Google Directions API (proxy ou direta).
      bool parseGoogleDirections(dynamic directionsData) {
        parsedSteps = [];
        routePoints = [];
        if (directionsData is! Map) return false;
        if (directionsData['status'] != 'OK' ||
            directionsData['routes'] == null ||
            (directionsData['routes'] as List).isEmpty) {
          return false;
        }
        final route = directionsData['routes'][0];
        final legs = route['legs'] as List? ?? [];
        for (var leg in legs) {
          final legSteps = leg['steps'] as List? ?? [];
          for (var step in legSteps) {
            parsedSteps.add(RouteStep.fromGoogleJson(step));
          }
        }
        final overviewPolyline = route['overview_polyline'];
        if (overviewPolyline != null && overviewPolyline['points'] != null) {
          routePoints = _decodePolyline(overviewPolyline['points'].toString());
        }
        return parsedSteps.isNotEmpty && routePoints.isNotEmpty;
      }

      final origin = '${coordsList.first.latitude},${coordsList.first.longitude}';
      final destination = '${coordsList.last.latitude},${coordsList.last.longitude}';
      String? intermediates;
      if (coordsList.length > 2) {
        intermediates = coordsList.sublist(1, coordsList.length - 1)
            .map((w) => 'via:${w.latitude},${w.longitude}')
            .join('|');
      }

      final mapProvider = locator<SettingsCubit>().state.mapProviderEnum;

      if (mapProvider == MapProviderEnum.googleMaps) {
        // 1ª opção: Edge Function get-directions — a chave do Google fica no
        // servidor, nunca no aparelho.
        try {
          final res = await Supabase.instance.client.functions.invoke(
            'get-directions',
            body: {
              'origin': origin,
              'destination': destination,
              if (intermediates != null) 'waypoints': intermediates,
            },
          ).timeout(const Duration(seconds: 6));
          success = parseGoogleDirections(res.data);
          if (success) {
            debugPrint('[Directions-Proxy] Rota via Edge Function (${parsedSteps.length} passos)');
          }
        } catch (e) {
          debugPrint('[Directions-Proxy] Falhou (${e.runtimeType}), tentando chamada direta.');
        }

        // 2ª opção (transitória): chamada direta ao Google com a chave lida do
        // app_settings. Mantida só até a Edge Function estar publicada em todos
        // os clientes; depois a linha google_map_api_key pode ser bloqueada por RLS.
        if (!success && coordsList.length >= 2) {
          String googleApiKey = '';
          try {
            final configRow = await Supabase.instance.client
                .from('app_settings')
                .select('value')
                .eq('key', 'google_map_api_key')
                .maybeSingle();
            if (configRow != null && configRow['value'] != null) {
              googleApiKey = configRow['value'].toString();
            }
          } catch (_) {}

          if (googleApiKey.isNotEmpty) {
            try {
              String url = 'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&key=$googleApiKey&language=pt-BR';
              if (intermediates != null) {
                url += '&waypoints=${Uri.encodeComponent(intermediates)}';
              }
              final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
              if (response.statusCode == 200) {
                success = parseGoogleDirections(json.decode(response.body));
              }
            } catch (e) {
              debugPrint('[Google-Driver-Nav] Exception: $e');
            }
          }
        }
      } else {
        // OSRM
        debugPrint('[OSRM-Driver-Nav] Requesting OSRM routing');
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

        final coords = coordsList.map((w) => '${w.longitude},${w.latitude}').join(';');
        String url = '$osrmBaseUrl/route/v1/driving/$coords?overview=full&geometries=geojson&steps=true';
        // Envia o rumo atual do veículo: sem isso a rota recalculada em
        // movimento às vezes começava mandando fazer retorno (U-turn).
        final heading = driverLoc?.rotation;
        if (heading != null) {
          final bearings = List<String>.filled(coordsList.length, '');
          bearings[0] = '${heading.toInt()},45';
          url += '&bearings=${bearings.join(';')}';
        }

        try {
          final response = await http.get(
            Uri.parse(url),
            headers: {'User-Agent': 'UppiDriverApp/1.0.0'},
          ).timeout(const Duration(seconds: 6));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data != null && data['routes'] != null && (data['routes'] as List).isNotEmpty) {
              final route = data['routes'][0];
              final legs = route['legs'] as List? ?? [];
              
              parsedSteps = [];
              for (var leg in legs) {
                final legSteps = leg['steps'] as List? ?? [];
                for (var step in legSteps) {
                  parsedSteps.add(RouteStep.fromJson(step));
                }
              }

              final geometry = route['geometry'] as Map<String, dynamic>?;
              routePoints = [];
              if (geometry != null && geometry['coordinates'] != null) {
                final coords = geometry['coordinates'] as List;
                for (var c in coords) {
                  if (c is List && c.length >= 2) {
                    routePoints.add(LatLng(
                      (c[1] as num).toDouble(),
                      (c[0] as num).toDouble(),
                    ));
                  }
                }
              }
              success = true;
            }
          }
        } catch (e) {
          debugPrint('[OSRM-Driver-Nav] Exception: $e');
        }
      }

      if (success) {
        if (mounted) {
          _reconnectTimer?.cancel();
          // Se a lista antiga de passos estava vazia, é a carga inicial da viagem.
          // Caso contrário, é um recálculo automático em movimento.
          final isInitialLoad = _steps.isEmpty;
          setState(() {
            _steps = parsedSteps;
            _currentStepIndex = 0;
            _loadedRideId = order.id;
            _loadedWaypointIndex = order.destinationArrivedTo;
            _loadedStatus = order.status;
            _isLoading = false;
            _isRecalculating = false;
            _isOfflineError = false;
          });
          HomeNavigationOverlay.activeRouteNotifier.value = routePoints;
          _buildRouteIndex(routePoints, parsedSteps);
          _spoken.clear();
          if (parsedSteps.isNotEmpty) {
            _spoken.add('a0');
            // Só fala a instrução de partida inicial se for o carregamento inicial da rota da viagem,
            // evitando que o motorista ouça repetidamente "Siga em direção a rua" em recálculos de desvio.
            if (isInitialLoad) {
              _speak(parsedSteps.first.getInstruction(context));
            }
          }
          _lastRouteLoadedTime = DateTime.now();
          _processLocationUpdate();
        }
        return;
      }
    } catch (e) {
      debugPrint('Error fetching turn-by-turn steps: $e');
    }

    if (mounted) {
      // Distingue "sem internet" de "erro ao calcular a rota" (ex.: Google
      // sem resultado, OSRM fora do ar) — antes toda falha virava a mensagem
      // enganosa de falta de sinal mesmo com internet perfeita.
      bool offline = true;
      try {
        offline = !locator<ConnectivityCubit>().state.isConnected;
      } catch (_) {}
      setState(() {
        _isOfflineError = true;
        _failureWasOffline = offline;
        _isLoading = false;
        _isRecalculating = false;
      });
      _scheduleReconnectRetry();
    }
  }

  void _scheduleReconnectRetry() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _isOfflineError && !_isLoading && !_isRecalculating) {
        debugPrint('[Navigation] Tentando reconectar e buscar rota novamente...');
        _fetchStepsIfNeeded();
      }
    });
  }

  double _getDynamicOffRouteThreshold(double speedKmh) {
    if (speedKmh <= 30.0) {
      return 15.0;
    } else if (speedKmh <= 70.0) {
      return 25.0;
    } else {
      return 35.0;
    }
  }

  Duration _getDynamicRecalculateCooldown(double speedKmh) {
    if (speedKmh <= 30.0) {
      return const Duration(seconds: 8);
    } else if (speedKmh <= 70.0) {
      return const Duration(seconds: 4);
    } else {
      return const Duration(seconds: 2);
    }
  }

  void _processLocationUpdate() {
    if (widget.driverLocation == null || _steps.isEmpty) return;

    final driverLatLng = LatLng(widget.driverLocation!.lat, widget.driverLocation!.lng);
    
    // Sem índice da rota ainda → usa o método antigo (linha reta) como
    // fallback seguro.
    if (_routeGeom.length < 2 || _stepsAlong.length != _steps.length) {
      _processLocationUpdateFallback(driverLatLng);
      return;
    }

    // 1. MAP-MATCHING: "gruda" a posição do motorista na linha da rota.
    // Busca primeiro numa janela em torno da última posição conhecida; se o
    // melhor ponto da janela ficou longe (salto de GPS legítimo), refaz na
    // rota inteira como fallback.
    var match = _snapToRoute(driverLatLng, nearAlong: _lastMatchAlong);
    if (_lastMatchAlong != null && match.offRoute > 50.0) {
      match = _snapToRoute(driverLatLng);
    }
    _lastMatchAlong = match.along;

    // Atualiza o índice do motorista e da próxima manobra para otimização do mapa
    HomeNavigationOverlay.driverIdxNotifier.value = match.index;
    if (_currentStepIndex >= 0 && _currentStepIndex < _stepsIndices.length) {
      HomeNavigationOverlay.nextManeuverIdxNotifier.value = _stepsIndices[_currentStepIndex];
    } else {
      HomeNavigationOverlay.nextManeuverIdxNotifier.value = _routeGeom.length - 1;
    }

    // 1.5 Wrong Way Detection (Detecção de Contramão):
    bool wrongWay = false;
    final driverRotation = widget.driverLocation!.rotation;
    // rotation == 0 em muitos aparelhos significa "heading indisponível", não
    // "norte" — usar esse valor causava falso positivo de contramão em vias
    // que seguem para o sul (mesma checagem já usada na câmera do mapa).
    if (driverRotation != null && driverRotation != 0 && DriverSpeed.kmh.value > 10.0) {
      final diff = (driverRotation.toDouble() - match.bearing).abs() % 360;
      final angleDiff = diff > 180 ? 360 - diff : diff;
      if (angleDiff > 135.0) {
        wrongWay = true;
        debugPrint('[Navigation] Sentido contrário detectado (Diferença de rumo: ${angleDiff.toStringAsFixed(1)}°).');
      }
    }

    // 2. Off-route / Wrong-way: adaptativo conforme velocidade do veículo.
    final dynamicOffRouteThreshold = _getDynamicOffRouteThreshold(DriverSpeed.kmh.value);
    final dynamicCooldown = _getDynamicRecalculateCooldown(DriverSpeed.kmh.value);

    // Evita o loop da morte de recálculo em alta velocidade.
    // Durante os primeiros 8 segundos após carregar uma nova rota,
    // o limiar de desvio é multiplicado por 2.5 para dar tempo da posição do GPS se alinhar
    // ao novo trajeto em movimento rápido.
    double finalThreshold = dynamicOffRouteThreshold;
    final now = DateTime.now();
    // Durante os primeiros 4 segundos após carregar uma nova rota,
    // o limiar de desvio é multiplicado por 1.8 para dar tempo de o GPS se assentar.
    if (_lastRouteLoadedTime != null && now.difference(_lastRouteLoadedTime!) < const Duration(seconds: 4)) {
      finalThreshold = dynamicOffRouteThreshold * 1.8;
    }

    // Evita recálculos infinitos devido a flutuações e ruídos do sinal de GPS quando o carro está parado.
    // O desvio de fora de rota só é testado se o veículo de fato estiver em movimento (velocidade > 5 km/h).
    final isMoving = DriverSpeed.kmh.value > 5.0;

    if (isMoving && (match.offRoute > finalThreshold || wrongWay) && !_isRecalculating && !_isLoading) {
      final now = DateTime.now();
      if (_lastRecalculateTime != null && now.difference(_lastRecalculateTime!) < dynamicCooldown) {
        debugPrint('[Navigation] Recálculo bloqueado temporariamente (cooldown anti-spam).');
      } else {
        _lastRecalculateTime = now;
        setState(() => _isRecalculating = true);
        debugPrint('[Navigation] Forçando recálculo por desvio (${match.offRoute.toStringAsFixed(1)}m de limiar $dynamicOffRouteThreshold) ou contramão ($wrongWay).');
        _speakRecalculating();
        _fetchStepsIfNeeded();
      }
      return;
    }

    // 3. Avanço de manobra medido pela distância percorrida AO LONGO da rota
    // (não em linha reta) — robusto mesmo em ruas curvas/rápidas.
    int newIndex = _currentStepIndex;
    while (newIndex < _steps.length - 1 && match.along >= _stepsAlong[newIndex] - 5) {
      newIndex++;
    }
    if (newIndex != _currentStepIndex) {
      setState(() => _currentStepIndex = newIndex);
      debugPrint('[Navigation] Manobra avançada para $_currentStepIndex: ${_steps[_currentStepIndex].instruction}');
    }

    // Calcular limite de velocidade dinamicamente com base no nome da via e instrução (Google)
    final currentStep = _steps[_currentStepIndex];
    double limit = 60.0;
    final nameLower = currentStep.name.toLowerCase();
    final instrLower = currentStep.instruction.toLowerCase();

    final isHighway = nameLower.contains('rodovia') || nameLower.contains('br-') || nameLower.contains('pa-') || nameLower.contains('rod.') ||
                      instrLower.contains('rodovia') || instrLower.contains('br-') || instrLower.contains('pa-') || instrLower.contains('rod.');
    final isAvenue = nameLower.contains('avenida') || nameLower.contains('av.') ||
                     instrLower.contains('avenida') || instrLower.contains('av.');

    if (isHighway) {
      limit = 110.0;
    } else if (isAvenue) {
      limit = 80.0;
    }
    if (HomeNavigationOverlay.speedLimitNotifier.value != limit) {
      HomeNavigationOverlay.speedLimitNotifier.value = limit;
    }
    _maybeAnnounceSpeedLimit(limit);

    // Nome da via atual (pílula estilo Google Maps): a via que o motorista
    // percorre agora é a do passo ANTERIOR à próxima manobra.
    String roadName = '';
    if (_currentStepIndex > 0 && _currentStepIndex - 1 < _steps.length) {
      roadName = _steps[_currentStepIndex - 1].name;
    } else if (_steps.isNotEmpty) {
      roadName = _steps.first.name;
    }
    if (roadName == 'null') roadName = '';
    if (HomeNavigationOverlay.currentRoadNotifier.value != roadName) {
      HomeNavigationOverlay.currentRoadNotifier.value = roadName;
    }

    // 4. Distâncias medidas ao longo da rota.
    final distToManeuver =
        (_stepsAlong[_currentStepIndex] - match.along).clamp(0.0, _routeLength).toDouble();
    final remainingDist = (_routeLength - match.along).clamp(0.0, _routeLength).toDouble();

    // 5. Tempo restante usando a DURAÇÃO REAL de cada trecho (vinda do OSRM):
    // fração restante do trecho atual + soma dos trechos seguintes.
    double remainingDur = 0.0;
    final curIdx = _currentStepIndex;
    if (curIdx >= 1) {
      final seg = _steps[curIdx - 1];
      if (seg.distance > 0) {
        final frac = (distToManeuver / seg.distance).clamp(0.0, 1.0);
        remainingDur += frac * seg.duration;
      }
    }
    for (int i = curIdx; i < _steps.length; i++) {
      remainingDur += _steps[i].duration;
    }

    HomeNavigationOverlay.distanceToNextManeuverNotifier.value = distToManeuver;
    HomeNavigationOverlay.remainingDistanceNotifier.value = remainingDist;
    HomeNavigationOverlay.remainingDurationNotifier.value = remainingDur;
    setState(() {
      _distanceToNextManeuver = distToManeuver;
    });

    _maybeAnnounce();
    _updateNextManeuverNotifier();
  }

  /// Fallback em linha reta (método antigo), usado se o índice da rota ainda
  /// não estiver disponível.
  void _processLocationUpdateFallback(LatLng driverLatLng) {
    double minDistanceToRoute = double.infinity;
    final routePoints = HomeNavigationOverlay.activeRouteNotifier.value;
    final Iterable<LatLng> probe =
        routePoints.isNotEmpty ? routePoints : _steps.map((s) => s.location);
    for (final point in probe) {
      final dist = _calculateDistance(driverLatLng, point);
      if (dist < minDistanceToRoute) minDistanceToRoute = dist;
    }

    final dynamicOffRouteThreshold = _getDynamicOffRouteThreshold(DriverSpeed.kmh.value);
    final dynamicCooldown = _getDynamicRecalculateCooldown(DriverSpeed.kmh.value);

    if (minDistanceToRoute > (dynamicOffRouteThreshold * 2.5) && !_isRecalculating && !_isLoading) {
      final now = DateTime.now();
      if (_lastRecalculateTime != null && now.difference(_lastRecalculateTime!) < dynamicCooldown) {
        debugPrint('[Navigation] Recálculo fallback bloqueado por cooldown.');
      } else {
        _lastRecalculateTime = now;
        setState(() => _isRecalculating = true);
        _fetchStepsIfNeeded();
      }
      return;
    }

    final currentStep = _steps[_currentStepIndex];
    final distanceToNext = _calculateDistance(driverLatLng, currentStep.location);
    if (distanceToNext < 20.0 && _currentStepIndex < _steps.length - 1) {
      setState(() => _currentStepIndex++);
    }

    double remainingDist = 0.0;
    double remainingDur = 0.0;
    _distanceToNextManeuver =
        _calculateDistance(driverLatLng, _steps[_currentStepIndex].location);
    remainingDist += _distanceToNextManeuver;
    remainingDur += (_distanceToNextManeuver /
        (currentStep.distance > 0
            ? (currentStep.distance / (currentStep.duration > 0 ? currentStep.duration : 1))
            : 10));
    for (int i = _currentStepIndex + 1; i < _steps.length; i++) {
      remainingDist += _steps[i].distance;
      remainingDur += _steps[i].duration;
    }
    HomeNavigationOverlay.distanceToNextManeuverNotifier.value = _distanceToNextManeuver;
    HomeNavigationOverlay.remainingDistanceNotifier.value = remainingDist;
    HomeNavigationOverlay.remainingDurationNotifier.value = remainingDur;
    setState(() {});
    _maybeAnnounce();
    _updateNextManeuverNotifier();
  }

  double _calculateDistance(LatLng p1, LatLng p2) {
    const double r = 6371000; // Raio da Terra em metros
    final double lat1 = p1.latitude * (math.pi / 180.0);
    final double lat2 = p2.latitude * (math.pi / 180.0);
    final double diffLat = (p2.latitude - p1.latitude) * (math.pi / 180.0);
    final double diffLng = (p2.longitude - p1.longitude) * (math.pi / 180.0);

    final double a = math.sin(diffLat / 2) * math.sin(diffLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(diffLng / 2) * math.sin(diffLng / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  /// Constrói o índice da rota para map-matching: comprimento acumulado de
  /// cada ponto e a distância (ao longo da rota) de cada manobra.
  void _buildRouteIndex(List<LatLng> points, List<RouteStep> steps) {
    _lastMatchAlong = null; // rota nova → zera a âncora de continuidade
    _routeGeom = points;
    _cumLen = List<double>.filled(points.length, 0.0);
    double acc = 0.0;
    for (int i = 1; i < points.length; i++) {
      acc += _calculateDistance(points[i - 1], points[i]);
      _cumLen[i] = acc;
    }
    _routeLength = acc;

    _stepsAlong = List<double>.filled(steps.length, 0.0);
    _stepsIndices = List<int>.filled(steps.length, 0);
    if (points.length >= 2) {
      for (int i = 0; i < steps.length; i++) {
        final snap = _snapToRoute(steps[i].location);
        _stepsAlong[i] = snap.along;
        _stepsIndices[i] = snap.index;
      }
      // Mantém não-decrescente (evita manobra "voltando" por ruído).
      for (int i = 1; i < _stepsAlong.length; i++) {
        if (_stepsAlong[i] < _stepsAlong[i - 1]) {
          _stepsAlong[i] = _stepsAlong[i - 1];
          _stepsIndices[i] = _stepsIndices[i - 1];
        }
      }
      // A chegada fica exatamente no fim da rota.
      _stepsAlong[_stepsAlong.length - 1] = _routeLength;
      _stepsIndices[_stepsIndices.length - 1] = points.length - 1;
    }
  }

  /// Busca binária: primeiro índice de [list] (crescente) com valor >= [value].
  int _lowerBound(List<double> list, double value) {
    int lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid] < value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Projeta [p] na polyline da rota. Retorna o ponto "grudado" na rua, a
  /// distância acumulada ao longo da rota até ele, o desvio (off-route), a direção do trecho e o índice do segmento.
  ({LatLng snapped, double along, double offRoute, double bearing, int index}) _snapToRoute(LatLng p, {double? nearAlong}) {
    if (_routeGeom.length < 2) {
      return (snapped: p, along: 0.0, offRoute: 0.0, bearing: 0.0, index: 0);
    }

    // Com [nearAlong], restringe a busca a uma janela em torno da última
    // posição conhecida na rota (continuidade) — também evita varrer a
    // geometria inteira a cada fix de GPS.
    int first = 0;
    int last = _routeGeom.length - 1; // segmentos: i < last
    if (nearAlong != null) {
      const double back = 300.0;
      const double ahead = 1200.0;
      first = _lowerBound(_cumLen, nearAlong - back) - 1;
      if (first < 0) first = 0;
      last = _lowerBound(_cumLen, nearAlong + ahead);
      if (last > _routeGeom.length - 1) last = _routeGeom.length - 1;
      if (last <= first) {
        first = 0;
        last = _routeGeom.length - 1;
      }
    }

    double bestOff = double.infinity;
    double bestAlong = 0.0;
    LatLng bestSnapped = _routeGeom.first;
    double bestBearing = 0.0;
    int bestIndex = 0;

    for (int i = first; i < last; i++) {
      final a = _routeGeom[i];
      final b = _routeGeom[i + 1];

      // Projeção planar local (metros), com origem em A.
      final mPerLng = 111320.0 * math.cos(a.latitude * math.pi / 180.0);
      const mPerLat = 111320.0;
      final bx = (b.longitude - a.longitude) * mPerLng;
      final by = (b.latitude - a.latitude) * mPerLat;
      final px = (p.longitude - a.longitude) * mPerLng;
      final py = (p.latitude - a.latitude) * mPerLat;

      final segLen2 = bx * bx + by * by;
      double t = segLen2 > 0 ? (px * bx + py * by) / segLen2 : 0.0;
      if (t < 0) t = 0;
      if (t > 1) t = 1;

      final snapped = LatLng(
        a.latitude + t * (b.latitude - a.latitude),
        a.longitude + t * (b.longitude - a.longitude),
      );

      final off = _calculateDistance(p, snapped);
      if (off < bestOff) {
        bestOff = off;
        bestSnapped = snapped;
        bestAlong = _cumLen[i] + _calculateDistance(a, snapped);
        bestIndex = i;
        
        // Calcula bearing planar de A a B.
        final sdy = b.latitude - a.latitude;
        final sdx = (b.longitude - a.longitude) * math.cos(a.latitude * math.pi / 180.0);
        bestBearing = (math.atan2(sdx, sdy) * 180.0 / math.pi + 360.0) % 360.0;
      }
    }
    return (snapped: bestSnapped, along: bestAlong, offRoute: bestOff, bearing: bestBearing, index: bestIndex);
  }

  IconData _getManeuverIcon(String type, String modifier) {
    return HomeNavigationOverlay.getManeuverIcon(type, modifier);
  }

  Color _getManeuverColor(String modifier) {
    if (modifier.contains('left')) {
      return const Color(0xFF10B981); // Verde Neon Uppi
    } else if (modifier.contains('right')) {
      return const Color(0xFF3B82F6); // Azul Vibrante
    } else {
      return const Color(0xFFEAB308); // Amarelo/Amber
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }



  void _showTurnByTurnBottomSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBgColor = isDark ? const Color(0xFA202124) : const Color(0xFAFFFFFF);
    final sheetBorderColor = isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08);
    final sheetHandleColor = isDark ? Colors.white.withOpacity(0.2) : Colors.black.withOpacity(0.15);
    final sheetTitleColor = isDark ? Colors.white : Colors.black87;
    final iconColor = isDark ? Colors.white70 : Colors.black54;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(30),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.only(top: 16, left: 20, right: 20, bottom: 24),
              decoration: BoxDecoration(
                color: sheetBgColor,
                border: Border(
                  top: BorderSide(
                    color: sheetBorderColor,
                    width: 1.5,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: sheetHandleColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.translate.turnByTurnInstructions,
                        style: TextStyle(
                          color: sheetTitleColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close_rounded, color: iconColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _steps.length,
                      separatorBuilder: (context, index) => Divider(
                        color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final step = _steps[index];
                        final isCurrent = index == _currentStepIndex;
                        final color = _getManeuverColor(step.modifier);
                        final icon = _getManeuverIcon(step.maneuverType, step.modifier);
                        
                        final highlightBg = isCurrent
                            ? (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03))
                            : Colors.transparent;
                        final itemTitleColor = isCurrent
                            ? (isDark ? Colors.white : Colors.black87)
                            : (isDark ? Colors.white70 : Colors.black54);
                        final distanceColor = isCurrent
                            ? (isDark ? Colors.greenAccent.shade400 : Colors.green.shade600)
                            : (isDark ? Colors.white38 : Colors.black38);
                        final badgeColor = isDark ? Colors.greenAccent : Colors.green.shade700;

                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                          decoration: BoxDecoration(
                            color: highlightBg,
                            borderRadius: BorderRadius.circular(14),
                            border: isCurrent 
                              ? Border.all(color: color.withOpacity(0.3), width: 1)
                              : null,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: color.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Icon(
                                  icon,
                                  color: color,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      step.getInstruction(context),
                                      style: TextStyle(
                                        color: itemTitleColor,
                                        fontSize: 15,
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                      ),
                                    ),
                                    if (step.distance > 0) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatDistance(step.distance),
                                        style: TextStyle(
                                          color: distanceColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (isCurrent) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: badgeColor.withOpacity(0.4),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    'ATUAL',
                                    style: TextStyle(
                                      color: badgeColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;

    if (_isOfflineError && _steps.isEmpty) {
      final isConnected = locator<ConnectivityCubit>().state.isConnected;
      final errorMsg = isConnected
          ? "Falha no servidor de rotas. Tentando reconectar..."
          : "Sem sinal de internet. Tentando reconectar...";
      return _buildContainer(
        height: 80,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(
              isConnected ? Icons.cloud_off_rounded : Icons.wifi_off_rounded,
              color: Colors.redAccent.shade400,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                errorMsg,
                style: TextStyle(
                  color: Colors.redAccent.shade400,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoading && _steps.isEmpty) {
      return _buildContainer(
        height: 80,
        child: Row(
          children: [
            const SizedBox(width: 16),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.greenAccent.shade400),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              context.translate.searchingNavigation,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (_isRecalculating && _steps.isEmpty) {
      return _buildContainer(
        height: 80,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(Icons.sync, color: Colors.orangeAccent.shade400, size: 24),
            const SizedBox(width: 16),
            Text(
              context.translate.recalculatingRoute,
              style: TextStyle(
                color: Colors.orangeAccent.shade400,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (_steps.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentStep = _steps[_currentStepIndex];
    final hasNextStep = _currentStepIndex < _steps.length - 1;
    final nextStep = hasNextStep ? _steps[_currentStepIndex + 1] : null;

    final maneuverIcon = _getManeuverIcon(currentStep.maneuverType, currentStep.modifier);

    final isNight = Theme.of(context).brightness == Brightness.dark;
    final hudBgColor = isNight ? const Color(0xE61C1C1E) : const Color(0xE60F9D58);
    final hudBorderColor = isNight ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.18);

    return GestureDetector(
      onTap: () => _showTurnByTurnBottomSheet(context),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: hudBgColor,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              border: Border(
                left: BorderSide(color: hudBorderColor, width: 0.5),
                right: BorderSide(color: hudBorderColor, width: 0.5),
                bottom: BorderSide(color: hudBorderColor, width: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    top: padding.top + 16,
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          maneuverIcon,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isOfflineError) ...[
                              Text(
                                _failureWasOffline
                                    ? "SEM INTERNET. RECONECTANDO..."
                                    : "ERRO AO ATUALIZAR ROTA. TENTANDO DE NOVO...",
                                style: TextStyle(
                                  color: Colors.redAccent.shade100,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                            ],
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  _formatDistance(_distanceToNextManeuver),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                if (_isRecalculating || _isLoading) ...[
                                  const SizedBox(width: 10),
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              currentStep.getInstruction(context),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.95),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildMuteButton(),
                    ],
                  ),
                ),
                // Linear progress bar showing proximity to the next maneuver
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: 0.0,
                    end: currentStep.distance > 0
                        ? (1.0 - (_distanceToNextManeuver / currentStep.distance).clamp(0.0, 1.0))
                        : 0.0,
                  ),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeInOut,
                  builder: (context, value, _) {
                    return LinearProgressIndicator(
                      value: value,
                      minHeight: 3,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isNight
                            ? const Color(0xFF00E5FF) // Neon Cyan in dark mode
                            : Colors.white,            // White in light mode
                      ),
                    );
                  },
                ),
                if (hasNextStep && nextStep != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: Colors.black.withOpacity(0.25),
                    child: Row(
                      children: [
                        Text(
                          '${context.translate.then.toUpperCase()} ',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Icon(
                          _getManeuverIcon(nextStep.maneuverType, nextStep.modifier),
                          color: Colors.white.withOpacity(0.6),
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            nextStep.getInstruction(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMuteButton() {
    return ValueListenableBuilder<bool>(
      valueListenable: HomeNavigationOverlay.voiceEnabledNotifier,
      builder: (context, enabled, _) {
        return GestureDetector(
          onTap: () {
            HomeNavigationOverlay.voiceEnabledNotifier.value = !enabled;
            if (enabled) _tts?.stop(); // estava ligado → silencia agora
            try {
              HydratedBloc.storage.write(_voicePrefKey, !enabled);
            } catch (_) {}
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        );
      },
    );
  }

  Widget _buildContainer({
    required Widget child,
    double? height,
    EdgeInsetsGeometry? padding,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFA202124) : const Color(0xFAFFFFFF);
    final borderColor = isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08);
    final shadowColor = isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.08);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: height,
          padding: padding,
          width: double.infinity,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: borderColor,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 16,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
