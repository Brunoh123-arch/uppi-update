import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class QuickRepliesScreen extends StatefulWidget {
  const QuickRepliesScreen({super.key});

  @override
  State<QuickRepliesScreen> createState() => _QuickRepliesScreenState();
}

class _QuickRepliesScreenState extends State<QuickRepliesScreen> {
  String _roleFilter = 'Todos';

  void _editReply(Map<String, dynamic>? reply) {
    final textCtrl = TextEditingController(text: reply?['text_pt'] ?? '');
    final keyCtrl = TextEditingController(text: reply?['text_key'] ?? '');
    final sortCtrl = TextEditingController(text: reply?['sort_order']?.toString() ?? '0');
    String role = reply?['role'] ?? 'rider';
    String category = reply?['category'] ?? 'general';
    bool isEnabled = reply?['is_enabled'] ?? true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              title: Text(reply == null ? 'Nova Resposta Rápida' : 'Editar Resposta'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: keyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Chave (ex: on_my_way)',
                        helperText: 'Identificador interno único',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: textCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Texto exibido (PT-BR)',
                        helperText: 'Ex: Estou a caminho!',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: role,
                            items: const [
                              DropdownMenuItem(value: 'rider', child: Text('Passageiro')),
                              DropdownMenuItem(value: 'driver', child: Text('Motorista')),
                            ],
                            onChanged: (val) => setDialogState(() => role = val!),
                            decoration: const InputDecoration(labelText: 'Quem vê?'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: category,
                            items: const [
                              DropdownMenuItem(value: 'general', child: Text('Geral')),
                              DropdownMenuItem(value: 'arrival', child: Text('Chegada')),
                              DropdownMenuItem(value: 'identification', child: Text('Identificação')),
                              DropdownMenuItem(value: 'delay', child: Text('Atraso')),
                            ],
                            onChanged: (val) => setDialogState(() => category = val!),
                            decoration: const InputDecoration(labelText: 'Categoria'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: sortCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Ordem'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SwitchListTile(
                            title: const Text('Ativo'),
                            value: isEnabled,
                            onChanged: (val) => setDialogState(() => isEnabled = val),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (textCtrl.text.isEmpty) return;

                    final updates = {
                      'text_key': keyCtrl.text,
                      'text_pt': textCtrl.text,
                      'role': role,
                      'category': category,
                      'sort_order': int.tryParse(sortCtrl.text) ?? 0,
                      'is_enabled': isEnabled,
                    };

                    if (reply == null) {
                      await Supabase.instance.client.from('quick_replies').insert(updates);
                    } else {
                      await Supabase.instance.client
                          .from('quick_replies')
                          .update(updates)
                          .eq('id', reply['id']);
                    }

                    if (mounted) Navigator.pop(context);
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
                'Respostas Rápidas do Chat',
                style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              Row(
                children: [
                  DropdownButton<String>(
                    value: _roleFilter,
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                      DropdownMenuItem(value: 'rider', child: Text('Passageiro')),
                      DropdownMenuItem(value: 'driver', child: Text('Motorista')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _roleFilter = val);
                    },
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: () => _editReply(null),
                    icon: const Icon(Icons.add),
                    label: const Text('Nova Resposta'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('quick_replies')
                .stream(primaryKey: ['id']),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              var replies = snapshot.data!;
              if (_roleFilter != 'Todos') {
                replies = replies.where((r) => r['role'] == _roleFilter).toList();
              }
              replies.sort((a, b) => (a['sort_order'] as int? ?? 0).compareTo(b['sort_order'] as int? ?? 0));

              if (replies.isEmpty) {
                return const Center(child: Text('Nenhuma resposta rápida configurada.', style: TextStyle(color: Colors.white54)));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: replies.length,
                itemBuilder: (context, index) {
                  final reply = replies[index];
                  final isEnabled = reply['is_enabled'] == true;
                  final isDriver = reply['role'] == 'driver';

                  return Card(
                    color: Theme.of(context).colorScheme.surface.withAlpha(200),
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isDriver ? Colors.orange.withAlpha(50) : Colors.blue.withAlpha(50),
                        child: Icon(
                          isDriver ? Icons.drive_eta : Icons.person,
                          color: isEnabled ? (isDriver ? Colors.orange : Colors.blue) : Colors.white38,
                        ),
                      ),
                      title: Text(
                        reply['text_pt'] ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isEnabled ? Colors.white : Colors.white38,
                        ),
                      ),
                      subtitle: Text(
                        'Key: ${reply['text_key']} • Cat: ${reply['category']} • Ordem: ${reply['sort_order']}',
                        style: TextStyle(color: isEnabled ? Colors.white54 : Colors.white24, fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blueAccent),
                            onPressed: () => _editReply(reply),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () async {
                              await Supabase.instance.client
                                  .from('quick_replies')
                                  .delete()
                                  .eq('id', reply['id']);
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
}
