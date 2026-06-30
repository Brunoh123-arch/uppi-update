import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class AccessibilityTagsScreen extends StatefulWidget {
  const AccessibilityTagsScreen({super.key});

  @override
  State<AccessibilityTagsScreen> createState() => _AccessibilityTagsScreenState();
}

class _AccessibilityTagsScreenState extends State<AccessibilityTagsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Alterna flag de acessibilidade no motorista
  void _toggleDriverTag(String profileId, String column, bool currentValue) async {
    try {
      await _supabase.from('profiles').update({
        column: !currentValue,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', profileId);

      // Sincroniza também na tabela driver_locations
      await _supabase.from('driver_locations').update({
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('driver_id', profileId);

      // Grava log
      final adminId = _supabase.auth.currentUser?.id ?? 'sistema';
      await _supabase.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'toggle_driver_accessibility',
        'target_user_id': profileId,
        'details': {
          'column': column,
          'new_value': !currentValue,
        },
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar acessibilidade: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // Diálogo para criar/editar tag de acessibilidade no catálogo
  void _showTagCatalogDialog({Map<String, dynamic>? tag}) {
    final keyController = TextEditingController(text: tag?['key']);
    final nameController = TextEditingController(text: tag?['display_name']);
    final iconController = TextEditingController(text: tag?['icon']);
    final descController = TextEditingController(text: tag?['description']);
    final colController = TextEditingController(text: tag?['column_name']);
    bool isActive = tag?['is_active'] ?? true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                tag == null ? 'Nova Tag de Acessibilidade' : 'Editar Tag do Catálogo',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: keyController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Chave Única (ex: wheelchair)',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF096EFF))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Nome de Exibição',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF096EFF))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: iconController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Emoji ou Ícone (ex: ♿)',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF096EFF))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Descrição',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF096EFF))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: colController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Coluna no Banco (ex: accessibility_wheelchair)',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF096EFF))),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tag Habilitada:', style: TextStyle(color: Colors.white70)),
                        Switch(
                          value: isActive,
                          activeThumbColor: const Color(0xFF096EFF),
                          onChanged: (val) => setDialogState(() => isActive = val),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (keyController.text.trim().isEmpty || nameController.text.trim().isEmpty) return;

                    final data = {
                      'key': keyController.text.trim(),
                      'display_name': nameController.text.trim(),
                      'icon': iconController.text.trim(),
                      'description': descController.text.trim(),
                      'column_name': colController.text.trim(),
                      'is_active': isActive,
                    };

                    if (tag == null) {
                      await _supabase.from('accessibility_tags').insert(data);
                    } else {
                      await _supabase.from('accessibility_tags').update(data).eq('id', tag['id']);
                    }
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF096EFF)),
                  child: Text(tag == null ? 'Criar' : 'Salvar', style: const TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Deletar Tag
  void _deleteTag(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Excluir Tag'),
        content: const Text('Tem certeza que deseja excluir esta tag do catálogo?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Não', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sim, Excluir'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _supabase.from('accessibility_tags').delete().eq('id', id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        title: Text(
          'Gestão de Acessibilidade',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.colorScheme.primary,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Acessibilidade dos Motoristas'),
            Tab(text: 'Catálogo de Tags'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDriversAccessibilityTab(),
          _buildTagsCatalogTab(),
        ],
      ),
    );
  }

  // ABA 1: Acessibilidade dos Motoristas
  Widget _buildDriversAccessibilityTab() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
          child: const Text(
            'Habilite ou desabilite recursos de acessibilidade no perfil de cada motorista cadastrado na plataforma.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _supabase.from('accessibility_tags').stream(primaryKey: ['id']),
            builder: (context, tagsSnap) {
              final tags = (tagsSnap.data ?? []).where((t) => t['is_active'] == true).toList();

              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: _supabase.from('profiles').stream(primaryKey: ['id']).eq('role', 'driver'),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(child: Text('Erro: ${snap.error}', style: const TextStyle(color: Colors.redAccent)));
                  }
                  final drivers = snap.data ?? [];
                  if (drivers.isEmpty) {
                    return const Center(child: Text('Nenhum motorista cadastrado.', style: TextStyle(color: Colors.white38)));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: drivers.length,
                    itemBuilder: (context, index) {
                      final driver = drivers[index];
                      final name = driver['full_name']?.toString() ?? 'Motorista';
                      final phone = driver['phone_number']?.toString() ?? 'N/A';

                      return Card(
                        color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Telefone: $phone  •  Veículo: ${driver['vehicle_details']?['model'] ?? 'N/A'} (${driver['vehicle_details']?['plate'] ?? 'N/A'})',
                                style: const TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                              const SizedBox(height: 16),
                              const Divider(color: Colors.white10),
                              const SizedBox(height: 12),
                              if (tags.isEmpty)
                                const Text('Nenhuma tag ativa configurada no catálogo.', style: TextStyle(color: Colors.white38, fontSize: 12))
                              else
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: tags.map((tag) {
                                    final colName = tag['column_name']?.toString() ?? '';
                                    final isEnabled = driver[colName] == true;
                                    final icon = tag['icon']?.toString() ?? '♿';

                                    return FilterChip(
                                      avatar: Text(icon, style: const TextStyle(fontSize: 16)),
                                      label: Text(
                                        tag['display_name']?.toString() ?? '',
                                        style: TextStyle(
                                          color: isEnabled ? Colors.white : Colors.white54,
                                          fontWeight: isEnabled ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                      selected: isEnabled,
                                      selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                      checkmarkColor: Colors.white,
                                      backgroundColor: Colors.white10,
                                      side: BorderSide(
                                        color: isEnabled ? Theme.of(context).colorScheme.primary : Colors.white10,
                                        width: 1,
                                      ),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                      onSelected: (_) => _toggleDriverTag(
                                        driver['id'].toString(),
                                        colName,
                                        isEnabled,
                                      ),
                                    );
                                  }).toList(),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ABA 2: Catálogo de Tags
  Widget _buildTagsCatalogTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Defina quais opções de acessibilidade estarão disponíveis para filtros nas viagens.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              ElevatedButton.icon(
                onPressed: () => _showTagCatalogDialog(),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('Nova Tag', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _supabase.from('accessibility_tags').stream(primaryKey: ['id']).order('display_name'),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Erro: ${snap.error}', style: const TextStyle(color: Colors.redAccent)));
              }
              final list = snap.data ?? [];
              if (list.isEmpty) {
                return const Center(child: Text('Nenhuma tag configurada no catálogo.', style: TextStyle(color: Colors.white38)));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final item = list[index];
                  final isActive = item['is_active'] == true;
                  final icon = item['icon']?.toString() ?? '♿';

                  return Card(
                    color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                        backgroundColor: isActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                        radius: 24,
                        child: Text(icon, style: const TextStyle(fontSize: 22)),
                      ),
                      title: Row(
                        children: [
                          Text(
                            item['display_name']?.toString() ?? '',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isActive ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isActive ? 'ATIVA' : 'INATIVA',
                              style: TextStyle(color: isActive ? Colors.greenAccent : Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Chave: ${item['key']}  •  Coluna: ${item['column_name']}\n${item['description'] ?? ""}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blueAccent),
                            onPressed: () => _showTagCatalogDialog(tag: item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () => _deleteTag(item['id']),
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
