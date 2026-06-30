import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RideTrackingSharesScreen extends StatefulWidget {
  const RideTrackingSharesScreen({super.key});

  @override
  State<RideTrackingSharesScreen> createState() =>
      _RideTrackingSharesScreenState();
}

class _RideTrackingSharesScreenState extends State<RideTrackingSharesScreen> {
  final Map<String, Map<String, dynamic>> _profilesCache = {};

  // Resolve os dados de perfil (Nome/Papel) de forma preguiçosa com cache para evitar queries N+1
  Future<Map<String, dynamic>> _resolveCreatorProfile(String userId) async {
    if (_profilesCache.containsKey(userId)) {
      return _profilesCache[userId]!;
    }

    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('full_name, role')
          .eq('id', userId)
          .maybeSingle();

      if (res != null) {
        _profilesCache[userId] = Map<String, dynamic>.from(res);
        return _profilesCache[userId]!;
      }
    } catch (_) {
      // Ignora erro e retorna default
    }

    return {'full_name': 'Usuário Desconhecido', 'role': 'unknown'};
  }

  // Revoga (exclui) o token de compartilhamento no Supabase
  Future<void> _revokeShare(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            const SizedBox(width: 10),
            Text('Confirmar Revogação', style: GoogleFonts.outfit()),
          ],
        ),
        content: const Text(
          'Deseja realmente revogar e invalidar este link de compartilhamento de corrida? O rastreamento externo será encerrado imediatamente.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black),
            child: const Text('Revogar Link'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await Supabase.instance.client
          .from('ride_tracking_shares')
          .delete()
          .eq('id', id);

      _showSnackBar('Link de compartilhamento revogado com sucesso!', Colors.greenAccent);
    } catch (e) {
      _showSnackBar('Erro ao revogar link: $e', Colors.redAccent);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              const Icon(Icons.share_location_rounded, color: Colors.indigoAccent, size: 28),
              const SizedBox(width: 12),
              Text(
                'Compartilhamento de Rotas (Safe-Tracking)',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // Listagem em tempo real (Option B - Real-time Stream)
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('ride_tracking_shares')
                .stream(primaryKey: ['id'])
                .order('created_at', ascending: false),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Erro ao escutar compartilhamentos: ${snapshot.error}',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                );
              }

              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return const Center(
                  child: Text(
                    'Nenhuma rota compartilhada ativamente no momento.',
                    style: TextStyle(color: Colors.white38),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(32),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final createdBy = item['created_by']?.toString() ?? '';
                  final createdAt = DateTime.tryParse(item['created_at']?.toString() ?? '')?.toLocal();
                  final expiresAt = DateTime.tryParse(item['expires_at']?.toString() ?? '')?.toLocal();
                  final isExpired = expiresAt != null && now.isAfter(expiresAt);

                  return FutureBuilder<Map<String, dynamic>>(
                    future: _resolveCreatorProfile(createdBy),
                    builder: (context, profileSnapshot) {
                      final profile = profileSnapshot.data ?? {'full_name': 'Buscando...', 'role': ''};
                      final creatorName = profile['full_name'];
                      final creatorRole = profile['role'] == 'driver' ? 'Motorista' : 'Passageiro';

                      return Card(
                        color: Theme.of(context).colorScheme.surface.withAlpha(200),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              // Icone de Status
                              Icon(
                                isExpired ? Icons.link_off_rounded : Icons.link_rounded,
                                color: isExpired ? Colors.redAccent : Colors.greenAccent,
                                size: 36,
                              ),
                              const SizedBox(width: 16),

                              // Info do Link e Usuário
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          creatorName,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                        if (profile['role'] != '') ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.white10,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              creatorRole,
                                              style: const TextStyle(fontSize: 10, color: Colors.white70),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'ID da Corrida: ${item['ride_id']}',
                                      style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'monospace'),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Token: ${item['share_token']}',
                                      style: const TextStyle(color: Colors.tealAccent, fontSize: 12, fontFamily: 'monospace'),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        if (createdAt != null)
                                          Text(
                                            'Criado: ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                                          ),
                                        if (createdAt != null && expiresAt != null)
                                          const Text(' • ', style: TextStyle(color: Colors.white38, fontSize: 11)),
                                        if (expiresAt != null)
                                          Text(
                                            'Expira: ${expiresAt.hour.toString().padLeft(2, '0')}:${expiresAt.minute.toString().padLeft(2, '0')}',
                                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // Status Badge & Ações
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isExpired
                                          ? Colors.redAccent.withAlpha(40)
                                          : Colors.greenAccent.withAlpha(40),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      isExpired ? 'Expirado' : 'Ativo',
                                      style: TextStyle(
                                        color: isExpired ? Colors.redAccent : Colors.greenAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (!isExpired)
                                    IconButton(
                                      icon: const Icon(Icons.cancel_schedule_send_rounded, color: Colors.orangeAccent),
                                      tooltip: 'Revogar Link',
                                      onPressed: () => _revokeShare(item['id'].toString()),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
