import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class GamificationScreen extends StatefulWidget {
  const GamificationScreen({super.key});

  @override
  State<GamificationScreen> createState() => _GamificationScreenState();
}

class _GamificationScreenState extends State<GamificationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _editChallenge(Map<String, dynamic>? challenge) {
    final titleCtrl = TextEditingController(text: challenge?['title'] ?? '');
    final descCtrl = TextEditingController(text: challenge?['description'] ?? '');
    final targetCtrl = TextEditingController(text: challenge?['target']?.toString() ?? '10');
    final amountCtrl = TextEditingController(text: challenge?['reward_amount']?.toString() ?? '50.00');
    bool isActive = challenge?['is_active'] ?? true;
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              title: Text(challenge == null ? 'Criar Desafio' : 'Editar Desafio'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Título (Ex: Final de Semana Premiado)')),
                    const SizedBox(height: 16),
                    TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Descrição')),
                    const SizedBox(height: 16),
                    TextField(
                      controller: targetCtrl, 
                      decoration: const InputDecoration(labelText: 'Alvo (Corridas necessárias)'),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountCtrl, 
                      decoration: const InputDecoration(labelText: 'Bônus Financeiro (Carteira)'),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Ativo'),
                      value: isActive,
                      onChanged: (val) => setDialogState(() => isActive = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () async {
                    if (titleCtrl.text.isEmpty) return;

                    final updates = {
                      'title': titleCtrl.text,
                      'description': descCtrl.text,
                      'target': int.tryParse(targetCtrl.text) ?? 10,
                      'reward_amount': double.tryParse(amountCtrl.text) ?? 0.0,
                      'reward_type': 'walletBonus',
                      'reward_label': 'Bônus em Dinheiro',
                      'is_active': isActive,
                    };

                    if (challenge == null) {
                      await Supabase.instance.client.from('challenges').insert(updates);
                    } else {
                      await Supabase.instance.client.from('challenges').update(updates).eq('id', challenge['id']);
                    }
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

  void _editBadge(Map<String, dynamic>? badge) {
    final idCtrl = TextEditingController(text: badge?['id'] ?? '');
    final nameCtrl = TextEditingController(text: badge?['name'] ?? '');
    final iconCtrl = TextEditingController(text: badge?['icon'] ?? '🏆');
    final descCtrl = TextEditingController(text: badge?['description'] ?? '');
    String role = badge?['role'] ?? 'driver';
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              title: Text(badge == null ? 'Criar Conquista' : 'Editar Conquista'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: idCtrl, decoration: const InputDecoration(labelText: 'ID Único (ex: lenda_100)'), enabled: badge == null),
                    const SizedBox(height: 16),
                    TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nome da Conquista')),
                    const SizedBox(height: 16),
                    TextField(controller: iconCtrl, decoration: const InputDecoration(labelText: 'Ícone (Emoji)')),
                    const SizedBox(height: 16),
                    TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Descrição')),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      items: const [
                        DropdownMenuItem(value: 'driver', child: Text('Motorista')),
                        DropdownMenuItem(value: 'rider', child: Text('Passageiro')),
                      ],
                      onChanged: (val) => setDialogState(() => role = val!),
                      decoration: const InputDecoration(labelText: 'Público Alvo'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () async {
                    if (idCtrl.text.isEmpty || nameCtrl.text.isEmpty) return;

                    final updates = {
                      'id': idCtrl.text,
                      'name': nameCtrl.text,
                      'icon': iconCtrl.text,
                      'description': descCtrl.text,
                      'role': role,
                    };

                    if (badge == null) {
                      await Supabase.instance.client.from('badge_definitions').insert(updates);
                    } else {
                      await Supabase.instance.client.from('badge_definitions').update(updates).eq('id', badge['id']);
                    }
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

  Widget _buildChallengesList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client.from('challenges').stream(primaryKey: ['id']),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!;
        if (items.isEmpty) return const Center(child: Text('Nenhum desafio ativo.', style: TextStyle(color: Colors.white54)));

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final isActive = item['is_active'] == true;
            return Card(
              color: Theme.of(context).colorScheme.surface.withAlpha(200),
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Icon(Icons.stars, color: isActive ? Colors.amber : Colors.white38, size: 36),
                title: Text(item['title'] ?? '', style: TextStyle(color: isActive ? Colors.white : Colors.white54, fontWeight: FontWeight.bold)),
                subtitle: Text('Alvo: ${item['target']} corridas • Bônus: R\$ ${item['reward_amount']}', style: TextStyle(color: isActive ? Colors.white70 : Colors.white38)),
                trailing: IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blueAccent),
                  onPressed: () => _editChallenge(item),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBadgesList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client.from('badge_definitions').stream(primaryKey: ['id']),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!;
        if (items.isEmpty) return const Center(child: Text('Nenhuma conquista definida.', style: TextStyle(color: Colors.white54)));

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final isDriver = item['role'] == 'driver';
            return Card(
              color: Theme.of(context).colorScheme.surface.withAlpha(200),
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Text(item['icon'] ?? '🏆', style: const TextStyle(fontSize: 28)),
                title: Text('${item['name']} (${isDriver ? 'Motorista' : 'Passageiro'})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text(item['description'] ?? '', style: const TextStyle(color: Colors.white70)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.edit, color: Colors.blueAccent), onPressed: () => _editBadge(item)),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () async => await Supabase.instance.client.from('badge_definitions').delete().eq('id', item['id']),
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
                    'Gamificação & Desafios',
                    style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w600),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _tabController.index == 0 ? _editChallenge(null) : _editBadge(null),
                    icon: const Icon(Icons.add),
                    label: Text(_tabController.index == 0 ? 'Novo Desafio' : 'Nova Conquista'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700, foregroundColor: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.amber,
                labelColor: Colors.amber,
                unselectedLabelColor: Colors.white54,
                onTap: (val) => setState(() {}),
                tabs: const [
                  Tab(text: 'Desafios Ativos'),
                  Tab(text: 'Badges / Conquistas'),
                  Tab(text: 'Conquistas de Usuários'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildChallengesList(),
              _buildBadgesList(),
              _buildUserBadgesList(),
            ],
          ),
        ),
      ],
    );
  }
  Widget _buildUserBadgesList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('user_badges')
          .select('*, profiles:user_id(full_name, role)')
          .order('created_at', ascending: false)
          .limit(100),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
           return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
           return Center(child: Text('Erro: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
           return const Center(child: Text('Nenhuma conquista distribuída ainda.', style: TextStyle(color: Colors.white54)));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final user = item['profiles'] ?? {};
            final date = DateTime.tryParse(item['created_at']?.toString() ?? '')?.toLocal();

            return Card(
              color: Theme.of(context).colorScheme.surface.withAlpha(200),
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.emoji_events, color: Colors.amber, size: 36),
                title: Text('${user['full_name'] ?? 'Usuário Desconhecido'} (${user['role'] ?? 'Desconhecido'})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('Ganhou: ${item['badge_name'] ?? 'Conquista'}', style: const TextStyle(color: Colors.amber)),
                trailing: Text(date != null ? '${date.day.toString().padLeft(2,'0')}/${date.month.toString().padLeft(2,'0')}/${date.year} ${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}' : '', style: const TextStyle(color: Colors.white54)),
              ),
            );
          },
        );
      },
    );
  }
}
