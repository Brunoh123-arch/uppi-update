import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tela God Mode: Monitora TODAS as mensagens trocadas entre passageiros
/// e motoristas em todas as corridas. Permite busca por ride_id, moderação
/// de conteúdo e exclusão de mensagens ofensivas.
/// Inclui duas abas: ride_messages (Edge Functions) e messages (legacy).
class RideMessagesMonitorScreen extends StatefulWidget {
  const RideMessagesMonitorScreen({super.key});

  @override
  State<RideMessagesMonitorScreen> createState() =>
      _RideMessagesMonitorScreenState();
}

class _RideMessagesMonitorScreenState extends State<RideMessagesMonitorScreen> {
  String _filterRideId = '';
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  String? _error;

  // Cache de nomes para evitar N+1 queries
  final Map<String, String> _nameCache = {};

  RealtimeChannel? _messagesChannel;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    _startRealtimeChannel();
  }

  void _startRealtimeChannel() {
    _messagesChannel = Supabase.instance.client.channel('chat_monitor')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'ride_messages',
        callback: (payload) => _onDataChanged(),
      )
      .subscribe();
  }

  void _onDataChanged() {
    if (_debounceTimer?.isActive ?? false) return;
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        _fetchMessages(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _messagesChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchMessages({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      var query = Supabase.instance.client
          .from('ride_messages')
          .select('*')
          .order('created_at', ascending: false)
          .limit(200);

      if (_filterRideId.isNotEmpty) {
        query = Supabase.instance.client
            .from('ride_messages')
            .select('*')
            .eq('ride_id', _filterRideId)
            .order('created_at', ascending: true)
            .limit(500);
      }

      final data = await query;
      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
        // Pre-fetch names for senders
        _prefetchNames();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _prefetchNames() async {
    final senderIds = _messages
        .map((m) => m['sender_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty && !_nameCache.containsKey(id))
        .toSet()
        .toList();

    if (senderIds.isEmpty) return;

    try {
      // Fetch in batches of 50
      for (var i = 0; i < senderIds.length; i += 50) {
        final batch = senderIds.skip(i).take(50).toList();
        final profiles = await Supabase.instance.client
            .from('profiles')
            .select('id, full_name, role')
            .inFilter('id', batch);
        for (var p in profiles) {
          final role = p['role'] == 'driver' ? '🚗' : '👤';
          _nameCache[p['id']] =
              '$role ${p['full_name'] ?? 'Sem Nome'}';
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _deleteMessage(String messageId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Excluir Mensagem?'),
        content: const Text(
          'Isso removerá permanentemente a mensagem do histórico. '
          'Esta ação será registrada no audit log.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Supabase.instance.client
          .from('ride_messages')
          .delete()
          .eq('id', messageId);

      // Audit log
      final adminId =
          Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'ride_message_deleted',
        'target_resource_id': messageId,
        'details': {'reason': 'admin_moderation'},
      });

      _fetchMessages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mensagem excluída.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showConversationForRide(String rideId) {
    setState(() {
      _filterRideId = rideId;
    });
    _fetchMessages();
  }

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
              Text(
                'Monitor de Mensagens (Chat Corridas)',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Search by ride_id
              SizedBox(
                width: 300,
                child: TextField(
                  onSubmitted: (v) {
                    setState(() => _filterRideId = v.trim());
                    _fetchMessages();
                  },
                  decoration: InputDecoration(
                    hintText: 'Filtrar por ID da corrida...',
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
              if (_filterRideId.isNotEmpty) ...[
                const SizedBox(width: 12),
                ActionChip(
                  label: const Text('Limpar filtro'),
                  avatar: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    setState(() => _filterRideId = '');
                    _fetchMessages();
                  },
                ),
              ],
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.blueAccent),
                tooltip: 'Atualizar',
                onPressed: _fetchMessages,
              ),
            ],
          ),
        ),

        // Stats bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          color: const Color(0xFF1E293B),
          child: Row(
            children: [
              _StatChip(
                icon: Icons.message,
                label: '${_messages.length} mensagens',
                color: Colors.blueAccent,
              ),
              const SizedBox(width: 16),
              if (_filterRideId.isNotEmpty)
                _StatChip(
                  icon: Icons.filter_alt,
                  label: 'Corrida: ${_filterRideId.substring(0, _filterRideId.length > 8 ? 8 : _filterRideId.length)}...',
                  color: Colors.orangeAccent,
                ),
              const Spacer(),
              const Text(
                'God Mode: Visualização total de comunicações',
                style: TextStyle(color: Colors.white24, fontSize: 11),
              ),
            ],
          ),
        ),

        // Message List
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text('Erro: $_error',
                style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchMessages,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined, color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            Text(
              _filterRideId.isEmpty
                  ? 'Nenhuma mensagem encontrada.'
                  : 'Nenhuma mensagem para esta corrida.',
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // Group by ride_id if not filtered
    if (_filterRideId.isNotEmpty) {
      return _buildConversationView();
    }

    return _buildGlobalListView();
  }

  Widget _buildConversationView() {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final senderId = msg['sender_id']?.toString() ?? '';
        final senderName = _nameCache[senderId] ?? senderId.substring(0, senderId.length > 8 ? 8 : senderId.length);
        final content = msg['content']?.toString() ?? msg['message']?.toString() ?? '';
        final createdAt = msg['created_at']?.toString().substring(0, 16) ?? '';
        final isDriver = senderName.startsWith('🚗');

        return Align(
          alignment: isDriver ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.5,
            ),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDriver
                  ? Colors.indigo.withOpacity(0.3)
                  : Colors.teal.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDriver
                    ? Colors.indigo.withOpacity(0.4)
                    : Colors.teal.withOpacity(0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      senderName,
                      style: TextStyle(
                        color: isDriver ? Colors.indigoAccent : Colors.tealAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      createdAt,
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => _deleteMessage(msg['id'].toString()),
                      child: const Icon(Icons.delete_outline,
                          color: Colors.redAccent, size: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  content,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlobalListView() {
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: _messages.length,
      separatorBuilder: (_, __) => const Divider(color: Colors.white10),
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final rideId = msg['ride_id']?.toString() ?? '';
        final senderId = msg['sender_id']?.toString() ?? '';
        final senderName = _nameCache[senderId] ??
            (senderId.length > 8 ? senderId.substring(0, 8) : senderId);
        final content = msg['content']?.toString() ?? msg['message']?.toString() ?? '';
        final createdAt = msg['created_at']?.toString().substring(0, 16) ?? '';

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.blueAccent.withOpacity(0.15),
            child: const Icon(Icons.chat_bubble_outline,
                color: Colors.blueAccent, size: 20),
          ),
          title: Text(
            content.length > 100 ? '${content.substring(0, 100)}...' : content,
            style: const TextStyle(color: Colors.white),
          ),
          subtitle: Text(
            'De: $senderName | Corrida: ${rideId.length > 8 ? rideId.substring(0, 8) : rideId}... | $createdAt',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.visibility, color: Colors.blueAccent, size: 18),
                tooltip: 'Ver conversa completa',
                onPressed: () => _showConversationForRide(rideId),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                tooltip: 'Excluir mensagem',
                onPressed: () => _deleteMessage(msg['id'].toString()),
              ),
            ],
          ),
        );
      },
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
                  color: color, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}
