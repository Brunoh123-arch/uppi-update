import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'face_verification_flow.dart';

/// Tela do Painel Admin para a verificação facial ANTI-FRAUDE dos motoristas.
///
/// A captura (selfie ao vivo + comparação com a foto de referência) acontece no
/// APP do motorista e grava em `driver_face_verifications`. Aqui o admin:
///  - revisa os casos duvidosos (status `needs_review`);
///  - vê o histórico de todas as verificações;
///  - ajusta as notas de corte (auto-aprovar / auto-bloquear);
///  - testa a experiência que o motorista vê.
class DriverFaceVerificationScreen extends StatefulWidget {
  const DriverFaceVerificationScreen({super.key});

  @override
  State<DriverFaceVerificationScreen> createState() =>
      _DriverFaceVerificationScreenState();
}

class _DriverFaceVerificationScreenState
    extends State<DriverFaceVerificationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
                    'Verificação Facial — Motoristas',
                    style: GoogleFonts.outfit(
                        fontSize: 28, fontWeight: FontWeight.w600),
                  ),
                  _PendingChip(),
                ],
              ),
              const SizedBox(height: 8),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: kFaceGreen,
                labelColor: kFaceGreen,
                unselectedLabelColor: Colors.white54,
                tabs: const [
                  Tab(text: 'Fila de Revisão'),
                  Tab(text: 'Histórico'),
                  Tab(text: 'Configurações'),
                  Tab(text: 'Testar Experiência'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _ReviewQueueTab(),
              _HistoryTab(),
              _ConfigTab(),
              _TestTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Helpers de status ───────────────────────────────────────────────────────

Color _statusColor(String status) {
  switch (status) {
    case 'approved':
    case 'auto_approved':
      return kFaceGreen;
    case 'rejected':
    case 'auto_rejected':
      return Colors.redAccent;
    case 'needs_review':
    default:
      return Colors.orangeAccent;
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'approved':
      return 'Aprovado (admin)';
    case 'auto_approved':
      return 'Aprovado (auto)';
    case 'rejected':
      return 'Rejeitado (admin)';
    case 'auto_rejected':
      return 'Bloqueado (auto)';
    case 'needs_review':
      return 'Em revisão';
    default:
      return status;
  }
}

// ─── Chip de pendências no cabeçalho ─────────────────────────────────────────

class _PendingChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('driver_face_verifications')
          .stream(primaryKey: ['id']),
      builder: (context, snap) {
        final count = (snap.data ?? [])
            .where((v) => v['status'] == 'needs_review')
            .length;
        return count > 0
            ? Chip(
                backgroundColor: Colors.orange.withValues(alpha: 0.2),
                label: Text('$count p/ revisar',
                    style: const TextStyle(color: Colors.orangeAccent)),
              )
            : const Chip(
                backgroundColor: Colors.green,
                label: Text('Sem pendências',
                    style: TextStyle(color: Colors.white)),
              );
      },
    );
  }
}

// ─── Aba 1: Fila de Revisão ──────────────────────────────────────────────────

class _ReviewQueueTab extends StatelessWidget {
  const _ReviewQueueTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('driver_face_verifications')
          .stream(primaryKey: ['id'])
          .order('created_at'),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _TableMissingHint(error: snapshot.error);
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!
            .where((v) => v['status'] == 'needs_review')
            .toList();

