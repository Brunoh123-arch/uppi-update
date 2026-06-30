import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class RidersManagementScreen extends StatefulWidget {
  const RidersManagementScreen({super.key});

  @override
  State<RidersManagementScreen> createState() => _RidersManagementScreenState();
}

class _RidersManagementScreenState extends State<RidersManagementScreen> {
  String _searchQuery = '';
  final List<Map<String, dynamic>> _riders = [];
  int _page = 0;
  bool _hasMore = true;
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  RealtimeChannel? _profilesChannel;

  @override
  void initState() {
    super.initState();
    _loadMoreRiders(reset: true);
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        _loadMoreRiders();
      }
    });
    _startRealtimeListener();
  }

  void _startRealtimeListener() {
    _profilesChannel = Supabase.instance.client
        .channel('riders_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          callback: (payload) {
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;
            final eventType = payload.eventType;

            if (!mounted) return;

            final record = eventType == PostgresChangeEvent.delete ? oldRecord : newRecord;
            if (record['role'] != 'rider') return;

            setState(() {
              if (eventType == PostgresChangeEvent.insert) {
                if (_matchesSearch(newRecord)) {
                  final exists = _riders.any((r) => r['id'] == newRecord['id']);
                  if (!exists) {
                    _riders.insert(0, newRecord);
                  }
                }
              } else if (eventType == PostgresChangeEvent.update) {
                final index = _riders.indexWhere((r) => r['id'] == newRecord['id']);
                if (index != -1) {
                  if (_matchesSearch(newRecord)) {
                    _riders[index] = newRecord;
                  } else {
                    _riders.removeAt(index);
                  }
                } else if (_matchesSearch(newRecord)) {
                  _riders.insert(0, newRecord);
                }
              } else if (eventType == PostgresChangeEvent.delete) {
                _riders.removeWhere((r) => r['id'] == oldRecord['id']);
              }
            });
          },
        )
        .subscribe();
  }

  bool _matchesSearch(Map<String, dynamic> record) {
    if (_searchQuery.isEmpty) return true;
    final name = (record['full_name'] ?? '').toString().toLowerCase();
    final phone = (record['phone_number'] ?? '').toString().toLowerCase();
    final email = (record['email'] ?? '').toString().toLowerCase();
    final q = _searchQuery.toLowerCase();
    return name.contains(q) || phone.contains(q) || email.contains(q);
  }

  @override
  void dispose() {
    _profilesChannel?.unsubscribe();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadMoreRiders({bool reset = false}) async {
    if (_isLoading) return;
    if (reset) {
      _page = 0;
      _hasMore = true;
      _riders.clear();
    }
    if (!_hasMore) return;

    setState(() => _isLoading = true);

    try {
      const pageSize = 50;
      final from = _page * pageSize;
      final to = from + pageSize - 1;

      var query = Supabase.instance.client
          .from('profiles')
          .select()
          .eq('role', 'rider');

      if (_searchQuery.isNotEmpty) {
        query = query.or('full_name.ilike.%$_searchQuery%,phone_number.ilike.%$_searchQuery%,email.ilike.%$_searchQuery%');
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(from, to);

      if (mounted) {
        setState(() {
          _riders.addAll(List<Map<String, dynamic>>.from(data));
          _page++;
          _hasMore = data.length == pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao buscar passageiros: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 600), () {
      _searchQuery = query.trim();
      _loadMoreRiders(reset: true);
    });
  }

  Future<void> _toggleRiderStatus(Map<String, dynamic> rider, bool isActive) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isActive ? 'Bloquear Passageiro?' : 'Desbloquear Passageiro?'),
        content: Text(
          'Deseja realmente ${isActive ? "bloquear" : "desbloquear"} o passageiro "${rider['full_name'] ?? 'Sem nome'}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive ? Colors.red : Colors.green,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final newStatus = isActive ? 'blocked' : 'active';
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'status': newStatus})
          .eq('id', rider['id']);
      
      // Audit trail
      final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': isActive ? 'rider_blocked' : 'rider_unblocked',
        'target_user_id': rider['id'],
        'details': {
          'rider_name': rider['full_name'],
          'new_status': newStatus,
        },
      });

      if (mounted) {
        setState(() {
          final index = _riders.indexWhere((r) => r['id'] == rider['id']);
          if (index != -1) {
            _riders[index]['status'] = newStatus;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isActive
                  ? 'Passageiro bloqueado com sucesso.'
                  : 'Passageiro desbloqueado com sucesso.',
            ),
            backgroundColor: isActive ? Colors.red : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                'Gestão de Passageiros',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(
                width: 300,
                child: TextField(
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Buscar passageiro...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.black12,
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
        Expanded(
          child: _riders.isEmpty && !_isLoading
              ? const Center(
                  child: Text('Nenhum passageiro encontrado.'),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(32),
                  itemCount: _riders.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _riders.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final rider = _riders[index];
                    final isActive = rider['status'] == 'active' || rider['status'] == null;
                    return Card(
                      color: Theme.of(context).colorScheme.surface,
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: isActive
                              ? Colors.blue.withOpacity(0.2)
                              : Colors.red.withOpacity(0.2),
                          backgroundImage: rider['avatar_url'] != null && (rider['avatar_url'] as String).isNotEmpty
                              ? NetworkImage(rider['avatar_url'] as String)
                              : null,
                          child: rider['avatar_url'] == null || (rider['avatar_url'] as String).isEmpty
                              ? Icon(
                                  Icons.person,
                                  color: isActive
                                      ? Colors.blueAccent
                                      : Colors.redAccent,
                                )
                              : null,
                        ),
                        title: Text(
                          (rider['full_name'] ?? 'Sem nome').toString().trim(),
                        ),
                        subtitle: Text(
                          'Celular: ${rider['phone_number'] ?? 'N/A'}\nStatus: ${rider['status'] ?? 'active'}',
                        ),
                        isThreeLine: true,
                        trailing: ElevatedButton(
                          onPressed: () => _toggleRiderStatus(rider, isActive),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isActive
                                ? Colors.redAccent.withOpacity(0.1)
                                : Colors.greenAccent.withOpacity(0.1),
                            foregroundColor: isActive
                                ? Colors.redAccent
                                : Colors.greenAccent,
                          ),
                          child: Text(isActive ? 'Bloquear' : 'Desbloquear'),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
