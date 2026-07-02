import 'package:flutter/material.dart';
import 'package:generic_map/generic_map.dart';

class CurrentLocationMarker extends StatelessWidget {
  const CurrentLocationMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF096EFF).withOpacity(0.10), // anel externo
        shape: BoxShape.circle,
      ),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF096EFF).withOpacity(0.30), // anel médio
          shape: BoxShape.circle,
        ),
        child: Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: const Color(0xFF2090FF), // primary60 — ponto central azul
            border: Border.all(color: Colors.white, width: 1.5),
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(blurRadius: 20, spreadRadius: 0),
            ],
          ),
        ),
      ),
    );
  }

  // Marcador central — tamanho 55x55, alinhamento central
  CenterMarker get marker => CenterMarker(
        widget: this,
        size: const Size(55, 55),
        alignment: Alignment.center,
      );
}
