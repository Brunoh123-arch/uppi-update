import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class VehicleConfigScreen extends StatefulWidget {
  const VehicleConfigScreen({super.key});

  @override
  State<VehicleConfigScreen> createState() => _VehicleConfigScreenState();
}

class _VehicleConfigScreenState extends State<VehicleConfigScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

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

  void _editItem(String table, Map<String, dynamic>? item) {
    final nameCtrl = TextEditingController(text: item?['name'] ?? '');
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(item == null ? 'Adicionar Novo' : 'Editar'),
          content: TextField(
            controller: nameCtrl,
            decoration: InputDecoration(labelText: table == 'car_models' ? 'Modelo (ex: Toyota Corolla)' : 'Cor (ex: Prata)'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isEmpty) return;

                final updates = {'name': nameCtrl.text};

                if (item == null) {
                  await Supabase.instance.client.from(table).insert(updates);
                } else {
                  await Supabase.instance.client
                      .from(table)
                      .update(updates)
                      .eq('id', item['id']);
                }

                if (mounted) Navigator.pop(context);
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildList(String table, String emptyMsg) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client.from(table).stream(primaryKey: ['id']),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final items = snapshot.data!;
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emptyMsg, style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _editItem(table, null),
                  child: const Text('Adicionar Primeiro'),
                )
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              color: Theme.of(context).colorScheme.surface.withAlpha(200),
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text(item['name'] ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blueAccent),
                      onPressed: () => _editItem(table, item),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () async {
                        await Supabase.instance.client.from(table).delete().eq('id', item['id']);
                      },
                    ),
                  ],
                ),
              ),
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
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Dados de Veículos (Motoristas)',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _editItem(_tabController.index == 0 ? 'car_models' : 'car_colors', null),
                    icon: const Icon(Icons.add),
                    label: Text(_tabController.index == 0 ? 'Novo Modelo' : 'Nova Cor'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.indigoAccent,
                labelColor: Colors.indigoAccent,
                unselectedLabelColor: Colors.white54,
                onTap: (val) => setState(() {}),
                tabs: const [
                  Tab(text: 'Modelos de Carro'),
                  Tab(text: 'Cores de Carro'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildList('car_models', 'Nenhum modelo cadastrado. (Necessário para aprovação de Motoristas)'),
              _buildList('car_colors', 'Nenhuma cor cadastrada. (Necessário para aprovação de Motoristas)'),
            ],
          ),
        ),
      ],
    );
  }
}
