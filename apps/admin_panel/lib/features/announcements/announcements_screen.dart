import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _announcements = [];
  
  // Stats
  int _activeCount = 0;
  int _riderCount = 0;
  int _driverCount = 0;

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  
  String _targetAudience = 'all';
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isActive = true;

  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
    _startRealtimeListener();
  }

  void _startRealtimeListener() {
    _realtimeChannel = Supabase.instance.client
        .channel('announcements_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'announcements',
          callback: (payload) {
            _loadAnnouncements(silent: true);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAnnouncements({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _isLoading = true);
    
    try {
      final List<Map<String, dynamic>> res = await Supabase.instance.client
          .from('announcements')
          .select('*')
          .order('created_at', ascending: false);

      int active = 0;
      int riders = 0;
      int drivers = 0;

      for (final a in res) {
        final activeVal = a['is_active'] as bool? ?? false;
        final target = a['target_audience']?.toString().toLowerCase() ?? 'all';
        
        if (activeVal) active++;
        if (target == 'rider' || target == 'all') riders++;
        if (target == 'driver' || target == 'all') drivers++;
      }

      if (mounted) {
        setState(() {
          _announcements = res;
          _activeCount = active;
          _riderCount = riders;
          _driverCount = drivers;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[AnnouncementsScreen] Erro ao carregar anúncios: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar comunicados: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleActive(String id, bool currentVal) async {
    try {
      await Supabase.instance.client
          .from('announcements')
          .update({'is_active': !currentVal})
          .eq('id', id);

      _loadAnnouncements();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!currentVal ? 'Comunicado ativado com sucesso! 🟢' : 'Comunicado desativado! 🔴'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao alterar status: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteAnnouncement(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Comunicado?'),
        content: const Text('Esta ação é permanente e removerá o aviso da tela de todos os usuários afetados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Supabase.instance.client.from('announcements').delete().eq('id', id);
      _loadAnnouncements();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comunicado excluído com sucesso!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showCreateDialog() {
    _titleCtrl.clear();
    _descCtrl.clear();
    _urlCtrl.clear();
    _targetAudience = 'all';
    _startDate = DateTime.now();
    _endDate = null;
    _isActive = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              'Criar Novo Comunicado',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 550),
              child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Título do Comunicado',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _descCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Descrição / Conteúdo',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _urlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'URL de Mídia / Banner (opcional)',
                      hintText: 'https://exemplo.com/banner.jpg',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _targetAudience,
                    dropdownColor: const Color(0xFF1E293B),
                    decoration: const InputDecoration(
                      labelText: 'Público Alvo',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Todos (Geral)')),
                      DropdownMenuItem(value: 'rider', child: Text('Passageiros (Riders)')),
                      DropdownMenuItem(value: 'driver', child: Text('Motoristas (Drivers)')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => _targetAudience = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _startDate == null 
                              ? 'Selecione data início' 
                              : 'Início: ${_startDate!.day}/${_startDate!.month}/${_startDate!.year}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                          );
                          if (date != null) {
                            setDialogState(() => _startDate = date);
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: const Text('Definir'),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _endDate == null 
                              ? 'Expiração: Sem expiração' 
                              : 'Fim: ${_endDate!.day}/${_endDate!.month}/${_endDate!.year}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now().add(const Duration(days: 7)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                          );
                          if (date != null) {
                            setDialogState(() => _endDate = date);
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: const Text('Definir'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Ativo Imediatamente', style: TextStyle(fontSize: 14)),
                    value: _isActive,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setDialogState(() => _isActive = v),
                  ),
                ],
              ),
             ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: () async {
                  if (_titleCtrl.text.trim().isEmpty || _descCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Preencha título e conteúdo!'), backgroundColor: Colors.red),
                    );
                    return;
                  }

                  try {
                    await Supabase.instance.client.from('announcements').insert({
                      'title': _titleCtrl.text.trim(),
                      'description': _descCtrl.text.trim(),
                      'url': _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
                      'target_audience': _targetAudience,
                      'start_at': _startDate?.toIso8601String() ?? DateTime.now().toIso8601String(),
                      'end_at': _endDate?.toIso8601String(),
                      'is_active': _isActive,
                    });

                    Navigator.pop(context);
                    _loadAnnouncements();
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Comunicado criado com sucesso! 🚀')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao criar comunicado: $e'), backgroundColor: Colors.red),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Criar Aviso'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          height: 80,
          padding: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Text(
                'Comunicados & Avisos Importantes',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _showCreateDialog,
                icon: const Icon(Icons.add),
                label: const Text('Novo Comunicado'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        
        // Cards de Estatisticas
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
          child: Row(
            children: [
              _buildStatCard('Avisos Ativos', _activeCount.toString(), Icons.campaign, Colors.orangeAccent),
              const SizedBox(width: 24),
              _buildStatCard('Foco Passageiros', _riderCount.toString(), Icons.person, Colors.blueAccent),
              const SizedBox(width: 24),
              _buildStatCard('Foco Motoristas', _driverCount.toString(), Icons.drive_eta, Colors.green),
            ],
          ),
        ),

        // List / Table
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _announcements.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.campaign_outlined, size: 64, color: Colors.white30),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhum comunicado criado ainda.',
                            style: GoogleFonts.outfit(fontSize: 18, color: Colors.white54),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(32),
                      itemCount: _announcements.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final a = _announcements[index];
                        final id = a['id'].toString();
                        final title = a['title']?.toString() ?? '';
                        final desc = a['description']?.toString() ?? '';
                        final url = a['url']?.toString();
                        final isActiveVal = a['is_active'] as bool? ?? false;
                        final audience = a['target_audience']?.toString().toLowerCase() ?? 'all';
                        final startAt = a['start_at'] != null ? DateTime.parse(a['start_at']) : null;
                        final endAt = a['end_at'] != null ? DateTime.parse(a['end_at']) : null;

                        Color audienceColor = Colors.purple;
                        String audienceText = 'Todos';
                        if (audience == 'rider') {
                          audienceColor = Colors.blueAccent;
                          audienceText = 'Passageiros';
                        } else if (audience == 'driver') {
                          audienceColor = Colors.green;
                          audienceText = 'Motoristas';
                        }

                        return Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white10),
                          ),
                          padding: const EdgeInsets.all(24),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Icone / Thumbnail
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: audienceColor.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.campaign, color: audienceColor, size: 28),
                              ),
                              const SizedBox(width: 20),
                              
                              // Textos
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: audienceColor.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: audienceColor.withValues(alpha: 0.4)),
                                          ),
                                          child: Text(
                                            audienceText,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: audienceColor,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      desc,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        height: 1.4,
                                      ),
                                    ),
                                    if (url != null) ...[
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          const Icon(Icons.link, size: 14, color: Colors.orangeAccent),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              url,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        const Icon(Icons.access_time, size: 12, color: Colors.white30),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Agendado: ${startAt != null ? "${startAt.day}/${startAt.month}/${startAt.year}" : "Imediato"}',
                                          style: const TextStyle(color: Colors.white30, fontSize: 11),
                                        ),
                                        const SizedBox(width: 16),
                                        const Icon(Icons.timer_off_outlined, size: 12, color: Colors.white30),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Expira em: ${endAt != null ? "${endAt.day}/${endAt.month}/${endAt.year}" : "Sem limite"}',
                                          style: const TextStyle(color: Colors.white30, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 32),
                              
                              // Status Switch & Ações
                              Column(
                                children: [
                                  Switch(
                                    value: isActiveVal,
                                    activeThumbColor: Colors.orangeAccent,
                                    onChanged: (_) => _toggleActive(id, isActiveVal),
                                  ),
                                  const SizedBox(height: 8),
                                  IconButton(
                                    onPressed: () => _deleteAnnouncement(id),
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    tooltip: 'Excluir Comunicado',
                                  ),
                                ],
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

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
          ],
        ),
      ),
    );
  }
}
