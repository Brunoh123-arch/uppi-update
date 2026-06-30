import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tela God Mode: Gerencia TODAS as corridas agendadas (status = 'booked')
/// dos passageiros. Permite visualizar, cancelar ou reatribuir corridas
/// programadas. Crítico para operação — passageiros agendam corridas com
/// antecedência e o admin precisa ter visibilidade total.
class ScheduledRidesScreen extends StatefulWidget {
  const ScheduledRidesScreen({super.key});

  @override
  State<ScheduledRidesScreen> createState() => _ScheduledRidesScreenState();
}

class _ScheduledRidesScreenState extends State<ScheduledRidesScreen> {
  String _filterStatus = 'booked';
  String _searchQuery = '';

  final List<String> _statusOptions = ['booked', 'all', 'rider_canceled', 'driver_canceled'];

  @override
  Widget build(BuildContext context) {
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Corridas Agendadas',
                    style: GoogleFonts.outfit(
                        fontSize: 28, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Passageiros que agendaram corridas com antecedência (status: booked)',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
              const Spacer(),
              // Status filter
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: DropdownButton<String>(
                  value: _filterStatus,
                  underline: const SizedBox(),
                  dropdownColor: const Color(0xFF1E293B),
                  items: _statusOptions.map((s) {
                    return DropdownMenuItem(
                      value: s,
                      child: Text(
                        s == 'all' ? 'Todos os Status' : s.toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _filterStatus = v);
                  },
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 260,
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar por passageiro ou endereço...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    filled: true,
                    fillColor: Colors.black12,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _buildStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Erro: ${snapshot.error}',
                      style: const TextStyle(color: Colors.redAccent)),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              var rides = snapshot.data!;

              // Client-side search
              if (_searchQuery.isNotEmpty) {
                final q = _searchQuery.toLowerCase();
                rides = rides.where((r) {
                  final pickup = (r['pickup_address'] ?? '').toString().toLowerCase();
                  final dropoff = (r['dropoff_address'] ?? '').toString().toLowerCase();
                  final riderId = (r['rider_id'] ?? '').toString().toLowerCase();
                  return pickup.contains(q) ||
                      dropoff.contains(q) ||
                      riderId.contains(q);
                }).toList();
              }

              if (rides.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_available_outlined,
                          color: Colors.white24, size: 80),
                      const SizedBox(height: 20),
                      Text(
                        _filterStatus == 'booked'
                            ? 'Nenhuma corrida agendada pendente.'
                            : 'Nenhuma corrida encontrada.',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 18),
                      ),
                    ],
                  ),
                );
              }

              // Stats
              final bookedCount =
                  rides.where((r) => r['status'] == 'booked').length;

              return Column(
                children: [
                  // Stats bar
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 12),
                    color: const Color(0xFF1E293B),
                    child: Row(
                      children: [
                        _StatChip(
                          icon: Icons.schedule,
                          label: '$bookedCount agendadas',
                          color: Colors.amberAccent,
                        ),
                        const SizedBox(width: 16),
                        _StatChip(
                          icon: Icons.list,
                          label: '${rides.length} total',
                          color: Colors.blueAccent,
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(24),
                      itemCount: rides.length,
                      itemBuilder: (context, index) {
                        return _buildRideCard(context, rides[index]);
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Stream<List<Map<String, dynamic>>> _buildStream() {
    if (_filterStatus == 'all') {
      return Supabase.instance.client
          .from('rides')
          .stream(primaryKey: ['id'])
          .inFilter('status', ['booked', 'rider_canceled', 'driver_canceled'])
          .order('expected_at', ascending: true);
    }
    return Supabase.instance.client
        .from('rides')
        .stream(primaryKey: ['id'])
        .eq('status', _filterStatus)
        .order('expected_at', ascending: true);
  }

  Widget _buildRideCard(
      BuildContext context, Map<String, dynamic> ride) {
    final rideId = ride['id']?.toString() ?? '';
    final riderId = ride['rider_id']?.toString() ?? '';
    final status = ride['status']?.toString() ?? '';
    final pickupAddress =
        ride['pickup_address']?.toString() ?? 'Endereço não informado';
    final dropoffAddress =
        ride['dropoff_address']?.toString() ?? 'Destino não informado';
    final expectedAt = ride['expected_at']?.toString() ?? '';
    final fare = (ride['fare'] as num?)?.toDouble() ?? 0.0;
    final createdAt = ride['created_at']?.toString().substring(0, 16) ?? '';

    // Format expected_at
    String expectedFormatted = expectedAt;
    if (expectedAt.length >= 16) {
      expectedFormatted = expectedAt.substring(0, 16).replaceAll('T', ' ');
    }

    final isBooked = status == 'booked';

    return Card(
      color:
          Theme.of(context).colorScheme.surface.withAlpha(220),
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isBooked
              ? Colors.amberAccent.withOpacity(0.3)
              : Colors.white10,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: status + time + fare
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isBooked
                        ? Colors.amber.withOpacity(0.15)
                        : Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isBooked
                          ? Colors.amberAccent.withOpacity(0.4)
                          : Colors.redAccent.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isBooked ? Icons.schedule : Icons.cancel_outlined,
                        color: isBooked
                            ? Colors.amberAccent
                            : Colors.redAccent,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          color: isBooked
                              ? Colors.amberAccent
                              : Colors.redAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (expectedFormatted.isNotEmpty) ...[
                  const Icon(Icons.access_time,
                      color: Colors.white38, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Agendado: $expectedFormatted',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12),
                  ),
                ],
                const Spacer(),
                Text(
                  'R\$ ${fare.toStringAsFixed(2)}',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.greenAccent,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(color: Colors.white10),
            const SizedBox(height: 12),

            // Route
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    const Icon(Icons.circle,
                        color: Colors.greenAccent, size: 12),
                    Container(
                      width: 2,
                      height: 24,
                      color: Colors.white24,
                    ),
                    const Icon(Icons.location_on,
                        color: Colors.redAccent, size: 14),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pickupAddress,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        dropoffAddress,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(color: Colors.white10),
            const SizedBox(height: 8),

            // Bottom: passenger info + actions
            Row(
              children: [
                // Passenger info
                FutureBuilder(
                  future: Supabase.instance.client
                      .from('profiles')
                      .select('full_name, phone_number, avatar_url')
                      .eq('id', riderId)
                      .maybeSingle(),
                  builder:
                      (ctx, AsyncSnapshot<Map<String, dynamic>?> snap) {
                    final name =
                        snap.data?['full_name'] ?? 'Passageiro';
                    final phone =
                        snap.data?['phone_number'] ?? '';
                    return Row(
                      children: [
                        const Icon(Icons.person,
                            color: Colors.blueAccent, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600),
                        ),
                        if (phone.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            '| $phone',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const Spacer(),
                Text(
                  'Criado: $createdAt',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(width: 16),
                // Actions
                if (isBooked) ...[
                  ElevatedButton.icon(
                    onPressed: () =>
                        _cancelScheduledRide(context, rideId),
                    icon: const Icon(Icons.cancel_outlined, size: 14),
                    label: const Text('Cancelar Corrida',
                        style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withOpacity(0.2),
                      foregroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () =>
                      _showRideDetails(context, ride),
                  child: const Text('Detalhes',
                      style: TextStyle(
                          color: Colors.blueAccent, fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancelScheduledRide(
      BuildContext context, String rideId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Cancelar Corrida Agendada?'),
        content: const Text(
            'Esta ação cancelará a corrida agendada. '
            'O passageiro será notificado. Esta ação será auditada.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar Cancelamento'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Supabase.instance.client
          .from('rides')
          .update({'status': 'rider_canceled', 'cancel_reason_note': 'Cancelado pelo Admin'}).eq('id', rideId);

      final adminId =
          Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'scheduled_ride_cancelled',
        'target_resource_id': rideId,
        'details': {'reason': 'admin_action'},
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Corrida agendada cancelada com sucesso.'),
              backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showRideDetails(
      BuildContext context, Map<String, dynamic> ride) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Detalhes da Corrida Agendada'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: ride.entries
                .where((e) => e.value != null)
                .map((e) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 160,
                          child: Text(
                            e.key,
                            style: const TextStyle(
                                color: Colors.white38,
                                fontFamily: 'monospace',
                                fontSize: 11),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            e.value.toString(),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12)),
        ],
      ),
    );
  }
}
