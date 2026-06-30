import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

// Constantes de estilo correspondentes ao Painel Admin
const _kPrimary = Color(0xFF096EFF);
const _kSurface = Color(0xFF1E293B);
const _kBackground = Color(0xFF0F172A);
const _kSubtext = Color(0xFF94A3B8);
const _kBorder = Color(0xFF2D3F58);

class ReferralManagementScreen extends StatefulWidget {
  const ReferralManagementScreen({super.key});

  @override
  State<ReferralManagementScreen> createState() => _ReferralManagementScreenState();
}

class _ReferralManagementScreenState extends State<ReferralManagementScreen> {
  final _bonusReferrerCtrl = TextEditingController();
  final _bonusReferredCtrl = TextEditingController();
  bool _referralEnabled = true;
  bool _isLoadingSettings = true;
  bool _isSavingSettings = false;

  List<Map<String, dynamic>> _referralsList = [];
  bool _isLoadingReferrals = true;

  // KPIs
  int _totalReferrals = 0;
  double _totalPaidOut = 0.0;
  int _pendingReferrals = 0;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _bonusReferrerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    await _loadSettings();
    await _loadReferrals();
  }

  Future<void> _loadSettings() async {
    if (mounted) setState(() => _isLoadingSettings = true);
    try {
      final res = await Supabase.instance.client
          .from('app_settings')
          .select('key, value');

      final Map<String, String> settings = {};
      for (final row in res) {
        settings[row['key']?.toString() ?? ''] = row['value']?.toString() ?? '';
      }

      if (mounted) {
        setState(() {
          _referralEnabled = settings['referral_enabled'] == 'true';
          _bonusReferrerCtrl.text = settings['referral_bonus_referrer'] ?? '10.00';
          _bonusReferredCtrl.text = settings['referral_bonus_referred'] ?? '5.00';
          _isLoadingSettings = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar configurações de indicações: $e');
      if (mounted) setState(() => _isLoadingSettings = false);
    }
  }

  Future<void> _loadReferrals() async {
    if (mounted) setState(() => _isLoadingReferrals = true);
    try {
      final client = Supabase.instance.client;
      
      // Busca a lista de indicações com detalhes dos perfis envolvidos (joins)
      final data = await client
          .from('referrals')
          .select('''
            id,
            reward_amount,
            status,
            created_at,
            completed_at,
            referrer:referrer_id (full_name, phone_number, email),
            referred:referred_id (full_name, phone_number, email)
          ''')
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> list = List<Map<String, dynamic>>.from(data);

      int total = list.length;
      double paid = 0.0;
      int pending = 0;

      for (var ref in list) {
        if (ref['status'] == 'completed') {
          paid += (ref['reward_amount'] as num?)?.toDouble() ?? 0.0;
        } else {
          pending++;
        }
      }

      if (mounted) {
        setState(() {
          _referralsList = list;
          _totalReferrals = total;
          _totalPaidOut = paid;
          _pendingReferrals = pending;
          _isLoadingReferrals = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao buscar lista de indicações: $e');
      if (mounted) setState(() => _isLoadingReferrals = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSavingSettings = true);
    try {
      final referrerBonus = double.tryParse(_bonusReferrerCtrl.text) ?? 10.00;
      final referredBonus = double.tryParse(_bonusReferredCtrl.text) ?? 5.00;

      final entries = {
        'referral_enabled': _referralEnabled.toString(),
        'referral_bonus_referrer': referrerBonus.toStringAsFixed(2),
        'referral_bonus_referred': referredBonus.toStringAsFixed(2),
      };

      for (final entry in entries.entries) {
        await Supabase.instance.client
            .from('app_settings')
            .upsert({
              'key': entry.key,
              'value': entry.value,
              'updated_at': DateTime.now().toIso8601String(),
            }, onConflict: 'key');
      }

      // Registro de Auditoria
      final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'referral_settings_updated',
        'target_resource_id': 'referral_config',
        'details': entries,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurações de indicação salvas com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar configurações: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingSettings = false);
    }
  }

  Future<void> _completeReferralManually(String id, String referredId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSurface,
        title: const Text('Confirmar Liberação', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Deseja forçar manualmente a conclusão desta indicação e creditar o bônus nas carteiras do indicador e indicado?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Liberar Bônus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Carrega os valores configurados de bônus
      final referrerBonus = double.tryParse(_bonusReferrerCtrl.text) ?? 10.00;
      final referredBonus = double.tryParse(_bonusReferredCtrl.text) ?? 5.00;

      // Executa no Supabase
      final client = Supabase.instance.client;

      // 1. Busca detalhes do referrer
      final refData = await client
          .from('referrals')
          .select('referrer_id')
          .eq('id', id)
          .single();

      final String referrerId = refData['referrer_id'] as String;

      // 2. Atualiza indicação
      await client
          .from('referrals')
          .update({
            'status': 'completed',
            'reward_amount': referrerBonus,
            'completed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);

      // 3. Credita indicador
      await client.rpc('credit_user_wallet_balance', params: {
        'p_user_id': referrerId,
        'p_amount': referrerBonus,
      });

      await client.from('wallet_transactions').insert({
        'user_id': referrerId,
        'amount': referrerBonus,
        'transaction_type': 'topup',
        'description': 'Bônus de Indicação Uppi (Liberação Manual Admin)',
      });

      // 4. Credita indicado
      await client.rpc('credit_user_wallet_balance', params: {
        'p_user_id': referredId,
        'p_amount': referredBonus,
      });

      await client.from('wallet_transactions').insert({
        'user_id': referredId,
        'amount': referredBonus,
        'transaction_type': 'topup',
        'description': 'Bônus de Indicação Uppi (Liberação Manual Admin - Código Utilizado)',
      });

      // Registro de Auditoria
      final adminId = client.auth.currentUser?.id ?? 'UNKNOWN';
      await client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'referral_manually_completed',
        'target_resource_id': id,
        'details': {'referral_id': id, 'referred_id': referredId, 'referrer_id': referrerId},
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Indicação liberada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadReferrals();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao processar liberação: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            decoration: const BoxDecoration(
              color: _kSurface,
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.share_outlined, color: Colors.purpleAccent, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Sistema de Indicações (Referral)',
                      style: GoogleFonts.outfit(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _loadAllData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Atualizar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),

          // Main Layout
          Expanded(
            child: _isLoadingSettings
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // KPIs Row
                        Row(
                          children: [
                            _buildKpiCard(
                              title: 'Total de Indicações',
                              value: _totalReferrals.toString(),
                              icon: Icons.people_outline,
                              color: Colors.blueAccent,
                            ),
                            const SizedBox(width: 16),
                            _buildKpiCard(
                              title: 'Bônus Pago (Carteira)',
                              value: 'R\$ ${_totalPaidOut.toStringAsFixed(2)}',
                              icon: Icons.monetization_on_outlined,
                              color: Colors.greenAccent,
                            ),
                            const SizedBox(width: 16),
                            _buildKpiCard(
                              title: 'Aguardando Corrida (Pendente)',
                              value: _pendingReferrals.toString(),
                              icon: Icons.hourglass_empty,
                              color: Colors.orangeAccent,
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left Column: Configuration Settings
                            SizedBox(
                              width: 400,
                              child: Card(
                                color: _kSurface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: const BorderSide(color: _kBorder),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Configurar Programa',
                                        style: GoogleFonts.outfit(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      SwitchListTile(
                                        title: const Text(
                                          'Programa Ativado',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                        subtitle: const Text(
                                          'Habilita/Desabilita o bônus de indicação.',
                                          style: TextStyle(color: _kSubtext, fontSize: 12),
                                        ),
                                        value: _referralEnabled,
                                        activeThumbColor: Colors.purpleAccent,
                                        onChanged: (val) {
                                          setState(() => _referralEnabled = val);
                                        },
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      const SizedBox(height: 24),
                                      TextField(
                                        controller: _bonusReferrerCtrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: const TextStyle(color: Colors.white),
                                        decoration: const InputDecoration(
                                          labelText: 'Recompensa de quem indica (R\$)',
                                          labelStyle: TextStyle(color: _kSubtext),
                                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: _kBorder)),
                                          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: _kPrimary)),
                                          prefixText: 'R\$ ',
                                          prefixStyle: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      TextField(
                                        controller: _bonusReferredCtrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: const TextStyle(color: Colors.white),
                                        decoration: const InputDecoration(
                                          labelText: 'Recompensa de quem é indicado (R\$)',
                                          labelStyle: TextStyle(color: _kSubtext),
                                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: _kBorder)),
                                          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: _kPrimary)),
                                          prefixText: 'R\$ ',
                                          prefixStyle: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                      const SizedBox(height: 32),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 50,
                                        child: ElevatedButton(
                                          onPressed: _isSavingSettings ? null : _saveSettings,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.purpleAccent,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          child: _isSavingSettings
                                              ? const SizedBox(
                                                  height: 20,
                                                  width: 20,
                                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                )
                                              : const Text('Salvar Regras de Indicação'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 32),

                            // Right Column: Referral Logs Table
                            Expanded(
                              child: Card(
                                color: _kSurface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: const BorderSide(color: _kBorder),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Feed de Indicações Ativas',
                                        style: GoogleFonts.outfit(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      _isLoadingReferrals
                                          ? const Center(child: CircularProgressIndicator())
                                          : _referralsList.isEmpty
                                              ? const Center(
                                                  child: Padding(
                                                    padding: EdgeInsets.all(48.0),
                                                    child: Text('Nenhuma indicação registrada no momento.',
                                                        style: TextStyle(color: _kSubtext)),
                                                  ),
                                                )
                                              : _buildReferralsTable(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferralsTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(_kBackground.withOpacity(0.6)),
        dividerThickness: 0.5,
        columnSpacing: 24,
        columns: const [
          DataColumn(label: Text('Indicador', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Indicado', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Status', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Prêmio', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Cadastro Em', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Ações', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ],
        rows: _referralsList.map((ref) {
          final referrer = ref['referrer'] as Map?;
          final referred = ref['referred'] as Map?;
          final status = ref['status'] as String?;
          final amount = (ref['reward_amount'] as num?)?.toDouble() ?? 0.0;
          final date = ref['created_at'] != null ? DateTime.parse(ref['created_at']).toLocal() : null;

          final referrerName = referrer?['full_name'] ?? 'Desconhecido';
          final referrerPhone = referrer?['phone_number'] ?? '';

          final referredName = referred?['full_name'] ?? 'Desconhecido';
          final referredPhone = referred?['phone_number'] ?? '';

          final dateStr = date != null ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}' : '-';

          return DataRow(cells: [
            DataCell(Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(referrerName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                if (referrerPhone.isNotEmpty) Text(referrerPhone, style: const TextStyle(color: _kSubtext, fontSize: 11)),
              ],
            )),
            DataCell(Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(referredName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                if (referredPhone.isNotEmpty) Text(referredPhone, style: const TextStyle(color: _kSubtext, fontSize: 11)),
              ],
            )),
            DataCell(_StatusChip(status: status)),
            DataCell(Text('R\$ ${amount.toStringAsFixed(2)}',
                style: TextStyle(
                    color: status == 'completed' ? Colors.greenAccent : _kSubtext,
                    fontWeight: FontWeight.w600,
                    fontSize: 13))),
            DataCell(Text(dateStr, style: const TextStyle(color: Colors.white70, fontSize: 13))),
            DataCell(
              status == 'pending'
                  ? TextButton(
                      onPressed: () => _completeReferralManually(ref['id'], ref['referred_id'] ?? ''),
                      style: TextButton.styleFrom(foregroundColor: Colors.purpleAccent),
                      child: const Text('Completar Manual'),
                    )
                  : const Text('Concluído', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
            ),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Card(
        color: _kSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _kBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.outfit(color: _kSubtext, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String? status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    if (status == 'completed') {
      color = Colors.greenAccent;
      label = 'CONCLUÍDO';
    } else {
      color = Colors.orangeAccent;
      label = 'PENDENTE';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
