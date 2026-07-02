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
        // ── Caixa branca principal (balão) ──────────────────────
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: width,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1464748B), // sombra suave cinza
                  offset: Offset(2, 4),
                  blurRadius: 8,
                ),
              ],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // ── Ícone com borda e fundo colorido ──────────────
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(color: foregroundColor),
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: foregroundColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      iconData,
                      color: const Color(0xFFFDFCFF), // branco puro
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // ── Texto do título/endereço ────────────────────
                Expanded(child: title),
              ],
            ),
          ),
        ),
        // ── Triângulo embaixo (ponteiro do balão) ───────────────
        ClipPath(
          clipper: TriangleClipper(),
          child: Container(
            color: Colors.white,
            height: 11,
            width: 16,
          ),
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
  static const double height = 67;
  static const Alignment alignment = Alignment.topCenter;

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
