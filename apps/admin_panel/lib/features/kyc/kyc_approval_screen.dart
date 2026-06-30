import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher_string.dart';


class KycApprovalScreen extends StatefulWidget {
  const KycApprovalScreen({super.key});

  @override
  State<KycApprovalScreen> createState() => _KycApprovalScreenState();
}

class _KycApprovalScreenState extends State<KycApprovalScreen>
    with SingleTickerProviderStateMixin {
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
                    'Central de KYC',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: Supabase.instance.client
                        .from('profiles')
                        .stream(primaryKey: ['id']),
                    builder: (context, snap) {
                      final allProfiles = snap.data ?? [];
                      final count = allProfiles.where((p) => p['role'] == 'driver' && p['is_approved'] != true).length;
                      return count > 0
                          ? Chip(
                              backgroundColor: Colors.orange.withOpacity(0.2),
                              label: Text(
                                '$count aguardando',
                                style: const TextStyle(
                                  color: Colors.orangeAccent,
                                ),
                              ),
                            )
                          : const Chip(
                              backgroundColor: Colors.green,
                              label: Text(
                                'Tudo ok!',
                                style: TextStyle(color: Colors.white),
                              ),
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
                  Tab(text: 'Todos os Motoristas'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _DriverGrid(statusFilter: 'pending_approval', filterByApproval: true),
              _DriverGrid(showAll: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _DriverGrid extends StatelessWidget {
  final String? statusFilter;
  final bool showAll;
  final bool filterByApproval;
  const _DriverGrid({this.statusFilter, this.showAll = false, this.filterByApproval = false});

  @override
  Widget build(BuildContext context) {
    // Para pendentes: busca todos os drivers e filtra por is_approved = false
    final stream = Supabase.instance.client
          .from('profiles')
          .stream(primaryKey: ['id'])
          .eq('role', 'driver');

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        var drivers = snapshot.data!;
        
        // Filtrar por aprovação pendente
        if (filterByApproval) {
          drivers = drivers.where((d) => d['is_approved'] != true).toList();
        }
        if (drivers.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.verified_user,
                  size: 64,
                  color: showAll ? Colors.white24 : Colors.greenAccent,
                ),
                const SizedBox(height: 16),
                Text(
                  showAll
                      ? 'Nenhum motorista cadastrado.'
                      : 'Nenhuma pendência!',
                  style: const TextStyle(color: Colors.white54, fontSize: 18),
                ),
              ],
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(32),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 24,
            mainAxisSpacing: 24,
            childAspectRatio: 0.85,
          ),
          itemCount: drivers.length,
          itemBuilder: (context, i) => _DriverCard(driver: drivers[i]),
        );
      },
    );
  }
}

class _DriverCard extends StatefulWidget {
  final Map<String, dynamic> driver;
  const _DriverCard({required this.driver});

  @override
  State<_DriverCard> createState() => _DriverCardState();
}

class _DriverCardState extends State<_DriverCard> {
  Map<String, dynamic>? _driverDocsMeta;
  bool _loadingMeta = true;

  @override
  void initState() {
    super.initState();
    _loadDriverDocsMeta();
  }

