import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  void _editAdmin(Map<String, dynamic>? admin) {
    final formKey = GlobalKey<FormState>();
    final idCtrl = TextEditingController(text: admin?['id'] ?? '');
    final nameCtrl = TextEditingController(text: admin?['name'] ?? '');
    final emailCtrl = TextEditingController(text: admin?['email'] ?? '');
    String selectedRole = admin?['role'] ?? 'admin';
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              title: Text(admin == null ? 'Adicionar Novo Admin' : 'Editar Admin'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: idCtrl,
                        decoration: const InputDecoration(labelText: 'Supabase/Firebase UID do Usuário'),
                        enabled: admin == null, // ID não editável após criado
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'O UID é obrigatório';
                          }
                          if (value.trim().length < 10) {
                            return 'UID muito curto (mínimo 10 caracteres)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Nome do Administrador'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'O nome é obrigatório';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: emailCtrl,
                        decoration: const InputDecoration(labelText: 'Email do Administrador'),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'O e-mail é obrigatório';
                          }
                          final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                          if (!emailRegex.hasMatch(value.trim())) {
                            return 'Insira um e-mail válido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedRole,
                        items: const [
                          DropdownMenuItem(value: 'operator', child: Text('Operador (Básico)')),
                          DropdownMenuItem(value: 'admin', child: Text('Administrador')),
                          DropdownMenuItem(value: 'superadmin', child: Text('Super Admin')),
                        ],
                        onChanged: (val) {
                          setDialogState(() => selectedRole = val!);
                        },
                        decoration: const InputDecoration(labelText: 'Nível de Permissão'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) {
                      return;
                    }

                    final updates = {
                      'id': idCtrl.text.trim(),
                      'name': nameCtrl.text.trim(),
                      'email': emailCtrl.text.trim(),
                      'role': selectedRole,
                    };

                    try {
                      if (admin == null) {
                        await Supabase.instance.client.from('admins').insert(updates);
                      } else {
                        await Supabase.instance.client
                            .from('admins')
                            .update(updates)
                            .eq('id', admin['id']);
                      }

                      final currentAdminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
                      await Supabase.instance.client.from('admin_audit_log').insert({
                        'admin_id': currentAdminId,
                        'action_type': admin == null ? 'admin_created' : 'admin_updated',
                        'target_resource_id': idCtrl.text.trim(),
                        'details': updates,
                      });

                      if (mounted) Navigator.pop(context);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red));
                    }
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
                'Equipe Administrativa',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _editAdmin(null),
                icon: const Icon(Icons.security),
                label: const Text('Adicionar Membro'),
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
                .from('admins')
                .stream(primaryKey: ['id']),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Erro ao carregar administradores.', style: TextStyle(color: Colors.red)));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final admins = snapshot.data!;

              return ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: admins.length,
                itemBuilder: (context, index) {
                  final admin = admins[index];
                  final isCurrent = admin['id'] == Supabase.instance.client.auth.currentUser?.id;

                  return Card(
                    color: Theme.of(context).colorScheme.surface.withAlpha(200),
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: admin['role'] == 'superadmin' ? Colors.deepPurple : Colors.indigo,
                        child: Icon(admin['role'] == 'superadmin' ? Icons.shield : Icons.person, color: Colors.white),
                      ),
                      title: Text(
                        '${admin['name'] ?? 'Sem Nome'} ${isCurrent ? "(Você)" : ""}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      subtitle: Text(
                        '${admin['email'] ?? 'Sem Email'} • Role: ${admin['role']}',
                        style: const TextStyle(color: Colors.white54),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blueAccent),
                            onPressed: () => _editAdmin(admin),
                          ),
                          if (!isCurrent)
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.redAccent),
                              onPressed: () async {
                                final currentAdminId = Supabase.instance.client.auth.currentUser?.id;
                                if (admin['id'] == currentAdminId) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Você não pode excluir a si mesmo!'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                  return;
                                }

                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Excluir Administrador?'),
                                    content: Text('Tem certeza que deseja remover ${admin['name'] ?? 'este administrador'} do painel?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text('Cancelar'),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Excluir', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm != true) return;

                                try {
                                  await Supabase.instance.client.from('admins').delete().eq('id', admin['id']);
                                  final currentAdminIdStr = currentAdminId ?? 'UNKNOWN';
                                  await Supabase.instance.client.from('admin_audit_log').insert({
                                    'admin_id': currentAdminIdStr,
                                    'action_type': 'admin_deleted',
                                    'target_resource_id': admin['id'],
                                  });
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Administrador removido com sucesso.')),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Erro ao excluir: $e'), backgroundColor: Colors.red),
                                    );
                                  }
                                }
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
