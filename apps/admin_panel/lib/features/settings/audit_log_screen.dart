import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});
  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  String _actionFilter = 'Todos';
  DateTimeRange? _selectedDateRange;
  final List<Map<String, dynamic>> _logs = [];
  int _page = 0;
  bool _hasMore = true;
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();

  RealtimeChannel? _auditChannel;
  Timer? _debounceTimer;

  final List<String> _actionsList = [
    'Todos',
    'payout',
    'wallet_adjustment',
    'admin_created',
    'admin_updated',
    'admin_deleted',
    'driver_status_change',
    'rider_blocked',
    'rider_unblocked',
    'complaint_resolved',
    'driver_warning'
  ];

  Color _actionColor(String action) {
    if (action.contains('delete') || action.contains('rejected')) return Colors.redAccent;
    if (action.contains('approved') || action.contains('resolved') || action.contains('created')) return Colors.greenAccent;
    if (action.contains('updated') || action.contains('config')) return Colors.amber;
    if (action.contains('sos')) return Colors.red;
    if (action.contains('payout')) return Colors.tealAccent;
    return Colors.blueAccent;
  }

  IconData _actionIcon(String action) {
    if (action.contains('sos')) return Icons.sos;
    if (action.contains('payout')) return Icons.account_balance_wallet;
    if (action.contains('driver')) return Icons.drive_eta;
    if (action.contains('admin')) return Icons.admin_panel_settings;
    if (action.contains('config') || action.contains('setting')) return Icons.settings;
    if (action.contains('complaint')) return Icons.support_agent;
    if (action.contains('cancel_reason')) return Icons.cancel;
    if (action.contains('review')) return Icons.star;
    return Icons.history;
  }

  @override
  void initState() {
    super.initState();
    _loadMoreLogs(reset: true);
    _startRealtimeChannel();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        _loadMoreLogs();
      }
    });
  }

  void _startRealtimeChannel() {
    final client = Supabase.instance.client;
    _auditChannel = client.channel('audit_log_realtime')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'admin_audit_log',
        callback: (payload) => _onRealtimeChange(),
      )
      .subscribe();
  }

  void _onRealtimeChange() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        _loadMoreLogs(reset: true);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _debounceTimer?.cancel();
    _auditChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadMoreLogs({bool reset = false}) async {
    if (_isLoading) return;
    if (reset) {
      _page = 0;
      _hasMore = true;
      _logs.clear();
    }
    if (!_hasMore && !reset) return;

    setState(() => _isLoading = true);

    try {
      const pageSize = 50;
      final from = _page * pageSize;
      final to = from + pageSize - 1;

      var query = Supabase.instance.client
          .from('admin_audit_log')
          .select();

      if (_actionFilter != 'Todos') {
        query = query.eq('action_type', _actionFilter);
      }

      if (_selectedDateRange != null) {
        final startIso = _selectedDateRange!.start.toUtc().toIso8601String();
        final endIso = _selectedDateRange!.end.add(const Duration(days: 1)).toUtc().toIso8601String();
        query = query.gte('created_at', startIso).lte('created_at', endIso);
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(from, to);

      if (mounted) {
        setState(() {
          _logs.addAll(List<Map<String, dynamic>>.from(data));
          _page++;
          _hasMore = data.length == pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao buscar logs: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(32, 20, 32, 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: const Border(bottom: BorderSide(color: Colors.white10)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            const Icon(Icons.policy, color: Colors.indigoAccent, size: 28),
            const SizedBox(width: 12),
            Text('Registro de Auditoria', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: Icon(Icons.date_range, color: _selectedDateRange != null ? Colors.indigoAccent : Colors.white54),
              tooltip: 'Filtrar por período',
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2025),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                  initialDateRange: _selectedDateRange,
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: ColorScheme.dark(
                          primary: Colors.indigo,
                          onPrimary: Colors.white,
                          surface: Theme.of(context).colorScheme.surface,
                          onSurface: Colors.white,
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (picked != null) {
                  setState(() => _selectedDateRange = picked);
                  _loadMoreLogs(reset: true);
                }
              },
            ),
            if (_selectedDateRange != null)
              IconButton(
                icon: const Icon(Icons.clear, color: Colors.redAccent),
                tooltip: 'Limpar período',
                onPressed: () {
                  setState(() => _selectedDateRange = null);
                  _loadMoreLogs(reset: true);
                },
              ),
            const SizedBox(width: 16),
            DropdownButton<String>(
              value: _actionFilter,
              dropdownColor: Theme.of(context).colorScheme.surface,
              underline: const SizedBox(),
              items: _actionsList.map((a) => DropdownMenuItem(value: a, child: Text(a, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _actionFilter = v);
                  _loadMoreLogs(reset: true);
                }
              },
            ),
          ],
        ),
      ),
      Expanded(
        child: _logs.isEmpty && !_isLoading
            ? const Center(child: Text('Nenhum registro encontrado.', style: TextStyle(color: Colors.white54)))
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                itemCount: _logs.length + (_hasMore ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i == _logs.length) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  final log = _logs[i];
                  final action = log['action_type']?.toString() ?? '';
                  final c = _actionColor(action);
                  final time = log['created_at'] != null
                      ? DateTime.tryParse(log['created_at'].toString())?.toLocal().toString().substring(0, 19) ?? '' : '';
                  final details = log['details']?.toString() ?? '';

                  return Card(
                    color: Theme.of(context).colorScheme.surface.withAlpha(200),
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      dense: true,
                      leading: Icon(_actionIcon(action), color: c, size: 24),
                      title: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: c.withAlpha(30), borderRadius: BorderRadius.circular(6)),
                          child: Text(action, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Text(time, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ]),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Admin: ${log['admin_id']?.toString().substring(0, 12) ?? '?'}...', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          if (log['target_user_id'] != null)
                            Text('Alvo (user): ${log['target_user_id']}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          if (log['target_resource_id'] != null)
                            Text('Recurso: ${log['target_resource_id']}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          if (details.isNotEmpty && details != 'null')
                            Text('Detalhes: ${details.length > 120 ? '${details.substring(0, 120)}...' : details}',
                                style: const TextStyle(color: Colors.white24, fontSize: 11)),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
