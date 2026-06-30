import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class DriverDocumentsScreen extends StatefulWidget {
  const DriverDocumentsScreen({super.key});
  @override
  State<DriverDocumentsScreen> createState() => _DriverDocumentsScreenState();
}

class _DriverDocumentsScreenState extends State<DriverDocumentsScreen> {
  String _statusFilter = 'Todos';

  Color _docColor(String s) {
    switch (s) {
      case 'approved': return Colors.greenAccent;
      case 'pending_review': return Colors.amber;
      case 'rejected': return Colors.redAccent;
      default: return Colors.white54;
    }
  }

  String _docLabel(String s) {
    switch (s) {
      case 'approved': return 'APROVADO';
      case 'pending_review': return 'PENDENTE';
      case 'rejected': return 'REJEITADO';
      default: return s.toUpperCase();
    }
  }

  void _changeStatus(Map<String, dynamic> doc, String newStatus) async {
    await Supabase.instance.client.from('driver_documents').update({'status': newStatus}).eq('driver_id', doc['driver_id']);
    
    // Sincroniza o status do perfil principal
    final profileStatus = newStatus == 'approved' ? 'active' : (newStatus == 'rejected' ? 'blocked' : 'waiting_documents');
    final Map<String, dynamic> profileUpdate = {'status': profileStatus};
    if (newStatus == 'approved') {
      final category = doc['vehicle_category'] ?? 'carro';
      profileUpdate['vehicle_type'] = category;
      
      // Update driver location as well if any
      await Supabase.instance.client
          .from('driver_locations')
          .update({'vehicle_type': category})
          .eq('driver_id', doc['driver_id']);
    }
    await Supabase.instance.client.from('profiles').update(profileUpdate).eq('id', doc['driver_id']);

    final aid = Supabase.instance.client.auth.currentUser?.id ?? 'X';
    await Supabase.instance.client.from('admin_audit_log').insert({
      'admin_id': aid,
      'action_type': 'driver_doc_$newStatus',
      'target_user_id': doc['driver_id'],
      'details': {'vehicle_plate': doc['vehicle_plate'], 'vehicle_model': doc['vehicle_model']},
    });
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
          Text('Documentos de Motoristas', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w600)),
          DropdownButton<String>(
            value: _statusFilter, dropdownColor: Theme.of(context).colorScheme.surface, underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 'Todos', child: Text('Todos')),
              DropdownMenuItem(value: 'pending_review', child: Text('Pendentes')),
              DropdownMenuItem(value: 'approved', child: Text('Aprovados')),
              DropdownMenuItem(value: 'rejected', child: Text('Rejeitados')),
            ],
            onChanged: (v) { if (v != null) setState(() => _statusFilter = v); },
          ),
        ]),
      ),
      Expanded(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: Supabase.instance.client.from('driver_documents').stream(primaryKey: ['driver_id']),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            var docs = snap.data!;
            if (_statusFilter != 'Todos') docs = docs.where((d) => d['status'] == _statusFilter).toList();
            if (docs.isEmpty) return const Center(child: Text('Nenhum documento encontrado.', style: TextStyle(color: Colors.white54)));

            return ListView.builder(
              padding: const EdgeInsets.all(24), itemCount: docs.length,
              itemBuilder: (ctx, i) {
                final d = docs[i];
                final st = d['status'] ?? 'pending_review';
                final c = _docColor(st);
                return Card(
                  color: Theme.of(context).colorScheme.surface.withAlpha(200),
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: c.withAlpha(40), borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.description, color: c, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Motorista: ${d['driver_id']?.toString().substring(0, 12) ?? ''}...', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('CNH: ${d['cnh'] ?? 'N/A'} • Placa: ${d['vehicle_plate'] ?? 'N/A'}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      Text('Modelo: ${d['vehicle_model'] ?? 'N/A'} • Cor: ${d['vehicle_color'] ?? 'N/A'} • Ano: ${d['vehicle_year'] ?? 'N/A'}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                      Text('Categoria: ${d['vehicle_category'] ?? 'N/A'}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    ])),
                    Column(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: c.withAlpha(40), borderRadius: BorderRadius.circular(8)),
                        child: Text(_docLabel(st), style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 12),
                      if (st == 'pending_review') ...[
                        ElevatedButton(
                          onPressed: () => _changeStatus(d, 'approved'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16)),
                          child: const Text('Aprovar'),
                        ),
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: () => _changeStatus(d, 'rejected'),
                          child: const Text('Rejeitar', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                        ),
                      ],
                    ]),
                  ])),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}