        if (items.isEmpty) {
          return const _EmptyState(
            icon: Icons.verified_user_rounded,
            color: kFaceGreen,
            title: 'Nenhum caso para revisar',
            subtitle:
                'Os casos em "zona de dúvida" (entre as notas de corte) aparecem '
                'aqui automaticamente quando os motoristas se verificarem no app.',
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(32),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 520,
            crossAxisSpacing: 24,
            mainAxisSpacing: 24,
            mainAxisExtent: 360,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => _ReviewCard(row: items[i]),
        );
      },
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const _ReviewCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final score = (row['similarity_score'] as num?)?.toDouble();
    final liveness = row['liveness_passed'] == true;
    final driverId = row['driver_id']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nome do motorista (busca pelo id).
          FutureBuilder<Map<String, dynamic>?>(
            future: Supabase.instance.client
                .from('profiles')
                .select('full_name, phone')
                .eq('id', driverId)
                .maybeSingle(),
            builder: (context, snap) {
              final name = (snap.data?['full_name'] ?? '').toString().trim();
              return Row(
                children: [
                  const Icon(Icons.drive_eta_rounded,
                      color: Colors.white54, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name.isEmpty ? 'Motorista ($driverId)' : name,
                      style: GoogleFonts.outfit(
                          fontSize: 16, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          // Comparação das fotos.
          Expanded(
            child: Row(
              children: [
                _photo('Cadastro', row['reference_url']?.toString()),
                const SizedBox(width: 12),
                _photo('Selfie agora', row['selfie_url']?.toString()),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _badge(
                score == null ? 'Sem nota' : '${score.toStringAsFixed(0)}%',
                Colors.blueAccent,
                Icons.compare_arrows_rounded,
              ),
              const SizedBox(width: 8),
              _badge(
                liveness ? 'Prova de vida ok' : 'Prova de vida falhou',
                liveness ? kFaceGreen : Colors.redAccent,
                liveness ? Icons.verified_rounded : Icons.gpp_bad_rounded,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _decide(context, false),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Rejeitar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _decide(context, true),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Aprovar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kFaceGreen,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _photo(String label, String? url) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: (url == null || url.isEmpty)
                  ? Container(
                      color: Colors.white10,
                      child: const Center(
                        child: Icon(Icons.image_not_supported_outlined,
                            color: Colors.white24),
                      ),
                    )
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.white10,
                        child: const Center(
                          child: Icon(Icons.broken_image_outlined,
                              color: Colors.white24),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _decide(BuildContext context, bool approved) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(approved ? 'Aprovar verificação' : 'Rejeitar verificação',
            style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: reasonCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: approved
                ? 'Observação (opcional)'
                : 'Motivo da rejeição (ex.: rosto não confere)',
            hintStyle: const TextStyle(color: Colors.white30),
            enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white30)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: approved ? kFaceGreen : Colors.redAccent,
                foregroundColor: approved ? Colors.black : Colors.white),
            child: Text(approved ? 'Aprovar' : 'Rejeitar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final supabase = Supabase.instance.client;
      final adminId = supabase.auth.currentUser?.id ?? 'UNKNOWN';
      await supabase.from('driver_face_verifications').update({
        'status': approved ? 'approved' : 'rejected',
        'decided_by': adminId != 'UNKNOWN' ? adminId : null,
        'decision_reason': reasonCtrl.text.trim(),
        'decided_at': DateTime.now().toIso8601String(),
      }).eq('id', row['id']);

      await supabase.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type':
            approved ? 'face_verification_approved' : 'face_verification_rejected',
        'target_user_id': row['driver_id'],
        'details': {
          'verification_id': row['id'],
          'reason': reasonCtrl.text.trim(),
        },
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approved
                ? 'Verificação aprovada.'
                : 'Verificação rejeitada.'),
            backgroundColor: approved ? Colors.green : Colors.red,
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

// ─── Aba 2: Histórico ────────────────────────────────────────────────────────

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('driver_face_verifications')
          .stream(primaryKey: ['id'])
          .order('created_at'),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _TableMissingHint(error: snapshot.error);
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!.reversed.toList(); // mais recentes primeiro
        if (items.isEmpty) {
          return const _EmptyState(
            icon: Icons.history_rounded,
            color: Colors.white24,
            title: 'Nenhuma verificação ainda',
            subtitle:
                'O histórico será preenchido conforme os motoristas se '
                'verificarem no app.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final v = items[i];
            final status = v['status']?.toString() ?? 'needs_review';
            final color = _statusColor(status);
            final score = (v['similarity_score'] as num?)?.toDouble();
            final url = v['selfie_url']?.toString();
            final created = v['created_at'] != null
                ? DateTime.tryParse(v['created_at'].toString())
                    ?.toLocal()
                    .toString()
                    .substring(0, 16)
                : '';

            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: (url == null || url.isEmpty)
                        ? const ColoredBox(
                            color: Colors.white10,
                            child: Icon(Icons.face, color: Colors.white24))
                        : Image.network(url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const ColoredBox(
                                color: Colors.white10,
                                child:
                                    Icon(Icons.face, color: Colors.white24))),
                  ),
                ),
                title: FutureBuilder<Map<String, dynamic>?>(
                  future: Supabase.instance.client
                      .from('profiles')
                      .select('full_name')
                      .eq('id', v['driver_id'])
                      .maybeSingle(),
                  builder: (context, snap) {
                    final name =
                        (snap.data?['full_name'] ?? '').toString().trim();
                    return Text(
                      name.isEmpty ? 'Motorista ${v['driver_id']}' : name,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    );
                  },
                ),
                subtitle: Text(
                  '${score == null ? 'sem nota' : '${score.toStringAsFixed(0)}% de semelhança'} • $created',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_statusLabel(status),
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Aba 3: Configurações ────────────────────────────────────────────────────

class _ConfigTab extends StatefulWidget {
  const _ConfigTab();

  @override
  State<_ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<_ConfigTab> {
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  double _autoApprove = 90;
  double _autoReject = 70;
  final TextEditingController _intervalCtrl = TextEditingController(text: '7');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _intervalCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('app_settings')
          .select('key, value');
      final map = {
        for (final r in rows)
          (r['key']?.toString() ?? ''): (r['value']?.toString() ?? '')
      };
      setState(() {
        _enabled = map['face_verification_enabled'] == 'true';
        _autoApprove =
            double.tryParse(map['face_auto_approve_threshold'] ?? '90') ?? 90;
        _autoReject =
            double.tryParse(map['face_auto_reject_threshold'] ?? '70') ?? 70;
        _intervalCtrl.text = map['face_verification_interval_days'] ?? '7';
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_autoReject >= _autoApprove) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'A nota de bloqueio deve ser MENOR que a de aprovação automática.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final supabase = Supabase.instance.client;
      final entries = {
        'face_verification_enabled': _enabled.toString(),
        'face_auto_approve_threshold': _autoApprove.toStringAsFixed(0),
        'face_auto_reject_threshold': _autoReject.toStringAsFixed(0),
        'face_verification_interval_days':
            (int.tryParse(_intervalCtrl.text) ?? 7).toString(),
      };
      for (final e in entries.entries) {
        await supabase.from('app_settings').upsert({
          'key': e.key,
          'value': e.value,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'key');
      }
      final adminId = supabase.auth.currentUser?.id ?? 'UNKNOWN';
      await supabase.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'face_verification_config_updated',
        'target_resource_id': 'app_settings',
        'details': entries,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Configurações salvas!'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _panel(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: kFaceGreen,
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                  title: const Text('Exigir verificação facial dos motoristas',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                    'Quando ligado, o app pede a selfie ao vivo nos momentos '
                    'configurados.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Notas de corte',
                        style: GoogleFonts.outfit(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    const Text(
                      'A "nota" é o quanto a selfie de agora se parece com a foto '
                      'do cadastro (0 a 100%).',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    _sliderRow(
                      label: 'Aprovar automático se ≥',
                      value: _autoApprove,
                      color: kFaceGreen,
                      min: 50,
                      max: 100,
                      onChanged: (v) => setState(() {
                        _autoApprove = v;
                        if (_autoReject > _autoApprove - 1) {
                          _autoReject = _autoApprove - 1;
                        }
                      }),
                    ),
                    _sliderRow(
                      label: 'Bloquear automático se <',
                      value: _autoReject,
                      color: Colors.redAccent,
                      min: 0,
                      max: 99,
                      onChanged: (v) => setState(() {
                        _autoReject = v > _autoApprove - 1
                            ? _autoApprove - 1
                            : v;
                      }),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.fact_check_outlined,
                              color: Colors.orangeAccent, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Entre ${_autoReject.toStringAsFixed(0)}% e '
                              '${_autoApprove.toStringAsFixed(0)}% → cai na sua '
                              'fila de revisão manual.',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _panel(
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Re-verificar a cada (dias)',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _intervalCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded),
                label: const Text('Salvar configurações'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kFaceGreen,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: GoogleFonts.outfit(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required Color color,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${value.toStringAsFixed(0)}%',
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: (max - min).round(),
          activeColor: color,
          label: '${value.toStringAsFixed(0)}%',
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }
}

// ─── Aba 4: Testar Experiência ───────────────────────────────────────────────

class _TestTab extends StatefulWidget {
  const _TestTab();

  @override
  State<_TestTab> createState() => _TestTabState();
}

class _TestTabState extends State<_TestTab> {
  FaceVerificationResult? _result;

  Future<void> _startTest() async {
    final result = await Navigator.of(context).push<FaceVerificationResult>(
      MaterialPageRoute(
        builder: (_) => const FaceVerificationFlow(),
        fullscreenDialog: true,
      ),
    );
    if (result != null && mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.face_rounded,
                            color: kFaceGreen, size: 24),
                        const SizedBox(width: 10),
                        Text('Pré-visualizar o que o motorista vê',
                            style: GoogleFonts.outfit(
                                fontSize: 18, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Este é só o fluxo visual de captura (câmera + oval + '
                      'instruções). A comparação de rosto anti-fraude roda no app '
                      'do motorista no celular.',
                      style: TextStyle(
                          color: Colors.white60, height: 1.5, fontSize: 13),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: _startTest,
                      icon: const Icon(Icons.play_circle_fill_rounded),
                      label: Text(
                          r == null ? 'Iniciar teste' : 'Refazer teste'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kFaceGreen,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        textStyle: GoogleFonts.outfit(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              if (r != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(r.imageBytes,
                            width: 150, height: 190, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.check_circle_rounded,
                                    color: kFaceGreen),
                                SizedBox(width: 8),
                                Text('Captura concluída',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              r.usedFallback
                                  ? 'Foto enviada (sem prova de vida)'
                                  : 'Prova de vida guiada em '
                                      '${(r.durationMs / 1000).toStringAsFixed(1)}s',
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 13),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${(r.imageBytes.lengthInBytes / 1024).toStringAsFixed(0)} KB capturados',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Componentes auxiliares ──────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(color: Colors.white70, fontSize: 18)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

/// Mostrado quando a tabela ainda não existe (migration não aplicada).
class _TableMissingHint extends StatelessWidget {
  final Object? error;
  const _TableMissingHint({this.error});

  @override
  Widget build(BuildContext context) {
    final msg = error?.toString() ?? '';
    final looksMissing = msg.contains('driver_face_verifications') ||
        msg.contains('does not exist') ||
        msg.contains('relation');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.dataset_outlined,
                size: 64, color: Colors.orangeAccent),
            const SizedBox(height: 16),
            Text(
              looksMissing
                  ? 'Tabela ainda não criada'
                  : 'Não foi possível carregar',
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              looksMissing
                  ? 'Aplique a migration "20260602000000_driver_face_verifications.sql" '
                      'no Supabase para ativar a fila de verificações.'
                  : msg,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
