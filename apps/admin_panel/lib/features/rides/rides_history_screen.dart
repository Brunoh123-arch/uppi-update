import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher_string.dart';

class RidesHistoryScreen extends StatefulWidget {
  const RidesHistoryScreen({super.key});

  @override
  State<RidesHistoryScreen> createState() => _RidesHistoryScreenState();
}

class _RidesHistoryScreenState extends State<RidesHistoryScreen> {
  String _statusFilter = 'Todos';

  final List<String> _statuses = [
    'Todos',
    'scheduled',
    'requested',
    'accepted',
    'arrived',
    'in_progress',
    'completed',
    'rider_canceled',
    'driver_canceled',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Premium Header
        Container(
          height: 80,
          padding: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Mural de Corridas (Tempo Real)',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              DropdownButton<String>(
                value: _statusFilter,
                dropdownColor: Theme.of(context).colorScheme.surface,
                underline: const SizedBox(),
                items: _statuses
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _statusFilter = val);
                },
              ),
            ],
          ),
        ),

        // Orders List
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _buildStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Erro ao carregar dados: ${snapshot.error}',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                );
              }

              final orders = snapshot.data ?? [];

              if (orders.isEmpty) {
                return const Center(
                  child: Text(
                    'Nenhuma corrida encontrada para o filtro.',
                    style: TextStyle(color: Colors.white54),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(32),
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final order = orders[index];
                  final status = order['status'] ?? 'Desconhecido';
                  final riderId = order['rider_id'] ?? 'N/A';
                  final driverId = order['driver_id'] ?? 'Aguardando Motorista';
                  final price =
                      (order['fare'] as num?)?.toDouble() ?? 0.0;
                  final distance =
                      (order['distance_meters'] as num?)?.toDouble() ?? 0.0;
                  final duration =
                      (order['duration_seconds'] as num?)?.toDouble() ?? 0.0;

                  // Detalhes do cancelamento
                  final cancelReason = order['cancel_reason_note'];

                  Color statusColor = Colors.white54;
                  if (status == 'completed') statusColor = Colors.greenAccent;
                  if (status == 'rider_canceled' || status == 'driver_canceled') {
                    statusColor = Colors.redAccent;
                  }
                  if (status == 'in_progress') statusColor = Colors.blueAccent;
                  if (status == 'accepted') {
                    statusColor = Colors.orangeAccent;
                  }

                  return Card(
                    color: Theme.of(context).colorScheme.surface,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              _getIconForStatus(status),
                              color: statusColor,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Corrida ID: ${order['id'].toString().substring(0, 8)}...',
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Passageiro: $riderId',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                Text(
                                  'Motorista: $driverId',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                if (status == 'scheduled' && order['expected_at'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Agendado para: ${DateTime.parse(order['expected_at'].toString()).toLocal().toString().substring(0, 16)}',
                                      style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Distância & Tempo',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  '${(distance / 1000).toStringAsFixed(1)} km',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${(duration / 60).toStringAsFixed(0)} min',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Valor',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  'R\$ ${price.toStringAsFixed(2)}',
                                  style: GoogleFonts.outfit(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.greenAccent,
                                  ),
                                ),
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (cancelReason != null)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text(
                                    'Motivo Cancel.',
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    cancelReason
                                        .toString(), // Idealmente faríamos join com a tabela cancel_reasons
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(width: 16),
                          IconButton(
                            icon: const Icon(Icons.map_rounded),
                            tooltip: 'Ver Rota no Mapa',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) =>
                                    _RideDetailsDialog(ride: order),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Stream<List<Map<String, dynamic>>> _buildStream() {
    if (_statusFilter != 'Todos') {
      return Supabase.instance.client
          .from('rides')
          .stream(primaryKey: ['id'])
          .eq('status', _statusFilter)
          .order('created_at', ascending: false)
          .limit(100);
    }
    return Supabase.instance.client
        .from('rides')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(100);
  }

  IconData _getIconForStatus(String status) {
    switch (status) {
      case 'requested':
        return Icons.search;
      case 'accepted':
        return Icons.directions_car;
      case 'arrived':
        return Icons.location_on;
      case 'in_progress':
        return Icons.play_arrow;
      case 'completed':
        return Icons.check_circle;
      case 'rider_canceled':
      case 'driver_canceled':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }
}

class _RideDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> ride;
  const _RideDetailsDialog({required this.ride});

  Future<List<Map<String, dynamic>>> _fetchTimeline() async {
    try {
      final res = await Supabase.instance.client
          .from('ride_activities')
          .select()
          .eq('ride_id', ride['id'])
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Erro ao buscar timeline: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ride['status'] ?? 'Unknown';
    final dist = (ride['distance_meters'] as num?)?.toDouble() ?? 0.0;
    final dur = (ride['duration_seconds'] as num?)?.toDouble() ?? 0.0;
    final price = (ride['fare'] as num?)?.toDouble() ?? 0.0;

    // Check if origin/destination exist and have coordinates
    final origin = ride['origin'];
    final dest = ride['destination'];

    String? mapUrl;
    if (origin != null &&
        dest != null &&
        origin['lat'] != null &&
        dest['lat'] != null) {
      final oLat = origin['lat'];
      final oLng = origin['lng'];
      final dLat = dest['lat'];
      final dLng = dest['lng'];
      mapUrl =
          'https://www.google.com/maps/dir/?api=1&origin=$oLat,$oLng&destination=$dLat,$dLng';
    }

    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 600,
        height: 800,
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Detalhes da Corrida',
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: Colors.white10, height: 32),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow('ID', ride['id'].toString()),
                    _InfoRow('Status', status),
                    _InfoRow('Distância', '${(dist / 1000).toStringAsFixed(2)} km'),
                    _InfoRow(
                      'Duração Estimada',
                      '${(dur / 60).toStringAsFixed(0)} mins',
                    ),
                    _InfoRow('Valor Final', 'R\$ ${price.toStringAsFixed(2)}'),

                    if (ride['cancel_reason_note'] != null)
                      _InfoRow(
                        'Motivo Cancelamento',
                        ride['cancel_reason_note'].toString(),
                      ),

                    const SizedBox(height: 16),

                    // Origin / Destination addresses
                    if (origin != null || dest != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          children: [
                            if (origin != null)
                              Row(
                                children: [
                                  const Icon(Icons.trip_origin,
                                      color: Colors.greenAccent, size: 18),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Origem',
                                            style: TextStyle(
                                                color: Colors.white38, fontSize: 11)),
                                        Text(
                                          origin['address']?.toString() ??
                                              '${origin['lat']}, ${origin['lng']}',
                                          style: const TextStyle(
                                              color: Colors.white, fontSize: 13),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            if (origin != null && dest != null)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Icon(Icons.more_vert,
                                      color: Colors.white24, size: 20),
                                ),
                              ),
                            if (dest != null)
                              Row(
                                children: [
                                  const Icon(Icons.location_on,
                                      color: Colors.redAccent, size: 18),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Destino',
                                            style: TextStyle(
                                                color: Colors.white38, fontSize: 11)),
                                        Text(
                                          dest['address']?.toString() ??
                                              '${dest['lat']}, ${dest['lng']}',
                                          style: const TextStyle(
                                              color: Colors.white, fontSize: 13),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (mapUrl != null)
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () => launchUrlString(mapUrl!),
                          icon: const Icon(Icons.map),
                          label: const Text(
                            'Ver Rota no Google Maps',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      )
                    else
                      const Center(
                        child: Text(
                          'Coordenadas indisponíveis para o mapa.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),

                    const SizedBox(height: 32),
                    Text(
                      'Auditoria: Linha do Tempo',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 16),

                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _fetchTimeline(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator(strokeWidth: 2));
                        }
                        if (snapshot.hasError) {
                          return Text('Erro: ${snapshot.error}',
                              style: const TextStyle(color: Colors.redAccent));
                        }
                        
                        final activities = snapshot.data ?? [];
                        if (activities.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.history, color: Colors.white38),
                                SizedBox(width: 12),
                                Text(
                                  'Nenhum registro de atividade encontrado.',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: activities.length,
                          itemBuilder: (context, index) {
                            final act = activities[index];
                            final actType = act['type'] ?? 'unknown';
                            final createdAt = act['created_at'] != null 
                              ? DateTime.parse(act['created_at'].toString()).toLocal()
                              : null;
                              
                            final timeStr = createdAt != null 
                              ? '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}:${createdAt.second.toString().padLeft(2, '0')}'
                              : '--:--:--';
                              
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 16,
                                    height: 16,
                                    margin: const EdgeInsets.only(top: 4, right: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.blueAccent,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: const Color(0xFF1E293B), width: 3),
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.white10),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                actType.toString().toUpperCase(),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              Text(
                                                timeStr,
                                                style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (act['data'] != null && act['data'].toString() != '{}')
                                            Padding(
                                              padding: const EdgeInsets.only(top: 8),
                                              child: Text(
                                                act['data'].toString(),
                                                style: const TextStyle(
                                                  color: Colors.orangeAccent,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
