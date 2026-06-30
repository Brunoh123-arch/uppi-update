import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

/// Cor de destaque do oval (verde, como na referência do app).
const Color kFaceGreen = Color(0xFF22C55E);

/// Resultado de uma verificação facial.
///
/// Retornado por [FaceVerificationFlow] via `Navigator.pop`.
class FaceVerificationResult {
  /// Bytes JPEG da selfie capturada.
  final Uint8List imageBytes;

  /// Se a "prova de vida" guiada foi concluída com sucesso.
  final bool passed;

  /// Quanto tempo durou o roteiro (ms).
  final int durationMs;

  /// Etapas que o usuário completou (para auditoria/telemetria).
  final List<String> completedSteps;

  /// `true` quando capturou pela câmera/galeria do SO (sem preview ao vivo),
  /// por exemplo se a câmera ao vivo não estava disponível.
  final bool usedFallback;

  const FaceVerificationResult({
    required this.imageBytes,
    required this.passed,
    required this.durationMs,
    required this.completedSteps,
    this.usedFallback = false,
  });
}

/// Uma etapa do roteiro de "prova de vida" (liveness guiado).
class _LivenessStep {
  final String instruction;
  final IconData icon;
  final Duration duration;
  const _LivenessStep(this.instruction, this.icon, this.duration);
}

/// Fluxo de verificação facial reutilizável: câmera frontal ao vivo dentro de
/// um oval verde, roteiro de instruções ("prova de vida" guiada) e captura
/// automática da selfie ao final.
///
/// Uso:
/// ```dart
/// final r = await Navigator.of(context).push<FaceVerificationResult>(
///   MaterialPageRoute(builder: (_) => const FaceVerificationFlow(), fullscreenDialog: true),
/// );
/// ```
///
/// Foi escrito de forma autocontida (não depende de nada específico do painel
/// admin) para ser portado depois ao rider/driver app movendo este arquivo.
///
/// Observação: a "prova de vida" aqui é GUIADA por roteiro (challenge-response
/// por tempo), suficiente para uma verificação leve. O ponto de extensão para
/// detecção facial real (piscar/virar detectados por ML) está marcado em
/// [_runScript]. ML Kit não roda em Flutter Web, por isso o modo guiado é o
/// padrão que funciona no painel admin (web) e no app (mobile).
class FaceVerificationFlow extends StatefulWidget {
  final String title;
  const FaceVerificationFlow({super.key, this.title = 'Verificação Facial'});

  @override
  State<FaceVerificationFlow> createState() => _FaceVerificationFlowState();
}

class _FaceVerificationFlowState extends State<FaceVerificationFlow> {
  CameraController? _controller;
  bool _initializing = true;
  String? _initError;

  static const List<_LivenessStep> _steps = [
    _LivenessStep('Posicione seu rosto no círculo',
        Icons.face_retouching_natural, Duration(milliseconds: 1600)),
    _LivenessStep('Mantenha o rosto centralizado',
        Icons.center_focus_strong, Duration(milliseconds: 1500)),
    _LivenessStep('Pisque os olhos lentamente',
        Icons.remove_red_eye_outlined, Duration(milliseconds: 1600)),
    _LivenessStep('Vire o rosto levemente p/ a direita',
        Icons.turn_right, Duration(milliseconds: 1600)),
    _LivenessStep('Ótimo, não mexa o celular...',
        Icons.check_circle_outline, Duration(milliseconds: 1500)),
  ];

  int _currentStep = -1; // -1 = ainda não iniciou
  bool _running = false;
  bool _capturing = false;
  bool _done = false;
  bool _canceled = false;
  DateTime? _startedAt;

