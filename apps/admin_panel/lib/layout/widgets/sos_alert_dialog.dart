import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SosAlertDialog extends StatelessWidget {
  final Map<String, dynamic> sosData;
  final VoidCallback onResolveComplete;

  const SosAlertDialog({
    super.key,
    required this.sosData,
    required this.onResolveComplete,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.red.shade900,
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.white, size: 40),
          SizedBox(width: 16),
          Text('ALERTA DE SOS!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Um passageiro ou motorista acionou o botão de pânico!', style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 16),
          Text('ID da Corrida: ${sosData['ride_id'] ?? 'N/A'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          Text('Acionado por: ${sosData['submitted_by'] == 'driver' ? 'Motorista' : 'Passageiro'}', style: const TextStyle(color: Colors.white)),
          if (sosData['user_name'] != null)
            Text('Usuário: ${sosData['user_name']}', style: const TextStyle(color: Colors.white70)),
        ],
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.red.shade900,
          ),
          onPressed: () async {
            try {
              // Atualiza sos_alerts (tabela unificada)
              await Supabase.instance.client
                  .from('sos_alerts')
                  .update({'status': 'resolved'})
                  .eq('id', sosData['id']);
            } catch (e) {
              debugPrint('Erro ao resolver SOS: $e');
            }
            onResolveComplete();
          },
          child: const Text('MARCAR COMO RESOLVIDO'),
        )
      ],
    );
  }
}
