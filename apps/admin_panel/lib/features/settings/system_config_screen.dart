import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class SystemConfigScreen extends StatefulWidget {
  const SystemConfigScreen({super.key});
  @override
  State<SystemConfigScreen> createState() => _SystemConfigScreenState();
}

class _SystemConfigScreenState extends State<SystemConfigScreen> {
  void _editConfig(Map<String, dynamic>? cfg) {
    final keyCtrl = TextEditingController(text: cfg?['key'] ?? '');
    final valueCtrl = TextEditingController(text: cfg?['value']?.toString() ?? '{}');
    final surgeCtrl = TextEditingController(text: cfg?['surge_multiplier']?.toString() ?? '1.00');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(cfg == null ? 'Nova Config' : 'Editar: ${cfg['key']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: keyCtrl, decoration: const InputDecoration(labelText: 'Chave (ex: pricing)'), enabled: cfg == null),
          const SizedBox(height: 16),
          TextField(controller: valueCtrl, decoration: const InputDecoration(labelText: 'Valor (JSON)'), maxLines: 4),
          const SizedBox(height: 16),
          TextField(controller: surgeCtrl, decoration: const InputDecoration(labelText: 'Surge Multiplier'), keyboardType: TextInputType.number),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () async {
              if (keyCtrl.text.isEmpty) return;
              final updates = {
                'key': keyCtrl.text,
                'value': valueCtrl.text,
                'surge_multiplier': double.tryParse(surgeCtrl.text) ?? 1.0,
                'updated_at': DateTime.now().toIso8601String(),
              };
              if (cfg == null) {
                await Supabase.instance.client.from('config').insert(updates);
              } else {
                await Supabase.instance.client.from('config').update(updates).eq('key', cfg['key']);
              }
              final aid = Supabase.instance.client.auth.currentUser?.id ?? 'X';
              await Supabase.instance.client.from('admin_audit_log').insert({
                'admin_id': aid, 'action_type': 'config_updated',
                'target_resource_id': keyCtrl.text, 'details': updates,
              });
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(32, 20, 32, 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: const Border(bottom: BorderSide(color: Colors.white10)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Config Dinâmica do Sistema', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w600)),
          ElevatedButton.icon(
            onPressed: () => _editConfig(null),
            icon: const Icon(Icons.add), label: const Text('Nova Chave'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
          ),
        ]),
      ),
      Expanded(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: Supabase.instance.client.from('config').stream(primaryKey: ['key']),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final items = snap.data!;
            if (items.isEmpty) return const Center(child: Text('Nenhuma config.', style: TextStyle(color: Colors.white54)));

            return ListView.builder(
              padding: const EdgeInsets.all(24), itemCount: items.length,
              itemBuilder: (ctx, i) {
                final c = items[i];
                final surge = c['surge_multiplier']?.toString() ?? '1.0';
                return Card(
                  color: Theme.of(context).colorScheme.surface.withAlpha(200),
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const Icon(Icons.tune, color: Colors.indigoAccent),
                    title: Text(c['key'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Surge: ${surge}x', style: TextStyle(color: double.parse(surge) > 1 ? Colors.amber : Colors.white54, fontSize: 13)),
                      Text('Value: ${c['value']?.toString().substring(0, (c['value']?.toString().length ?? 0) > 80 ? 80 : c['value']?.toString().length ?? 0) ?? '{}'}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    ]),
                    trailing: IconButton(icon: const Icon(Icons.edit, color: Colors.blueAccent), onPressed: () => _editConfig(c)),
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}