  @override
  void initState() {
    super.initState();
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _initError = 'Nenhuma câmera encontrada neste dispositivo.';
            _initializing = false;
          });
        }
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = e.toString();
          _initializing = false;
        });
      }
    }
  }

  /// Fração de etapas concluídas (0..1), usada pelos "pontos" de progresso.
  int get _completedCount {
    if (_done) return _steps.length;
    if (_currentStep < 0) return 0;
    return _currentStep + 1;
  }

  Future<void> _runScript() async {
    if (_running) return;
    setState(() {
      _running = true;
      _startedAt = DateTime.now();
    });

    for (var i = 0; i < _steps.length; i++) {
      if (_canceled || !mounted) return;
      setState(() => _currentStep = i);
      // PONTO DE EXTENSÃO: aqui é onde, no futuro, daria para validar a ação
      // real do usuário (piscar/virar) com detecção facial antes de avançar.
      await Future<void>.delayed(_steps[i].duration);
    }

    if (_canceled || !mounted) return;
    await _capture();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _capturing = true);
    try {
      final XFile shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      if (!mounted) return;
      final durationMs = _startedAt == null
          ? 0
          : DateTime.now().difference(_startedAt!).inMilliseconds;
      setState(() {
        _capturing = false;
        _done = true;
      });
      // Mostra o "check" de sucesso por um instante antes de fechar.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      Navigator.of(context).pop(
        FaceVerificationResult(
          imageBytes: bytes,
          passed: true,
          durationMs: durationMs,
          completedSteps: _steps.map((s) => s.instruction).toList(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao capturar: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// Fallback quando a câmera ao vivo não está disponível (permissão negada,
  /// sem webcam etc.): usa a câmera/galeria do sistema via image_picker.
  Future<void> _fallbackPick() async {
    try {
      final picker = ImagePicker();
      XFile? img = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      img ??= await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (img == null) return;
      final bytes = await img.readAsBytes();
      if (!mounted) return;
      Navigator.of(context).pop(
        FaceVerificationResult(
          imageBytes: bytes,
          passed: true,
          durationMs: 0,
          completedSteps: const [],
          usedFallback: true,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    _canceled = true;
    _controller?.dispose();
    super.dispose();
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _initializing
                  ? const Center(child: CircularProgressIndicator())
                  : _initError != null
                      ? _buildError()
                      : _buildScanner(),
            ),
            // Botão fechar (X), como na referência.
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                tooltip: 'Fechar',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded, color: Colors.white38, size: 64),
            const SizedBox(height: 16),
            Text(
              'Não foi possível abrir a câmera',
              style: GoogleFonts.outfit(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _initError ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fallbackPick,
              icon: const Icon(Icons.photo_camera_rounded),
              label: const Text('Enviar foto (câmera/galeria)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kFaceGreen,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanner() {
    final instruction = _done
        ? 'Tudo certo!'
        : _capturing
            ? 'Processando...'
            : !_running
                ? 'Toque em Iniciar e olhe para a câmera'
                : (_currentStep >= 0 ? _steps[_currentStep].instruction : '');

    final instructionIcon = _done
        ? Icons.verified_rounded
        : _capturing
            ? Icons.hourglass_top_rounded
            : !_running
                ? Icons.face_rounded
                : (_currentStep >= 0 ? _steps[_currentStep].icon : Icons.face_rounded);

    return Column(
      children: [
        const SizedBox(height: 56),
        Text(
          widget.title,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        // Oval + preview + anel verde + instrução sobre o rosto.
        SizedBox(
          width: 300,
          height: 380,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(child: _ovalPreview()),
              Positioned.fill(
                child: CustomPaint(
                  painter: _FaceRingPainter(
                    color: kFaceGreen,
                    glow: _running && !_done,
                  ),
                ),
              ),
              // Pílula de instrução sobre o rosto (como na referência).
              _instructionPill(instruction, instructionIcon),
            ],
          ),
        ),
        const SizedBox(height: 28),
        _stepDots(),
        const Spacer(),
        _bottomArea(),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _ovalPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox(width: 260, height: 340);
    }

    Widget preview = FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: 100 * controller.value.aspectRatio,
        height: 100,
        child: CameraPreview(controller),
      ),
    );

    return ClipPath(
      clipper: _OvalClipper(),
      child: SizedBox(width: 260, height: 340, child: preview),
    );
  }

  Widget _instructionPill(String text, IconData icon) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha:0.85),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF0B1220)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: const Color(0xFF0B1220),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_steps.length, (i) {
        final filled = i < _completedCount;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: filled ? 22 : 10,
          height: 10,
          decoration: BoxDecoration(
            color: filled ? kFaceGreen : Colors.white24,
            borderRadius: BorderRadius.circular(5),
          ),
        );
      }),
    );
  }

  Widget _bottomArea() {
    if (_done) {
      return const Icon(Icons.check_circle_rounded, color: kFaceGreen, size: 48);
    }
    if (_capturing) {
      return const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 3, color: kFaceGreen),
      );
    }
    if (_running) {
      return const Text(
        'Siga as instruções...',
        style: TextStyle(color: Colors.white54, fontSize: 14),
      );
    }
    // Estado inicial: botão Iniciar + atalho de fallback.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 240,
          child: ElevatedButton.icon(
            onPressed: _runScript,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Iniciar verificação'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kFaceGreen,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: GoogleFonts.outfit(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _fallbackPick,
          child: const Text(
            'A câmera não abre? Enviar foto',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

/// Recorta o filho num oval (proporção da referência).
class _OvalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromLTWH(0, 0, size.width, size.height));

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Desenha o "scrim" escuro fora do oval e o anel verde ao redor dele.
class _FaceRingPainter extends CustomPainter {
  final Color color;
  final bool glow;
  _FaceRingPainter({required this.color, this.glow = false});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ovalRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.86,
      height: size.height * 0.92,
    );

    // Escurece tudo fora do oval.
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha:0.45));

    // Brilho suave (quando ativo).
    if (glow) {
      canvas.drawOval(
        ovalRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..color = color.withValues(alpha:0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // Anel verde principal.
    canvas.drawOval(
      ovalRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_FaceRingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.glow != glow;
}
