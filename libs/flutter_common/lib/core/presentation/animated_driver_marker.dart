import 'package:flutter/material.dart';
import 'package:flutter_common/gen/assets.gen.dart';
import 'package:flutter_common/core/entities/driver_location.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:generic_map/generic_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_common/core/presentation/uppi_feedback.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
class UppiRainDetector {
  static bool isRaining = false;
  static RealtimeChannel? _rainChannel;
  static final List<VoidCallback> _listeners = [];
  static bool _isInitialized = false;

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
    if (!_isInitialized) {
      _init();
    }
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty && _isInitialized) {
      try {
        _rainChannel?.unsubscribe();
      } catch (_) {}
      _rainChannel = null;
      _isInitialized = false;
    }
  }

  static void _init() {
    _isInitialized = true;
    Supabase.instance.client
        .from('app_settings')
        .select('value')
        .eq('key', 'is_raining')
        .maybeSingle()
        .then((row) {
      if (row != null) {
        final val = row['value']?.toString() == 'true';
        if (isRaining != val) {
          isRaining = val;
          _notify();
        }
      }
    });

    _rainChannel = Supabase.instance.client
        .channel('global_rain_detector')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_settings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'key',
            value: 'is_raining',
          ),
          callback: (payload) {
            final val = payload.newRecord['value']?.toString() == 'true';
            if (isRaining != val) {
              isRaining = val;
              _notify();
            }
          },
        );
    try {
      _rainChannel!.subscribe();
    } catch (_) {}
  }

  static void _notify() {
    for (final listener in List<VoidCallback>.from(_listeners)) {
      try {
        listener();
      } catch (_) {}
    }
  }
}

/// Widget que anima suavemente a transição do marcador do motorista no mapa
/// Elimina o "teleporte" — a transição é fluida como no Uber/99
class AnimatedDriverMarker extends StatefulWidget {
  final LatLng targetPosition;
  final int targetRotation;
  final String? vehicleType;
  final String? markerUrl;
  final Duration animationDuration;

  /// Quando `true`, desenha uma seta (chevron) estilo Google Maps em vez do
  /// carrinho — usado SÓ na navegação do motorista. O app do passageiro
  /// mantém `false`, então continua vendo o carro.
  final bool navigationMode;
  final bool isGoogleMaps;

  const AnimatedDriverMarker({
    super.key,
    required this.targetPosition,
    required this.targetRotation,
    this.vehicleType,
    this.markerUrl,
    this.navigationMode = false,
    this.isGoogleMaps = false,
    this.animationDuration = const Duration(milliseconds: 1000),
  });

  @override
  State<AnimatedDriverMarker> createState() => _AnimatedDriverMarkerState();
}

