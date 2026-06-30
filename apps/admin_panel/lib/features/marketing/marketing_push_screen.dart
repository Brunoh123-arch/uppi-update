import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MarketingPushScreen extends StatefulWidget {
  const MarketingPushScreen({super.key});

  @override
  State<MarketingPushScreen> createState() => _MarketingPushScreenState();
}

class _MarketingPushScreenState extends State<MarketingPushScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _imageUrlCtrl = TextEditingController();

  String _target = 'Passageiros';
  String _statusFilter = 'todos';
  String _activityFilter = 'any';

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _cityCtrl.dispose();
    _imageUrlCtrl.dispose();
    super.dispose();
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
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Marketing & Push Notifications',
              style: GoogleFonts.outfit(
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool isNarrow = constraints.maxWidth < 1150;

                final configCard = Card(
                  color: Theme.of(context).colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Configurar Disparo',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        DropdownButtonFormField<String>(
                          initialValue: _target,
                          dropdownColor: Theme.of(context).colorScheme.surface,
                          decoration: const InputDecoration(
                            labelText: 'Público Alvo',
                            border: OutlineInputBorder(),
                          ),
                          items: ['Passageiros', 'Motoristas', 'Todos']
                              .map(
                                (t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _target = v);
                          },
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Filtros de Segmentação Avançados',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _cityCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Filtrar por Cidade (ILike endereço)',
                            prefixIcon: Icon(Icons.location_city),
                            border: OutlineInputBorder(),
                          ),
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _statusFilter,
                          dropdownColor: Theme.of(context).colorScheme.surface,
                          decoration: const InputDecoration(
                            labelText: 'Status do Usuário',
                            prefixIcon: Icon(Icons.verified),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'todos', child: Text('Todos', style: TextStyle(color: Colors.white))),
                            DropdownMenuItem(value: 'online', child: Text('Online', style: TextStyle(color: Colors.white))),
                            DropdownMenuItem(value: 'offline', child: Text('Offline', style: TextStyle(color: Colors.white))),
                            DropdownMenuItem(value: 'approved', child: Text('Aprovado', style: TextStyle(color: Colors.white))),
                            DropdownMenuItem(value: 'pending', child: Text('Pendente de Aprovação', style: TextStyle(color: Colors.white))),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _statusFilter = v);
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _activityFilter,
                          dropdownColor: Theme.of(context).colorScheme.surface,
                          decoration: const InputDecoration(
                            labelText: 'Período de Atividade',
                            prefixIcon: Icon(Icons.history),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'any', child: Text('Qualquer data', style: TextStyle(color: Colors.white))),
                            DropdownMenuItem(value: '24h', child: Text('Ativo nas últimas 24h', style: TextStyle(color: Colors.white))),
                            DropdownMenuItem(value: '7d', child: Text('Ativo na última semana', style: TextStyle(color: Colors.white))),
                            DropdownMenuItem(value: '30d_inactive', child: Text('Inativo há mais de 30 dias', style: TextStyle(color: Colors.white))),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _activityFilter = v);
                          },
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _titleCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Título da Notificação',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _bodyCtrl,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Mensagem',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _imageUrlCtrl,
                          decoration: const InputDecoration(
                            labelText: 'URL da Imagem (opcional, deve começar com https://)',
                            prefixIcon: Icon(Icons.image_outlined),
                            hintText: 'https://exemplo.com/imagem.jpg',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.url,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              if (_titleCtrl.text.isEmpty ||
                                  _bodyCtrl.text.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Preencha título e mensagem!',
                                    ),
                                  ),
                                );
                                return;
                              }

                              try {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Buscando tokens e preparando envio...',
                                    ),
                                  ),
                                );

                                var query = Supabase.instance.client
                                    .from('profiles')
                                    .select('fcm_token');

                                // Filtro de Público Alvo (Role)
                                if (_target != 'Todos') {
                                  final role = _target == 'Passageiros' ? 'rider' : 'driver';
                                  query = query.eq('role', role);
                                }

                                // Filtro de Cidade (Endereço)
                                final city = _cityCtrl.text.trim();
                                if (city.isNotEmpty) {
                                  query = query.ilike('address', '%$city%');
                                }

                                // Filtro de Status
                                if (_statusFilter == 'online') {
                                  query = query.eq('status', 'online');
                                } else if (_statusFilter == 'offline') {
                                  query = query.eq('status', 'offline');
                                } else if (_statusFilter == 'approved') {
                                  query = query.eq('is_approved', true);
                                } else if (_statusFilter == 'pending') {
                                  query = query.eq('is_approved', false);
                                }

                                // Filtro de Período de Atividade
                                if (_activityFilter == '24h') {
                                  final threshold = DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();
                                  query = query.gte('updated_at', threshold);
                                } else if (_activityFilter == '7d') {
                                  final threshold = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
                                  query = query.gte('updated_at', threshold);
                                } else if (_activityFilter == '30d_inactive') {
                                  final threshold = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
                                  query = query.lt('updated_at', threshold);
                                }

                                final List<Map<String, dynamic>> users = await query;
                                final tokens = users
                                    .map((e) => e['fcm_token'] as String?)
                                    .where((t) => t != null && t.isNotEmpty)
                                    .toList();

                                if (tokens.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Nenhum usuário com token encontrado para esta segmentação.',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                final imageUrl = _imageUrlCtrl.text.trim();
                                if (imageUrl.isNotEmpty && !imageUrl.startsWith('https://')) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('URL da imagem deve começar com https://'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }

                                await Supabase.instance.client.functions.invoke(
                                  'send-multicast-push',
                                  body: {
                                    'title': _titleCtrl.text,
                                    'body': _bodyCtrl.text,
                                    'tokens': tokens,
                                    if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
                                  },
                                );

                                // Audit log for push marketing
                                final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
                                await Supabase.instance.client.from('admin_audit_log').insert({
                                  'admin_id': adminId,
                                  'action_type': 'marketing_push',
                                  'target_resource_id': 'bulk_${tokens.length}_tokens',
                                  'details': {
                                    'target': _target,
                                    'city_filter': city,
                                    'status_filter': _statusFilter,
                                    'activity_filter': _activityFilter,
                                    'title': _titleCtrl.text,
                                    'body': _bodyCtrl.text,
                                    'image_url': imageUrl.isEmpty ? null : imageUrl,
                                    'tokens_count': tokens.length,
                                  },
                                });

                                // Gravar nos anúncios para ficar visível no app permanentemente
                                await Supabase.instance.client.from('announcements').insert({
                                  'title': _titleCtrl.text,
                                  'description': _bodyCtrl.text,
                                  'start_at': DateTime.now().toIso8601String(),
                                });

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Notificação enviada para ${tokens.length} dispositivo(s)!',
                                    ),
                                  ),
                                );
                                _titleCtrl.clear();
                                _bodyCtrl.clear();
                                _cityCtrl.clear();
                                _imageUrlCtrl.clear();
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Erro ao enviar: $e'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.send),
                            label: const Text('Disparar Push Notification'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orangeAccent,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );

                final previewCard = Card(
                  color: Theme.of(context).colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        const Text(
                          'Preview (Android)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.notifications,
                                      color: Colors.white54,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _titleCtrl.text.isEmpty
                                                ? 'Seu Título Aqui'
                                                : _titleCtrl.text,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _bodyCtrl.text.isEmpty
                                                ? 'O corpo da sua notificação aparecerá aqui.'
                                                : _bodyCtrl.text,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Preview da imagem (se URL preenchida)
                              if (_imageUrlCtrl.text.trim().isNotEmpty)
                                Image.network(
                                  _imageUrlCtrl.text.trim(),
                                  width: double.infinity,
                                  height: 160,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    height: 160,
                                    color: Colors.white10,
                                    child: const Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.broken_image, color: Colors.white38, size: 40),
                                          SizedBox(height: 8),
                                          Text('Imagem não carregou — verifique a URL',
                                            style: TextStyle(color: Colors.white38, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '⚠️ Imagens no iOS requerem Notification Service Extension instalada no app.',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      configCard,
                      const SizedBox(height: 32),
                      previewCard,
                    ],
                  );
                } else {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: configCard,
                      ),
                      const SizedBox(width: 32),
                      Expanded(
                        child: previewCard,
                      ),
                    ],
                  );
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}