  Future<void> _loadDriverDocsMeta() async {
    try {
      final res = await Supabase.instance.client
          .from('driver_documents')
          .select()
          .eq('driver_id', widget.driver['id'].toString())
          .maybeSingle();
      if (mounted) {
        setState(() {
          _driverDocsMeta = res;
          _loadingMeta = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar metadados de driver_documents: $e');
      if (mounted) {
        setState(() {
          _loadingMeta = false;
        });
      }
    }
  }

  bool _areDocsUploaded() {
    final profileDocs = widget.driver['documents'];
    final avatarUrl = widget.driver['avatar_url']?.toString() ?? '';
    
    int validCount = 0;
    if (avatarUrl.isNotEmpty) {
      validCount++;
    }
    
    if (profileDocs is List) {
      for (var doc in profileDocs) {
        if (doc == null) continue;
        if (doc is Map) {
          final url = doc['url']?.toString() ?? doc['address']?.toString() ?? '';
          if (url.isNotEmpty) validCount++;
        } else if (doc is String && doc.isNotEmpty) {
          validCount++;
        }
      }
    }
    return validCount >= 4;
  }

  bool _isMetaComplete() {
    if (_driverDocsMeta == null) return false;
    final cnh = _driverDocsMeta!['cnh']?.toString().trim() ?? '';
    final plate = _driverDocsMeta!['vehicle_plate']?.toString().trim() ?? '';
    final model = _driverDocsMeta!['vehicle_model']?.toString().trim() ?? '';
    final category = _driverDocsMeta!['vehicle_category']?.toString().trim() ?? '';
    return cnh.isNotEmpty && plate.isNotEmpty && model.isNotEmpty && category.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.driver['full_name'] ?? '').toString().trim();
    final email = (widget.driver['email'] ?? '').toString().trim();
    final status = widget.driver['status'] ?? 'pending_approval';
    Color statusColor = Colors.orangeAccent;
    
    final profileDocs = widget.driver['documents'];
    List<String> docNames = [];
    if (profileDocs is List && profileDocs.isNotEmpty) {
      for (int i = 0; i < profileDocs.length; i++) {
        final doc = profileDocs[i];
        if (doc is Map) {
          docNames.add(doc['name']?.toString() ?? 'Doc ${i + 1}');
        } else if (doc is String && doc.isNotEmpty) {
          docNames.add('Doc ${i + 1}');
        }
      }
    }
    String docsText = docNames.isEmpty ? 'Nenhum documento anexado' : 'Docs: ${docNames.join(', ')}';
    if (status == 'online' || status == 'approved') {
      statusColor = Colors.greenAccent;
    }
    if (status == 'rejected' || status == 'blocked') {
      statusColor = Colors.redAccent;
    }

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
                backgroundImage: widget.driver['avatar_url'] != null
                    ? NetworkImage(widget.driver['avatar_url'])
                    : null,
                child: widget.driver['avatar_url'] == null
                    ? Icon(Icons.person, size: 36, color: statusColor)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              name.isEmpty ? 'Motorista' : name,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.driver['phone'] ?? widget.driver['phone_number'] ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            if (email.isNotEmpty)
              Text(
                email,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 8),
            Text(
              docsText,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            if (_loadingMeta)
              const Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              )
            else ...[
              if (!_areDocsUploaded())
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text(
                    '⚠️ Docs incompletos (mín. 4)',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (!_isMetaComplete())
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text(
                    '⚠️ Veículo/CNH incompleto',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
            const SizedBox(height: 6),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () =>
                  _viewDocs(context, widget.driver['id'].toString(), name),
              icon: const Icon(Icons.plagiarism_rounded, size: 16),
              label: const Text('Ver Documentos'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            if (widget.driver['is_approved'] != true) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          _reject(context, widget.driver['id'].toString()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Rejeitar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_loadingMeta || !_areDocsUploaded() || !_isMetaComplete())
                          ? null
                          : () => _approve(context, widget.driver['id'].toString()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        disabledBackgroundColor: Colors.white12,
                        disabledForegroundColor: Colors.white30,
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

  void _viewDocs(BuildContext context, String driverId, String name) {
    showDialog(
      context: context,
      builder: (_) => _DocumentsDialog(
        driverId: driverId,
        driverName: name,
        driverData: widget.driver,
      ),
    );
  }

  Future<void> _approve(BuildContext context, String id) async {
    try {
      final adminId =
          Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';

      await Supabase.instance.client
          .from('driver_kyc_history')
          .insert({
            'driver_id': id,
            'admin_id': adminId != 'UNKNOWN' ? adminId : null,
            'document_type': 'all',
            'status': 'approved',
          });

      // Sincroniza o motorista como APROVADO de verdade
      final Map<String, dynamic> profileUpdate = {
        'is_approved': true,
        'status': 'active',
      };
      if (_driverDocsMeta != null && _driverDocsMeta!['vehicle_category'] != null) {
        profileUpdate['vehicle_type'] = _driverDocsMeta!['vehicle_category'];
      }
      await Supabase.instance.client
          .from('driver_documents')
          .update({'status': 'approved'}).eq('driver_id', id);
      await Supabase.instance.client
          .from('profiles')
          .update(profileUpdate)
          .eq('id', id);

      // Audit trail
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'kyc_approval',
        'target_user_id': id,
        'details': {'action': 'approved'},
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Motorista aprovado!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _reject(BuildContext context, String id) async {
    final TextEditingController reasonController = TextEditingController();

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Motivo da Rejeição', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: reasonController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Digite o motivo da rejeição dos documentos...',
            hintStyle: TextStyle(color: Colors.white30),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white30),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.orangeAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Confirmar Rejeição', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final reason = reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, informe o motivo da rejeição.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final adminId =
          Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';

      await Supabase.instance.client
          .from('driver_kyc_history')
          .insert({
            'driver_id': id,
            'admin_id': adminId != 'UNKNOWN' ? adminId : null,
            'document_type': 'all',
            'status': 'rejected',
            'rejection_reason': reason,
          });

      // Sincroniza o motorista como REJEITADO
      await Supabase.instance.client
          .from('driver_documents')
          .update({'status': 'rejected'}).eq('driver_id', id);
      await Supabase.instance.client
          .from('profiles')
          .update({'is_approved': false, 'status': 'blocked'}).eq('id', id);

      // Audit trail
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'kyc_rejection',
        'target_user_id': id,
        'details': {'action': 'rejected', 'reason': reason},
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Motorista rejeitado.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _DocumentsDialog extends StatefulWidget {
  final String driverId;
  final String driverName;
  final Map<String, dynamic> driverData;
  const _DocumentsDialog({
    required this.driverId,
    required this.driverName,
    required this.driverData,
  });

  @override
  State<_DocumentsDialog> createState() => _DocumentsDialogState();
}

class _DocumentsDialogState extends State<_DocumentsDialog> {
  List<Map<String, String>> _docs = [];
  List<Map<String, dynamic>> _history = [];
  Map<String, dynamic>? _meta; // metadados estruturados (driver_documents)
  bool _isLoading = true;
  String? _error;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    final docs = <Map<String, String>>[];

    try {
      // 1. Avatar/Selfie do perfil
      final avatarUrl = widget.driverData['avatar_url'] as String?;
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        docs.add({'name': 'Selfie (Perfil)', 'url': avatarUrl});
      }

      // 2. Documentos salvos como JSONB no campo 'documents' do profile
      final profileDocs = widget.driverData['documents'];
      if (profileDocs is List && profileDocs.isNotEmpty) {
        for (int i = 0; i < profileDocs.length; i++) {
          final doc = profileDocs[i];
          if (doc is Map) {
            final url = doc['url']?.toString() ?? doc['address']?.toString() ?? '';
            final name = doc['name']?.toString() ?? 'Documento ${i + 1}';
            if (url.isNotEmpty) {
              docs.add({'name': name, 'url': url});
            }
          } else if (doc is String && doc.isNotEmpty) {
            docs.add({'name': 'Documento ${i + 1}', 'url': doc});
          }
        }
      }

      // 3. Fallback: listar do Supabase Storage
      if (docs.length <= 1) {
        // Só tem a selfie ou nada — tenta buscar do Storage
        try {
          final files = await Supabase.instance.client.storage
              .from('documents')
              .list(path: '${widget.driverId}/documents');
          for (var f in files) {
            if (f.name.isEmpty || f.name == '.emptyFolderPlaceholder') continue;
            final url = await Supabase.instance.client.storage
                .from('documents')
                .createSignedUrl('${widget.driverId}/documents/${f.name}', 315360000);
            docs.add({'name': f.name, 'url': url});
          }
        } catch (e) {
          debugPrint('Storage fallback error: $e');
        }

        // Também tenta o path sem subpasta "documents"
        if (docs.length <= 1) {
          try {
            final files = await Supabase.instance.client.storage
                .from('documents')
                .list(path: widget.driverId);
            for (var f in files) {
              if (f.name.isEmpty || f.name == '.emptyFolderPlaceholder') continue;
              // Ignora a pasta "documents" se existir
              if (f.id == null && f.name == 'documents') continue;
              final url = await Supabase.instance.client.storage
                  .from('documents')
                  .createSignedUrl('${widget.driverId}/${f.name}', 315360000);
              // Evita duplicatas
              if (!docs.any((d) => d['url'] == url)) {
                docs.add({'name': f.name, 'url': url});
              }
            }
          } catch (e) {
            debugPrint('Storage root fallback error: $e');
          }
        }
      }

      // 4. Buscar histórico de KYC
      try {
        final historyData = await Supabase.instance.client
            .from('driver_kyc_history')
            .select()
            .eq('driver_id', widget.driverId)
            .order('created_at', ascending: false);
        _history = List<Map<String, dynamic>>.from(historyData);
      } catch (e) {
        debugPrint('KYC history fetch error: $e');
      }

      // Metadados estruturados do motorista (driver_documents): CNH, placa, etc.
      try {
        _meta = await Supabase.instance.client
            .from('driver_documents')
            .select()
            .eq('driver_id', widget.driverId)
            .maybeSingle();
      } catch (e) {
        debugPrint('driver_documents fetch error: $e');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }

    if (mounted) {
      setState(() {
        _docs = docs;
        _isLoading = false;
      });
    }
  }

  Widget _metaItem(String label, dynamic value) {
    final v = (value ?? '').toString();
    return RichText(
      text: TextSpan(children: [
        TextSpan(
            text: '$label: ',
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
        TextSpan(
            text: v.isEmpty ? '—' : v,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 1000,
        height: 580,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(28, 20, 20, 20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.plagiarism_rounded,
                    color: Colors.blueAccent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Documentos — ${widget.driverName.isEmpty ? widget.driverId : widget.driverName}',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Metadados estruturados do motorista (driver_documents)
            if (_meta != null)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Wrap(
                  spacing: 20,
                  runSpacing: 6,
                  children: [
                    _metaItem('CNH', _meta!['cnh']),
                    _metaItem('Placa', _meta!['vehicle_plate']),
                    _metaItem('Modelo', _meta!['vehicle_model']),
                    _metaItem('Cor', _meta!['vehicle_color']),
                    _metaItem('Ano', _meta!['vehicle_year']),
                    _metaItem('Categoria', _meta!['vehicle_category']),
                  ],
                ),
              ),
            // Body
            Expanded(
              child: _error != null
                  ? Center(
                      child: Text(
                        'Erro: $_error',
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    )
                  : _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _docs.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.folder_open,
                            size: 64,
                            color: Colors.white24,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Nenhum documento enviado.',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ],
                      ),
                    )
                  : Row(
                      children: [
                        // File list sidebar
                        Container(
                          width: 200,
                          decoration: const BoxDecoration(
                            border: Border(
                              right: BorderSide(color: Colors.white10),
                            ),
                          ),
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _docs.length,
                            itemBuilder: (ctx, i) {
                              final sel = _selectedIndex == i;
                              final docName = _docs[i]['name'] ?? 'Doc ${i + 1}';
                              return GestureDetector(
                                onTap: () => setState(() => _selectedIndex = i),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: sel
                                        ? Colors.blueAccent.withOpacity(0.2)
                                        : Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: sel
                                          ? Colors.blueAccent
                                          : Colors.white10,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        docName.contains('Selfie')
                                            ? Icons.face
                                            : Icons.image_outlined,
                                        size: 16,
                                        color: sel
                                            ? Colors.blueAccent
                                            : Colors.white38,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          docName,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: sel
                                                ? Colors.white
                                                : Colors.white70,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // Image viewer
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      _docs[_selectedIndex]['url']!,
                                      fit: BoxFit.contain,
                                      loadingBuilder: (ctx, child, prog) {
                                        if (prog == null) return child;
                                        return Center(
                                          child: CircularProgressIndicator(
                                            value:
                                                prog.expectedTotalBytes != null
                                                ? prog.cumulativeBytesLoaded /
                                                      prog.expectedTotalBytes!
                                                : null,
                                          ),
                                        );
                                      },
                                      errorBuilder: (_, __, ___) =>
                                          const Center(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.broken_image_outlined,
                                                  size: 64,
                                                  color: Colors.white24,
                                                ),
                                                SizedBox(height: 12),
                                                Text(
                                                  'Imagem indisponível.',
                                                  style: TextStyle(
                                                    color: Colors.white38,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.open_in_new, size: 16),
                                  label: const Text('Abrir em Nova Aba'),
                                  onPressed: () => launchUrlString(
                                    _docs[_selectedIndex]['url']!,
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // KYC History Panel
                        Container(
                          width: 260,
                          decoration: const BoxDecoration(
                            border: Border(
                              left: BorderSide(color: Colors.white10),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text(
                                  'Histórico de KYC',
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                              const Divider(color: Colors.white10, height: 1),
                              Expanded(
                                child: _history.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'Nenhum histórico.',
                                          style: TextStyle(
                                            color: Colors.white30,
                                            fontSize: 12,
                                          ),
                                        ),
                                      )
                                    : ListView.separated(
                                        padding: const EdgeInsets.all(12),
                                        itemCount: _history.length,
                                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                                        itemBuilder: (ctx, idx) {
                                          final h = _history[idx];
                                          final status = h['status'] ?? 'unknown';
                                          final reason = h['rejection_reason'] ?? '';
                                          final dateStr = h['created_at'] != null
                                              ? DateTime.parse(h['created_at'].toString())
                                                  .toLocal()
                                                  .toString()
                                                  .substring(0, 16)
                                              : '';
                                          final isApp = status == 'approved';
                                          final color = isApp ? Colors.greenAccent : Colors.redAccent;

                                          return Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.02),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.white10),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: color.withOpacity(0.15),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        status.toUpperCase(),
                                                        style: TextStyle(
                                                          color: color,
                                                          fontSize: 9,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                    Text(
                                                      dateStr,
                                                      style: const TextStyle(
                                                        color: Colors.white38,
                                                        fontSize: 9,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (reason.isNotEmpty) ...[
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    'Motivo: $reason',
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 11,
                                                      height: 1.3,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
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