class _AnimatedDriverMarkerState extends State<AnimatedDriverMarker>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _latAnimation;
  late Animation<double> _lngAnimation;
  late Animation<double> _rotationAnimation;

  late AnimationController _haloController;
  late Animation<double> _haloScaleAnimation;

  LatLng _currentPosition = const LatLng(0, 0);
  double _currentRotation = 0;
  bool _isFirst = true;

  // Reatividade climática no próprio marcador
  bool _isRaining = false;

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.targetPosition;
    _currentRotation = widget.targetRotation.toDouble();

    _controller = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );

    _haloController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat(reverse: true);

    _haloScaleAnimation = Tween<double>(begin: 0.82, end: 1.12).animate(
      CurvedAnimation(
        parent: _haloController,
        curve: Curves.easeInOut,
      ),
    );

    _setupAnimations(widget.targetPosition, widget.targetRotation.toDouble());
    _startRainingListener();
  }

  void _startRainingListener() {
    _isRaining = UppiRainDetector.isRaining;
    UppiRainDetector.addListener(_onRainChanged);
  }

  void _onRainChanged() {
    if (mounted) {
      setState(() {
        _isRaining = UppiRainDetector.isRaining;
      });
    }
  }

  void _setupAnimations(LatLng target, double targetRot) {
    final curve = widget.navigationMode ? Curves.linear : Curves.easeInOutCubic;

    _latAnimation =
        Tween<double>(
          begin: _currentPosition.latitude,
          end: target.latitude,
        ).animate(
          CurvedAnimation(parent: _controller, curve: curve),
        );

    _lngAnimation =
        Tween<double>(
          begin: _currentPosition.longitude,
          end: target.longitude,
        ).animate(
          CurvedAnimation(parent: _controller, curve: curve),
        );

    // Normalizar rotação para evitar giro de 350° quando deveria girar 10°
    double startRot = _currentRotation;
    double endRot = targetRot;
    double diff = endRot - startRot;
    if (diff > 180) endRot -= 360;
    if (diff < -180) endRot += 360;

    _rotationAnimation = Tween<double>(begin: startRot, end: endRot).animate(
      CurvedAnimation(parent: _controller, curve: curve),
    );
  }

  @override
  void didUpdateWidget(AnimatedDriverMarker oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.targetPosition != widget.targetPosition ||
        oldWidget.targetRotation != widget.targetRotation) {
      _currentPosition = LatLng(_latAnimation.value, _lngAnimation.value);
      _currentRotation = _rotationAnimation.value;

      _controller.duration = widget.animationDuration;
      _setupAnimations(widget.targetPosition, widget.targetRotation.toDouble());

      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _haloController.dispose();
    UppiRainDetector.removeListener(_onRainChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vehicleWidget = widget.navigationMode ? _buildNavigationChevron() : _buildVehicleImage();

    // Se estiver chovendo, envolvemos o carro em um visual elegante com badge de gotinha d'água
    final decoratedWidget = _isRaining && !widget.navigationMode
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              vehicleWidget,
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.water_drop,
                    color: ColorPalette.primary40, // Gotinha no azul original do Uppi
                    size: 11,
                  ),
                ),
              ),
            ],
          )
        : vehicleWidget;

    if (widget.isGoogleMaps) {
      return decoratedWidget;
    }

    if (_isFirst) {
      _isFirst = false;
      return Transform.rotate(
        angle: widget.targetRotation * (pi / 180),
        child: decoratedWidget,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        double dx = 0;
        double dy = 0;

        try {
          // UPPI BRASIL FLUIDEZ DE MARCADOR:
          // O widget marcador do flutter_map fica posicionado fisicamente em targetPosition.
          // Para evitar o "teleporte", calculamos a cada frame da animação a diferença em pixels
          // entre a posição final (targetPosition) e a posição animada intermediária,
          // e aplicamos essa diferença como translação visual (Transform.translate).
          final camera = MapCamera.of(context);
          final targetPoint = camera.latLngToScreenPoint(widget.targetPosition);
          final animPoint = camera.latLngToScreenPoint(LatLng(_latAnimation.value, _lngAnimation.value));
          
          dx = animPoint.x - targetPoint.x;
          dy = animPoint.y - targetPoint.y;
        } catch (_) {
          // Fallback seguro caso esteja usando Google Maps ou sem contexto de câmera do Leaflet
        }

        return Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.rotate(
            angle: _rotationAnimation.value * (pi / 180),
            child: child,
          ),
        );
      },
      child: decoratedWidget,
    );
  }

  Widget _buildVehicleImage() {
    final isMoto = widget.vehicleType?.toLowerCase() == 'moto';
    if (widget.markerUrl != null && widget.markerUrl!.isNotEmpty) {
      return Image.network(widget.markerUrl!, width: 48, height: 48);
    }
    return isMoto
        ? Assets.images.motoTopView.image(width: 40, height: 40)
        : Assets.images.carTopView.image(width: 48, height: 48);
  }

  /// Seta de navegação estilo Google Maps: halo de precisão pulsante +
  /// círculo azul com borda branca + seta branca apontando na direção do
  /// movimento (a rotação vem do pai: rota snapped / GPS / bússola).
  Widget _buildNavigationChevron() {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Halo de precisão (azul translúcido pulsante)
          ScaleTransition(
            scale: _haloScaleAnimation,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF4285F4).withOpacity(0.20),
              ),
            ),
          ),
          // Chevron 3D Oficial do Google Maps (borda branca + sombra)
          const SizedBox(
            width: 28,
            height: 35,
            child: CustomPaint(
              painter: ChevronPainter(
                fillLogicColor: Color(0xFF1A73E8),
                strokeColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Extensão sobre DriverLocation para gerar CustomMarker animado
/// Uso: driverLocation.animatedMarker() em vez de driverLocation.genericMarker()
extension AnimatedDriverLocationX on DriverLocation {
  CustomMarker animatedMarker({
    Key? key,
    bool navigationMode = false,
    LatLng? overridePosition,
    int? overrideRotation,
    bool isGoogleMaps = false,
    Duration? animationDuration,
  }) {
    if (UppiPerformance.batterySaverMode) {
      return genericMarker();
    }
    // overridePosition: usado na navegação para "grudar" a posição na rua
    // (map-matching). Sem ele, usa a posição crua do GPS.
    final pos = overridePosition ?? LatLng(lat, lng);
    final rot = overrideRotation ?? rotation ?? 0;
    return CustomMarker(
      id: id?.toString() ?? 'driver',
      position: pos,
      alignment: Alignment.center,
      width: navigationMode ? 80 : 48,
      height: navigationMode ? 80 : 48,
      // Se for Google Maps, a rotação é feita de forma nativa pela GPU (definindo rotação no CustomMarker).
      // Se for Leaflet, a rotação é feita internamente pelo widget com animações suaves.
      rotation: isGoogleMaps ? rot : 0,
      flat: navigationMode,
      widget: AnimatedDriverMarker(
        // Chave ESTÁVEL (não usa a posição): senão o Flutter recria o marcador
        // a cada GPS — reabrindo o canal do Supabase (vazamento) e matando a
        // animação suave. Outros motoristas têm id próprio; o próprio = "self".
        key: key ?? ValueKey('driver_${id ?? "self"}'),
        targetPosition: pos,
        targetRotation: rot,
        vehicleType: vehicleType,
        markerUrl: markerUrl,
        navigationMode: navigationMode,
        isGoogleMaps: isGoogleMaps,
        animationDuration: animationDuration ?? (navigationMode
            ? const Duration(milliseconds: 900)
            : const Duration(milliseconds: 1200)),
      ),
    );
  }
}

/// Extensão para lista de DriverLocation com markers animados
extension AnimatedDriverLocationListX on List<DriverLocation> {
  List<CustomMarker> get animatedMarkers =>
      map((e) => e.animatedMarker()).toList();

  List<CustomMarker> animatedMarkersWith({bool isGoogleMaps = false}) =>
      map((e) => e.animatedMarker(isGoogleMaps: isGoogleMaps)).toList();
}

/// Desenha o chevron (seta de navegação) perfeitamente alinhado para o Norte (0°)
/// Evita gambiarras de rotação, desenhando em vetor nativo.
class ChevronPainter extends CustomPainter {
  final Color fillLogicColor;
  final Color strokeColor;

  const ChevronPainter({
    this.fillLogicColor = const Color(0xFF1A73E8), // Azul Maps
    this.strokeColor = Colors.white,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path();
    // Ponta superior (aponta reto para cima)
    path.moveTo(w / 2, 0);
    // Linha até a ponta inferior direita
    path.lineTo(w, h);
    // Linha até o centro interno (o recesso/vinco da seta)
    path.lineTo(w / 2, h * 0.72);
    // Linha até a ponta inferior esquerda
    path.lineTo(0, h);
    path.close();

    // 1. Sombra projetada do Chevron
    canvas.drawShadow(path.shift(const Offset(0, 2)), Colors.black, 4.0, true);

    // 2. Borda branca (stroke com espessura premium)
    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);

    // 3. Preenchimento azul Google Maps
    final fillPaint = Paint()
      ..color = fillLogicColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(covariant ChevronPainter oldDelegate) {
    return oldDelegate.fillLogicColor != fillLogicColor || oldDelegate.strokeColor != strokeColor;
  }
}

/// Desenha a seta de manobra estilo Google Maps — uma seta branca
/// semi-translúcida que fica "deitada" (flat) sobre a rota no ponto
/// onde ocorre a próxima curva/manobra.
///
/// Diferente do ChevronPainter (que é o marcador do motorista),
/// este painter é usado SOMENTE para indicar a DIREÇÃO da próxima
/// manobra sobre o mapa (como Google Maps/Waze faz com a seta no
/// ponto da curva).
class ManeuverArrowPainter extends CustomPainter {
  /// Ângulo de rotação em radianos. 0 = reto (para cima), positivo = horário.
  final double rotationRadians;

  const ManeuverArrowPainter({this.rotationRadians = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(rotationRadians);
    canvas.translate(-w / 2, -h / 2);

    // A seta é uma chevron grossa estilo Google Maps (apontando para cima)
    final path = Path();
    // Ponta central superior
    path.moveTo(w * 0.50, h * 0.12);
    // Linha para baixo-direita
    path.lineTo(w * 0.88, h * 0.72);
    // Recuo (braço interno direito)
    path.lineTo(w * 0.50, h * 0.52);
    // Recuo (braço interno esquerdo)
    path.lineTo(w * 0.12, h * 0.72);
    path.close();

    // 1. Sombra sutil projetada
    canvas.drawShadow(path.shift(const Offset(0, 1.5)), Colors.black, 3.0, true);

    // 2. Borda/stroke azul escuro muito fino para dar profundidade
    final strokePaint = Paint()
      ..color = const Color(0xFF3367D6) // Azul Google Maps mais escuro
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);

    // 3. Preenchimento branco semi-opaco (visual Google Maps real)
    final fillPaint = Paint()
      ..color = const Color(0xE6FFFFFF) // Branco com 90% opacidade
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ManeuverArrowPainter oldDelegate) {
    return oldDelegate.rotationRadians != rotationRadians;
  }

  /// Calcula o ângulo de rotação da seta a partir do modificador
  /// de manobra (e.g. 'left', 'right', 'sharp left', 'uturn', etc.).
  /// Retorno em radianos.
  static double modifierToRadians(String modifier) {
    switch (modifier) {
      case 'sharp left':
        return -2.356; // -135°
      case 'left':
        return -1.571; // -90°
      case 'slight left':
        return -0.785; // -45°
      case 'slight right':
        return 0.785; // +45°
      case 'right':
        return 1.571; // +90°
      case 'sharp right':
        return 2.356; // +135°
      case 'uturn':
        return 3.1416; // 180°
      case 'straight':
      default:
        return 0; // Reto para cima
    }
  }
}
