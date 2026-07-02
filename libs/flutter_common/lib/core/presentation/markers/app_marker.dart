import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';

enum MarkerColor { blue, green }
enum MarkerIcon { location, locate }

class AppMarker extends StatelessWidget {
  final Widget title;
  final MarkerColor color;
  final MarkerIcon icon;
  final VoidCallback? onTap;

  const AppMarker({
    super.key,
    required this.title,
    this.color = MarkerColor.blue,   // azul = partida, verde = destino/parada
    this.icon = MarkerIcon.locate,  // locate = partida, location = destino/parada
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 1. Caixa branca principal (balão) ──────────────────────
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x2064748B), // sombra suave cinza
                  offset: Offset(0, 4),
                  blurRadius: 10,
                ),
              ],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12, width: 0.5),
            ),
            child: Row(
              children: [
                // Sem o ícone interno para liberar espaço e evitar overflow
                Expanded(child: title),
              ],
            ),
          ),
        ),
        // ── 2. Triângulo embaixo (ponteiro do balão apontando para a cabeça do pino) ──
        ClipPath(
          clipper: TriangleClipper(),
          child: Container(
            color: Colors.white,
            height: 8,
            width: 12,
          ),
        ),
        // ── 3. Cabeça do pino real no mapa (idêntico ao que estava no balão) ──
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
            border: Border.all(color: foregroundColor, width: 2.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            iconData,
            color: foregroundColor,
            size: 16,
          ),
        ),
        // ── 4. Haste vertical fina (a agulha do pino que encosta no mapa) ──
        Container(
          width: 2.5,
          height: 12,
          color: foregroundColor,
        ),
      ],
    );
  }

  // Cor do ícone e borda: azul para partida, ciano para destino/parada
  Color get foregroundColor => color == MarkerColor.green
      ? const Color(0xFF00E2C5)  // tertiary60 — ciano
      : const Color(0xFF096EFF); // primary50  — azul

  // Cor de fundo do ícone: mais clara que a foreground
  Color get backgroundColor => color == MarkerColor.green
      ? const Color(0xFFC0FFF8)  // tertiary95 — ciano claro
      : const Color(0xFFABCCFB); // primary80  — azul claro

  IconData get iconData =>
      icon == MarkerIcon.location ? Ionicons.location : Ionicons.locate;

  // Tamanho padrão do balão — usado ao criar CustomMarker
  static const double width = 240;
  static const double height = 150;
  static const Alignment alignment = Alignment.bottomCenter;

  static Widget buildBubbleContent(BuildContext context, String addressText, {VoidCallback? onTap}) {
    return Text(
      addressText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 13.0,
        fontWeight: FontWeight.w500,
        color: Colors.black87,
      ),
    );
  }
}

// Clipper do triângulo inferior do balão
class TriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(size.width, 0.0);
    path.lineTo(size.width / 2, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(TriangleClipper oldClipper) => false;
}
