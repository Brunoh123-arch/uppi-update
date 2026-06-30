import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class SosManagementScreen extends StatefulWidget {
  const SosManagementScreen({super.key});
  @override
  State<SosManagementScreen> createState() => _SosManagementScreenState();
}

class _SosManagementScreenState extends State<SosManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _filter = 'Todos';

  // Variáveis para gerenciar o SOS selecionado
  Map<String, dynamic>? _selectedAlert;
  RealtimeChannel? _chatRealtimeChannel;
  List<Map<String, dynamic>> _sosMessages = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chatRealtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _startChatRefresher(String rideId) {
    _chatRealtimeChannel?.unsubscribe();
    _fetchSosChat(rideId);
    
    _chatRealtimeChannel = Supabase.instance.client
        .channel('public:ride_messages_sos')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ride_messages',
          callback: (payload) {
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;
            final rId = (newRecord['ride_id'] ?? oldRecord['ride_id'])?.toString();
            if (rId == rideId) {
              _fetchSosChat(rideId);
            }
          },
        );
    _chatRealtimeChannel!.subscribe();
  }

  Future<void> _fetchSosChat(String rideId) async {
    if (!mounted || _selectedAlert == null) return;
    try {
      final response = await Supabase.instance.client
          .rpc('rpc_get_sos_chat_context', params: {'p_ride_id': rideId});

      if (response != null && mounted) {
        setState(() {
          _sosMessages = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error fetching SOS chat: $e');
    }
  }

  void _closeCrisisPanel() {
    _chatRealtimeChannel?.unsubscribe();
    _chatRealtimeChannel = null;
    setState(() {
      _selectedAlert = null;
      _sosMessages = [];
    });
  }

  Color _sColor(BuildContext context, String s) {
    if (s == 'active') return Theme.of(context).colorScheme.error;
    if (s == 'resolved') return Theme.of(context).colorScheme.tertiary;
    return Theme.of(context).colorScheme.secondary;
  }

  void _resolve(Map<String, dynamic> a, String st) async {
    // Toda resolução agora é na tabela sos_alerts unificada
    await Supabase.instance.client
        .from('sos_alerts')
        .update({'status': st})
        .eq('id', a['id']);
    final aid = Supabase.instance.client.auth.currentUser?.id ?? 'X';
    await Supabase.instance.client.from('admin_audit_log').insert({
      'admin_id': aid,
      'action_type': 'sos_$st',
      'target_resource_id': a['id'].toString(),
      'details': {'table': 'sos_alerts', 'user_id': a['user_id'], 'submitted_by': a['submitted_by']},
    });

    if (_selectedAlert?['id'] == a['id']) {
      _closeCrisisPanel();
    }
  }

  /// Lista SOS filtrada por submitted_by:
  /// [submittedBy] = 'rider' → passageiros (inclui null para compatibilidade)
  /// [submittedBy] = 'driver' → motoristas
  Widget _list(String submittedBy) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client.from('sos_alerts').stream(primaryKey: ['id']),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        var items = snap.data!;

        // Filtrar por tipo de quem submeteu
        if (submittedBy == 'rider') {
          items = items
              .where((a) => a['submitted_by'] == 'rider' || a['submitted_by'] == null)
              .toList();
        } else {
          items = items.where((a) => a['submitted_by'] == 'driver').toList();
        }

        // Filtrar por status
        if (_filter != 'Todos') {
          items = items.where((a) => a['status'] == _filter).toList();
        }

        items.sort((a, b) {
          if (a['status'] == 'active' && b['status'] != 'active') return -1;
          if (a['status'] != 'active' && b['status'] == 'active') return 1;
          return (b['created_at']?.toString() ?? '').compareTo(a['created_at']?.toString() ?? '');
        });

        if (items.isEmpty) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.shield, size: 64, color: Theme.of(context).colorScheme.tertiary.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(
              submittedBy == 'rider'
                  ? 'Nenhum alerta de passageiro.'
                  : 'Nenhum alerta de motorista.',
              style: const TextStyle(color: Colors.white54),
            ),
          ]));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(24), itemCount: items.length,
          itemBuilder: (ctx, i) {
            final a = items[i];
            final st = a['status'] ?? 'active';
            final c = _sColor(context, st);
            final time = a['created_at'] != null
                ? DateTime.tryParse(a['created_at'].toString())?.toLocal().toString().substring(0, 16) ?? '' : '';
            final isSelected = _selectedAlert?['id'] == a['id'];

            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedAlert = a;
                });
                if (a['ride_id'] != null) {
                  _startChatRefresher(a['ride_id'].toString());
                } else {
                  _chatRealtimeChannel?.unsubscribe();
                  _chatRealtimeChannel = null;
                  setState(() { _sosMessages = []; });
                }
              },
              child: Card(
                color: isSelected
                    ? Theme.of(context).colorScheme.error.withOpacity(0.15)
                    : (st == 'active' ? Theme.of(context).colorScheme.error.withOpacity(0.05) : Theme.of(context).colorScheme.surface.withOpacity(0.8)),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: isSelected
                      ? BorderSide(color: Theme.of(context).colorScheme.error, width: 2.5)
                      : (st == 'active' ? BorderSide(color: Theme.of(context).colorScheme.error, width: 1) : BorderSide.none),
                ),
                child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                    child: Icon(st == 'active' ? Icons.warning_amber_rounded : Icons.check_circle, color: c, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                        child: Text(st.toUpperCase(), style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      // Badge do tipo de usuário
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (a['submitted_by'] == 'driver' ? Colors.blueAccent : Colors.purpleAccent).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          a['submitted_by'] == 'driver' ? '🚗 Motorista' : '👤 Passageiro',
                          style: TextStyle(
                            color: a['submitted_by'] == 'driver' ? Colors.blueAccent : Colors.purpleAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(time, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    ]),
                    const SizedBox(height: 8),
                    Text('Usuário: ${a['user_name'] ?? a['user_id'] ?? '?'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (a['user_phone'] != null) Text('Tel: ${a['user_phone']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    if (a['message'] != null) Text('Msg: ${a['message']}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                    if (a['ride_id'] != null) Text('Corrida: ${a['ride_id'].toString().substring(0, 8)}...', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ])),
                  if (st == 'active') Column(children: [
                    ElevatedButton.icon(
                      onPressed: () => _resolve(a, 'resolved'),
                      icon: const Icon(Icons.check, size: 16), label: const Text('Resolver'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.tertiary,
                        foregroundColor: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(onPressed: () => _resolve(a, 'dismissed'),
                      child: Text('Descartar', style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 12))),
                  ]),
                ])),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        color: Colors.white54,
        fontWeight: FontWeight.bold,
        fontSize: 11,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isLongText = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: isLongText
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Text(value, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 13)),
                ),
                Expanded(
                  child: Text(value,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
    );
  }

  void _copyDossier(Map<String, dynamic> a) {
    final buffer = StringBuffer();
    buffer.writeln('=== DOSSIÊ DE CRISE SOS (UPPI) ===');
    buffer.writeln('ID Alerta: ${a['id']}');
    buffer.writeln('Tipo: ${a['submitted_by'] == 'driver' ? 'Motorista' : 'Passageiro'}');
    buffer.writeln('Horário: ${a['created_at']}');
    buffer.writeln('Nome: ${a['user_name'] ?? 'Não informado'}');
    buffer.writeln('Telefone: ${a['user_phone'] ?? 'Não informado'}');
    buffer.writeln('ID Usuário: ${a['user_id']}');
    if (a['ride_id'] != null) {
      buffer.writeln('ID Corrida: ${a['ride_id']}');
      buffer.writeln('Origem: ${a['origin_address'] ?? 'N/D'}');
      buffer.writeln('Destino: ${a['destination_address'] ?? 'N/D'}');
      if (a['driver_name'] != null) buffer.writeln('Motorista: ${a['driver_name']}');
      if (a['passenger_name'] != null) buffer.writeln('Passageiro: ${a['passenger_name']}');
    }
    if (a['message'] != null) buffer.writeln('Mensagem SOS: ${a['message']}');

    if (_sosMessages.isNotEmpty) {
      buffer.writeln('\n=== ÚLTIMAS MENSAGENS DO CHAT ===');
      for (final msg in _sosMessages.take(10)) {
        final sender = msg['sender_type'] == 'rider' ? 'Passageiro' : 'Motorista';
        buffer.writeln('[$sender]: ${msg['message']}');
      }
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Dossiê policial copiado para a área de transferência!'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Widget _buildCrisisPanel() {
    final a = _selectedAlert;
    if (a == null) return const SizedBox();

    final st = a['status'] ?? 'active';
    final c = _sColor(context, st);
    final time = a['created_at'] != null
        ? DateTime.tryParse(a['created_at'].toString())?.toLocal().toString().substring(0, 16) ?? '' : '';

    final isDriver = a['submitted_by'] == 'driver';
    final title = isDriver ? 'SOS — Motorista' : 'SOS — Passageiro';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 6,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: st == 'active'
                ? [Theme.of(context).colorScheme.error, Theme.of(context).colorScheme.error.withOpacity(0.7), Theme.of(context).colorScheme.error]
                : [Theme.of(context).colorScheme.tertiary, Theme.of(context).colorScheme.tertiary.withOpacity(0.7), Theme.of(context).colorScheme.tertiary],
            ),
            boxShadow: st == 'active' ? [
              BoxShadow(
                color: Theme.of(context).colorScheme.error.withOpacity(0.5),
                blurRadius: 10, spreadRadius: 2,
              )
            ] : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(isDriver ? Icons.drive_eta : Icons.person_pin, color: c, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold, color: Colors.white,
                        fontSize: 16, letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      'STATUS: ${st.toUpperCase()}',
                      style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white60),
                onPressed: _closeCrisisPanel,
                hoverColor: Colors.white12,
                splashRadius: 20,
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildSectionHeader('INFORMAÇÕES GERAIS'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    _buildInfoRow('Nome:', a['user_name'] ?? 'Não informado'),
                    _buildInfoRow('Telefone:', a['user_phone'] ?? 'Não informado'),
                    _buildInfoRow('ID Usuário:', a['user_id']?.toString() ?? 'N/D'),
                    _buildInfoRow('Horário:', time),
                    _buildInfoRow('Tipo:', isDriver ? 'Motorista' : 'Passageiro'),
                    if (a['message'] != null)
                      _buildInfoRow('Mensagem SOS:', a['message'].toString(), isLongText: true),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (a['ride_id'] != null) ...[
                _buildSectionHeader('DETALHES DA VIAGEM'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      _buildInfoRow('ID da Viagem:', a['ride_id'].toString()),
                      if (a['origin_address'] != null)
                        _buildInfoRow('Origem:', a['origin_address'].toString()),
                      if (a['destination_address'] != null)
                        _buildInfoRow('Destino:', a['destination_address'].toString()),
                      if (a['driver_name'] != null)
                        _buildInfoRow('Motorista:', a['driver_name'].toString()),
                      if (a['passenger_name'] != null)
                        _buildInfoRow('Passageiro:', a['passenger_name'].toString()),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                _buildSectionHeader('HISTÓRICO DO CHAT DA CORRIDA (REALTIME)'),
                const SizedBox(height: 10),
                Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: _sosMessages.isEmpty
                      ? const Center(
                          child: Text(
                            'Nenhuma mensagem de chat registrada nesta corrida.',
                            style: TextStyle(color: Colors.white30, fontSize: 12),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _sosMessages.length,
                          itemBuilder: (ctx, idx) {
                            final msg = _sosMessages[idx];
                            final senderType = msg['sender_type'] ?? 'unknown';
                            final text = msg['message'] ?? '';
                            final timestamp = msg['created_at'] != null
                                ? DateTime.tryParse(msg['created_at'].toString())?.toLocal().toString().substring(11, 16) ?? ''
                                : '';
                            final isRider = senderType == 'rider';

                            return Align(
                              alignment: isRider ? Alignment.centerLeft : Alignment.centerRight,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isRider
                                      ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                                      : Theme.of(context).colorScheme.error.withOpacity(0.15),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(12),
                                    topRight: const Radius.circular(12),
                                    bottomLeft: isRider ? Radius.zero : const Radius.circular(12),
                                    bottomRight: isRider ? const Radius.circular(12) : Radius.zero,
                                  ),
                                  border: Border.all(
                                    color: isRider
                                        ? Theme.of(context).colorScheme.primary.withOpacity(0.4)
                                        : Theme.of(context).colorScheme.error.withOpacity(0.4),
                                    width: 0.5,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      isRider ? 'Passageiro' : 'Motorista',
                                      style: TextStyle(
                                        color: isRider
                                            ? Theme.of(context).colorScheme.primary
                                            : Theme.of(context).colorScheme.error,
                                        fontWeight: FontWeight.bold, fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(text, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Text(timestamp, style: const TextStyle(color: Colors.white38, fontSize: 9)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 20),
              ],
            ],
          ),
        ),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: const Border(top: BorderSide(color: Colors.white10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                onPressed: () => _copyDossier(a),
                icon: const Icon(Icons.copy),
                label: const Text('COPIAR DOSSIÊ POLICIAL (190)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: st == 'active' ? () => _resolve(a, 'resolved') : null,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('RESOLVER'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.tertiary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: st == 'active' ? () => _resolve(a, 'dismissed') : null,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('DESCARTAR'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.secondary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(children: [
            Container(
              padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: const Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Row(children: [
                    Icon(Icons.sos, color: Theme.of(context).colorScheme.error, size: 32),
                    const SizedBox(width: 12),
                    Text('Central de Emergências (SOS)',
                        style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w600)),
                  ]),
                  DropdownButton<String>(
                    value: _filter,
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                      DropdownMenuItem(value: 'active', child: Text('🔴 Ativos')),
                      DropdownMenuItem(value: 'resolved', child: Text('🟢 Resolvidos')),
                    ],
                    onChanged: (v) { if (v != null) setState(() => _filter = v); },
                  ),
                ]),
                const SizedBox(height: 16),
                TabBar(
                  controller: _tabController,
                  indicatorColor: Theme.of(context).colorScheme.error,
                  labelColor: Theme.of(context).colorScheme.error,
                  unselectedLabelColor: Colors.white54,
                  tabs: const [
                    Tab(icon: Icon(Icons.person, size: 18), text: 'Passageiros'),
                    Tab(icon: Icon(Icons.drive_eta, size: 18), text: 'Motoristas'),
                  ],
                ),
              ]),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Aba 1: SOS de Passageiros (submitted_by = 'rider' ou null)
                  _list('rider'),
                  // Aba 2: SOS de Motoristas (submitted_by = 'driver')
                  _list('driver'),
                ],
              ),
            ),
          ]),
        ),
        if (_selectedAlert != null)
          Container(
            width: 480,
            decoration: BoxDecoration(
              border: const Border(left: BorderSide(color: Colors.white10)),
              color: Theme.of(context).colorScheme.surface,
            ),
            child: _buildCrisisPanel(),
          ),
      ],
    );
  }
}
