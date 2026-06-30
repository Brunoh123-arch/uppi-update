import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class CancelReasonsScreen extends StatefulWidget {
  const CancelReasonsScreen({super.key});

  @override
  State<CancelReasonsScreen> createState() => _CancelReasonsScreenState();
}

class _CancelReasonsScreenState extends State<CancelReasonsScreen> {
  void _editReason(Map<String, dynamic>? reason) {
    final nameCtrl = TextEditingController(text: reason?['name'] ?? '');
    String selectedRole = reason?['role'] ?? 'rider';
    bool isActive = reason?['is_active'] ?? true;
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              title: Text(reason == null ? 'Nova Razão de Cancelamento' : 'Editar Razão'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Motivo (Ex: Motorista demorou muito)'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    items: const [
                      DropdownMenuItem(value: 'rider', child: Text('Passageiro')),
                      DropdownMenuItem(value: 'driver', child: Text('Motorista')),
                    ],
                    onChanged: (val) {
                      setDialogState(() => selectedRole = val!);
                    },
                    decoration: const InputDecoration(labelText: 'Quem pode ver esse motivo?'),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Ativo'),
                    value: isActive,
                    onChanged: (val) {
                      setDialogState(() => isActive = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameCtrl.text.isEmpty) return;

                    final updates = {
                      'name': nameCtrl.text,
                      'role': selectedRole,
                      'is_active': isActive,
                    };

                    if (reason == null) {
                      await Supabase.instance.client.from('cancel_reasons').insert(updates);
                    } else {
                      await Supabase.instance.client
                          .from('cancel_reasons')
                          .update(updates)
                          .eq('id', reason['id']);
                    }

                    final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
                    await Supabase.instance.client.from('admin_audit_log').insert({
                      'admin_id': adminId,
                      'action_type': reason == null ? 'cancel_reason_created' : 'cancel_reason_updated',
                      'target_resource_id': reason?['id']?.toString() ?? 'new_reason',
                      'details': updates,
                    });

                    if (mounted) Navigator.pop(context);
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          }
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
                'Motivos de Cancelamento',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _editReason(null),
                icon: const Icon(Icons.add),
                label: const Text('Novo Motivo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('cancel_reasons')
                .stream(primaryKey: ['id']),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Erro ao carregar.', style: TextStyle(color: Colors.red)));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final reasons = snapshot.data!;
              if (reasons.isEmpty) {
                return const Center(child: Text('Nenhum motivo configurado.', style: TextStyle(color: Colors.white54)));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: reasons.length,
                itemBuilder: (context, index) {
                  final reason = reasons[index];
                  final isActive = reason['is_active'] == true;
                  final isRider = reason['role'] == 'rider';

                  return Card(
                    color: Theme.of(context).colorScheme.surface.withAlpha(200),
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: Icon(
                        isRider ? Icons.person : Icons.drive_eta,
                        color: isActive ? Colors.white : Colors.white38,
                      ),
                      title: Text(
                        reason['name'] ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isActive ? Colors.white : Colors.white38,
                        ),
                      ),
                      subtitle: Text(
                        isRider ? 'Aplicativo Passageiro' : 'Aplicativo Motorista',
                        style: TextStyle(color: isActive ? Colors.white54 : Colors.white24),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blueAccent),
                        onPressed: () => _editReason(reason),
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
