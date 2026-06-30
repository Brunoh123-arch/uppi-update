import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher_string.dart';

class RiderIdentityVerificationScreen extends StatefulWidget {
  const RiderIdentityVerificationScreen({super.key});

  @override
  State<RiderIdentityVerificationScreen> createState() => _RiderIdentityVerificationScreenState();
}

class _RiderIdentityVerificationScreenState extends State<RiderIdentityVerificationScreen> with SingleTickerProviderStateMixin {
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
                    'Verificação de Identidade (Passageiros)',
                    style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w600),
                  ),
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: Supabase.instance.client.from('profiles').stream(primaryKey: ['id']),
                    builder: (context, snap) {
                      final allProfiles = snap.data ?? [];
                      final count = allProfiles.where((p) => p['role'] == 'rider' && p['identity_verification_status'] == 'pending').length;
                      return count > 0
                          ? Chip(
                              backgroundColor: Colors.orange.withOpacity(0.2),
                              label: Text('$count aguardando', style: const TextStyle(color: Colors.orangeAccent)),
                            )
                          : const Chip(
                              backgroundColor: Colors.green,
                              label: Text('Nenhuma pendência', style: TextStyle(color: Colors.white)),
                            );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.orangeAccent,
                labelColor: Colors.orangeAccent,
                unselectedLabelColor: Colors.white54,
                tabs: const [
                  Tab(text: 'Pendentes'),
                  Tab(text: 'Todas Verificações'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _RiderGrid(statusFilter: 'pending'),
              _RiderGrid(showAll: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _RiderGrid extends StatelessWidget {
  final String? statusFilter;
  final bool showAll;
  const _RiderGrid({this.statusFilter, this.showAll = false});

  @override
  Widget build(BuildContext context) {
    var stream = Supabase.instance.client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('role', 'rider');

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}'));
        
        var riders = snapshot.data!;
        
        if (!showAll) {
          riders = riders.where((d) => d['identity_verification_status'] == 'pending').toList();
        } else {
          riders = riders.where((d) => d['identity_verification_status'] != null).toList();
        }

        if (riders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined, size: 64, color: showAll ? Colors.white24 : Colors.greenAccent),
                const SizedBox(height: 16),
                Text(
                  showAll ? 'Nenhuma verificação de identidade encontrada.' : 'Nenhuma verificação pendente!',
                  style: const TextStyle(color: Colors.white54, fontSize: 18),
                ),
              ],
            ),
          );
        }
        
        return GridView.builder(
          padding: const EdgeInsets.all(32),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 24, mainAxisSpacing: 24, childAspectRatio: 0.85,
          ),
          itemCount: riders.length,
          itemBuilder: (context, i) => _RiderCard(rider: riders[i]),
        );
      },
    );
  }
}

class _RiderCard extends StatelessWidget {
  final Map<String, dynamic> rider;
  const _RiderCard({required this.rider});

  @override
  Widget build(BuildContext context) {
    final name = (rider['full_name'] ?? '').toString().trim();
    final status = rider['identity_verification_status'] ?? 'none';
    Color statusColor = Colors.grey;

    if (status == 'pending') statusColor = Colors.orangeAccent;
    if (status == 'verified' || status == 'approved') statusColor = Colors.greenAccent;
    if (status == 'rejected') statusColor = Colors.redAccent;

    return Card(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: CircleAvatar(
                radius: 36,
                backgroundColor: statusColor.withOpacity(0.15),
                backgroundImage: rider['avatar_url'] != null ? NetworkImage(rider['avatar_url']) : null,
                child: rider['avatar_url'] == null ? Icon(Icons.person, size: 36, color: statusColor) : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              name.isEmpty ? 'Passageiro' : name,
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
            Text(
              rider['phone'] ?? rider['phone_number'] ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () => _viewDocs(context, rider['id'].toString(), name),
              icon: const Icon(Icons.plagiarism_rounded, size: 16),
              label: const Text('Analisar Documentos'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            if (status == 'pending') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _reject(context, rider['id'].toString()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Rejeitar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _approve(context, rider['id'].toString()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent, foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Aprovar'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _viewDocs(BuildContext context, String riderId, String name) {
    showDialog(
      context: context,
      builder: (_) => _RiderDocumentsDialog(riderId: riderId, riderName: name, riderData: rider),
    );
  }

  Future<void> _approve(BuildContext context, String id) async {
    try {
      await Supabase.instance.client.from('profiles').update({
        'identity_verification_status': 'verified',
      }).eq('id', id);

      final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId, 'action_type': 'rider_identity_approval', 'target_user_id': id, 'details': {'action': 'approved'},
      });
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verificação aprovada!'), backgroundColor: Colors.green));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _reject(BuildContext context, String id) async {
    try {
      await Supabase.instance.client.from('profiles').update({
        'identity_verification_status': 'rejected',
      }).eq('id', id);

      final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId, 'action_type': 'rider_identity_rejection', 'target_user_id': id, 'details': {'action': 'rejected'},
      });
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verificação rejeitada.'), backgroundColor: Colors.red));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
    }
  }
}

class _RiderDocumentsDialog extends StatefulWidget {
  final String riderId;
  final String riderName;
  final Map<String, dynamic> riderData;
  const _RiderDocumentsDialog({required this.riderId, required this.riderName, required this.riderData});

  @override
  State<_RiderDocumentsDialog> createState() => _RiderDocumentsDialogState();
}

class _RiderDocumentsDialogState extends State<_RiderDocumentsDialog> {
  final List<Map<String, String>> _docs = [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    final docsObj = widget.riderData['identity_docs'];
    if (docsObj is Map) {
      if (docsObj['selfieUrl'] != null) _docs.add({'name': 'Selfie', 'url': docsObj['selfieUrl'].toString()});
      if (docsObj['rgUrl'] != null) _docs.add({'name': 'RG', 'url': docsObj['rgUrl'].toString()});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 820, height: 580,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(28, 20, 20, 20),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: Colors.blueAccent),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Identidade — ${widget.riderName.isEmpty ? widget.riderId : widget.riderName}', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Expanded(
              child: _docs.isEmpty
                  ? const Center(child: Text('Nenhum documento de identidade encontrado.', style: TextStyle(color: Colors.white54)))
                  : Row(
                      children: [
                        Container(
                          width: 200,
                          decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white10))),
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12), itemCount: _docs.length,
                            itemBuilder: (ctx, i) {
                              final sel = _selectedIndex == i;
                              return GestureDetector(
                                onTap: () => setState(() => _selectedIndex = i),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: sel ? Colors.blueAccent.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: sel ? Colors.blueAccent : Colors.white10),
                                  ),
                                  child: Text(_docs[i]['name']!, style: TextStyle(color: sel ? Colors.white : Colors.white70)),
                                ),
                              );
                            },
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(_docs[_selectedIndex]['url']!, fit: BoxFit.contain))),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.open_in_new, size: 16), label: const Text('Abrir em Nova Aba'),
                                  onPressed: () => launchUrlString(_docs[_selectedIndex]['url']!),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
