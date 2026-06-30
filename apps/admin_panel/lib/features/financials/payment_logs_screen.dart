import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class PaymentLogsScreen extends StatefulWidget {
  const PaymentLogsScreen({super.key});

  @override
  State<PaymentLogsScreen> createState() => _PaymentLogsScreenState();
}

class _PaymentLogsScreenState extends State<PaymentLogsScreen> {
  String _searchQuery = '';
  List<Map<String, dynamic>> _allLogs = [];
  bool _isLoading = true;
  RealtimeChannel? _paymentsChannel;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
    _startRealtimeChannel();
  }

  void _startRealtimeChannel() {
    _paymentsChannel = Supabase.instance.client.channel('payments_monitor')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'mp_payments',
        callback: (payload) => _onDataChanged(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'pix_payments',
        callback: (payload) => _onDataChanged(),
      )
      .subscribe();
  }

  void _onDataChanged() {
    if (_debounceTimer?.isActive ?? false) return;
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) _fetchLogs(silent: true);
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _paymentsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchLogs({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final supa = Supabase.instance.client;
      final mpRes = await supa.from('mp_payments').select('*, rides(id), profiles:rider_id(full_name)').order('created_at', ascending: false).limit(200);
      final pixRes = await supa.from('pix_payments').select('*, rides(id), profiles:rider_id(full_name)').order('created_at', ascending: false).limit(200);

      final List<Map<String, dynamic>> combined = [];

      for (var p in mpRes) {
        combined.add({
          ...p,
          'gateway_type': 'Mercado Pago',
          'amount_val': p['transaction_amount'] ?? 0.0,
          'status_val': p['status'] ?? 'unknown',
          'external_id': p['mp_payment_id']?.toString() ?? p['id'],
        });
      }

      for (var p in pixRes) {
        combined.add({
          ...p,
          'gateway_type': 'PIX',
          'amount_val': p['amount'] ?? 0.0,
          'status_val': p['status'] ?? 'unknown',
          'external_id': p['mp_payment_id']?.toString() ?? p['id'],
        });
      }

      combined.sort((a, b) {
        final d1 = DateTime.tryParse(a['created_at'].toString()) ?? DateTime.now();
        final d2 = DateTime.tryParse(b['created_at'].toString()) ?? DateTime.now();
        return d2.compareTo(d1); // Descending
      });

      if (mounted) {
        setState(() {
          _allLogs = combined;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching payment logs: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> filteredLogs = _allLogs;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filteredLogs = _allLogs.where((l) {
        final extId = (l['external_id'] ?? '').toString().toLowerCase();
        final rider = (l['profiles']?['full_name'] ?? '').toString().toLowerCase();
        final rideId = (l['ride_id'] ?? '').toString().toLowerCase();
        return extId.contains(q) || rider.contains(q) || rideId.contains(q);
      }).toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Logs de Pagamento (Gateways)',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  SizedBox(
                    width: 300,
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Buscar ID, Ride ou Usuário...',
                        prefixIcon: const Icon(Icons.search),
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
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Atualizar',
                    onPressed: _fetchLogs,
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : filteredLogs.isEmpty
                  ? const Center(child: Text('Nenhum log encontrado.', style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(24),
                      itemCount: filteredLogs.length,
                      itemBuilder: (context, index) {
                        final log = filteredLogs[index];
                        final gateway = log['gateway_type'];
                        final amount = (log['amount_val'] as num).toDouble();
                        final status = log['status_val'].toString();
                        final dateStr = log['created_at'].toString();
                        final date = DateTime.tryParse(dateStr)?.toLocal();
                        final rideId = log['ride_id'];
                        final riderName = log['profiles']?['full_name'] ?? 'Usuário';

                        Color statusColor = Colors.grey;
                        if (status == 'approved' || status == 'paid') statusColor = Colors.green;
                        if (status == 'pending') statusColor = Colors.orange;
                        if (status == 'rejected' || status == 'cancelled' || status == 'cancelled_by_system') statusColor = Colors.red;

                        return Card(
                          color: Theme.of(context).colorScheme.surface.withAlpha(200),
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: gateway == 'PIX' ? Colors.teal.shade900 : Colors.blue.shade900,
                              child: Icon(
                                gateway == 'PIX' ? Icons.qr_code : Icons.credit_card,
                                color: gateway == 'PIX' ? Colors.tealAccent : Colors.blueAccent,
                                size: 20,
                              ),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  'R\$ ${amount.toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withAlpha(50),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: statusColor),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text('Passageiro: $riderName | Data: ${date.toString().substring(0, 16)}'),
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                color: Colors.black12,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Detalhes do Transação ($gateway)', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
                                    const SizedBox(height: 8),
                                    SelectableText('Internal ID: ${log['id']}'),
                                    SelectableText('External ID (Gateway): ${log['external_id']}'),
                                    SelectableText('Ride ID: ${rideId ?? 'N/A'}'),
                                    SelectableText('Rider ID: ${log['rider_id'] ?? 'N/A'}'),
                                    if (log['error_message'] != null) ...[
                                      const SizedBox(height: 8),
                                      const Text('Erro:', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                      SelectableText(log['error_message'].toString(), style: const TextStyle(color: Colors.red)),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
