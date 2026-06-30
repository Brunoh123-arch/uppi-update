import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tela God Mode: Integra as Edge Functions exclusivas do admin que o painel
/// ainda não usava: admin-actions, admin-recharge-wallet, admin-insights (export CSV).
/// Inclui: recarga de carteira, zerar saldo, definir comissão, isenção, exportar CSV.
class AdminActionsScreen extends StatefulWidget {
  const AdminActionsScreen({super.key});

  @override
  State<AdminActionsScreen> createState() => _AdminActionsScreenState();
}

class _AdminActionsScreenState extends State<AdminActionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;

  // BUG FIX #12: Controllers criados aqui (no State), nunca dentro de build().
  // Criá-los dentro de build() causa memory leak e perda de estado a cada rebuild.

  // Tab 1 — Carteiras
  final _userIdCtrl    = TextEditingController();
  final _amountCtrl    = TextEditingController();
  final _descCtrl      = TextEditingController();
  final _zeroIdCtrl    = TextEditingController();

  // Tab 2 — Comissões
  final _driverIdsCtrl   = TextEditingController();
  final _commissionCtrl  = TextEditingController();
  final _exemptDaysCtrl  = TextEditingController();
  final _globalCommCtrl  = TextEditingController();
  final _exemptIdsCtrl   = TextEditingController();

  // Tab 3 — Export
  final _startCtrl = TextEditingController();
  final _endCtrl   = TextEditingController();
  String _exportStatus = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    // Dispose all controllers to prevent memory leaks
    _userIdCtrl.dispose();
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _zeroIdCtrl.dispose();
    _driverIdsCtrl.dispose();
    _commissionCtrl.dispose();
    _exemptDaysCtrl.dispose();
    _globalCommCtrl.dispose();
    _exemptIdsCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _invokeAdminAction(String action, Map<String, dynamic> params) async {
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'admin-actions',
        body: {'action': action, ...params},
      );
      if (res.status != 200) throw Exception(res.data?.toString() ?? 'Erro desconhecido');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ $action executado com sucesso!'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Erro: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
                children: [
                  Text('Ações Avançadas (Edge Functions)',
                      style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.4)),
                    ),
                    child: const Text('GOD MODE', style: TextStyle(color: Colors.deepPurpleAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  if (_isLoading) ...[
                    const SizedBox(width: 16),
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.deepPurpleAccent,
                labelColor: Colors.deepPurpleAccent,
                unselectedLabelColor: Colors.white54,
                tabs: const [
                  Tab(icon: Icon(Icons.account_balance_wallet, size: 18), text: 'Carteiras'),
                  Tab(icon: Icon(Icons.percent, size: 18), text: 'Comissões'),
                  Tab(icon: Icon(Icons.download, size: 18), text: 'Exportar Dados'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildWalletActionsTab(),
              _buildCommissionActionsTab(),
              _buildExportTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ─── TAB 1: Carteiras ───────────────────────────────────────
  Widget _buildWalletActionsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionCard(
            title: '💰 Recarregar Carteira (admin-recharge-wallet)',
            subtitle: 'Adiciona saldo à carteira de qualquer usuário via Edge Function segura.',
            color: Colors.greenAccent,
            child: Column(
              children: [
                _buildTextField(_userIdCtrl, 'ID do Usuário (UUID)', Icons.person),
                const SizedBox(height: 12),
                _buildTextField(_amountCtrl, 'Valor em R\$', Icons.attach_money, isNumber: true),
                const SizedBox(height: 12),
                _buildTextField(_descCtrl, 'Descrição (ex: Bônus de cadastro)', Icons.description),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (_userIdCtrl.text.isEmpty || _amountCtrl.text.isEmpty) return;
                      setState(() => _isLoading = true);
                      try {
                        final res = await Supabase.instance.client.functions.invoke(
                          'admin-recharge-wallet',
                          body: {
                            'userId': _userIdCtrl.text.trim(),
                            'amount': double.tryParse(_amountCtrl.text) ?? 0,
                            'currency': 'BRL',
                            'description': _descCtrl.text.isNotEmpty ? _descCtrl.text : 'Recarga pelo admin',
                          },
                        );
                        if (res.status != 200) throw Exception(res.data?.toString());
                        if (mounted) {
                          _userIdCtrl.clear(); _amountCtrl.clear(); _descCtrl.clear();
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('✅ Carteira recarregada com sucesso!'),
                            backgroundColor: Colors.green,
                          ));
                        }
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red));
                      } finally {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    },
                    icon: const Icon(Icons.add_card),
                    label: const Text('Recarregar Carteira'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.withOpacity(0.2),
                      foregroundColor: Colors.greenAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          _SectionCard(
            title: '🔴 Zerar Carteira do Motorista (admin-actions: zeroDriverWallet)',
            subtitle: 'Zera completamente o saldo do motorista. Ação irreversível — auditada.',
            color: Colors.redAccent,
            child: Column(
              children: [
                _buildTextField(_zeroIdCtrl, 'ID do Motorista (UUID)', Icons.drive_eta),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (_zeroIdCtrl.text.isEmpty) return;
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: Theme.of(context).colorScheme.surface,
                          title: const Text('⚠️ Zerar Carteira?'),
                          content: const Text('Esta ação é irreversível. O saldo do motorista será zerado e a transação registrada no audit log.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Confirmar'),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                      await _invokeAdminAction('zeroDriverWallet', {'driverId': _zeroIdCtrl.text.trim()});
                      _zeroIdCtrl.clear();
                    },
                    icon: const Icon(Icons.money_off),
                    label: const Text('Zerar Saldo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withOpacity(0.2),
                      foregroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── TAB 2: Comissões ────────────────────────────────────────
  Widget _buildCommissionActionsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          _SectionCard(
            title: '🎯 Comissão Individual por Motorista',
            subtitle: 'Define uma taxa de comissão específica para um ou mais motoristas (separar IDs por vírgula).',
            color: Colors.orangeAccent,
            child: Column(
              children: [
                _buildTextField(_driverIdsCtrl, 'IDs dos Motoristas (separados por vírgula)', Icons.people),
                const SizedBox(height: 12),
                _buildTextField(_commissionCtrl, 'Comissão % (ex: 12 = 12%)', Icons.percent, isNumber: true),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final ids = _driverIdsCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                      final pct = double.tryParse(_commissionCtrl.text) ?? 0;
                      if (ids.isEmpty) return;
                      await _invokeAdminAction('setDriverCommission', {'driverIds': ids, 'commissionPercentage': pct});
                    },
                    icon: const Icon(Icons.tune),
                    label: const Text('Aplicar Comissão'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.withOpacity(0.2),
                      foregroundColor: Colors.orangeAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          _SectionCard(
            title: '🎁 Isenção de Comissão (Temporária)',
            subtitle: 'Concede isenção total de comissão por N dias para os motoristas especificados.',
            color: Colors.blueAccent,
            child: Column(
              children: [
                _buildTextField(_exemptIdsCtrl, 'IDs dos Motoristas (separados por vírgula)', Icons.people),
                const SizedBox(height: 12),
                _buildTextField(_exemptDaysCtrl, 'Dias de Isenção (1–365)', Icons.calendar_today, isNumber: true),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final ids = _exemptIdsCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                      final days = int.tryParse(_exemptDaysCtrl.text) ?? 0;
                      if (ids.isEmpty || days < 1) return;
                      await _invokeAdminAction('grantCommissionExemption', {'driverIds': ids, 'exemptionDays': days});
                    },
                    icon: const Icon(Icons.card_giftcard),
                    label: const Text('Conceder Isenção'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.withValues(alpha: 0.15),
                      foregroundColor: Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          _SectionCard(
            title: '🌐 Comissão Global da Plataforma',
            subtitle: 'Altera a taxa de comissão padrão da plataforma (salva em app_settings.commission_rate).',
            color: Colors.purpleAccent,
            child: Column(
              children: [
                _buildTextField(_globalCommCtrl, 'Nova comissão global % (ex: 15)', Icons.percent, isNumber: true),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final pct = double.tryParse(_globalCommCtrl.text) ?? 0;
                      await _invokeAdminAction('updatePlatformCommission', {'commissionPercentage': pct});
                    },
                    icon: const Icon(Icons.public),
                    label: const Text('Atualizar Comissão Global'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.withOpacity(0.2),
                      foregroundColor: Colors.purpleAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── TAB 3: Exportar Dados ───────────────────────────────────
  Widget _buildExportTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          _SectionCard(
            title: '📊 Exportar Corridas em CSV (admin-insights)',
            subtitle: 'Gera um CSV com até 1.000 corridas no período selecionado. Inclui: ID, status, passageiro, motorista, valor.',
            color: Colors.blueAccent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _buildTextField(_startCtrl, 'Data início (YYYY-MM-DD)', Icons.calendar_today)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildTextField(_endCtrl, 'Data fim (YYYY-MM-DD)', Icons.calendar_today)),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      setState(() => _exportStatus = 'Gerando exportação...');
                      try {
                        final res = await Supabase.instance.client.functions.invoke(
                          'admin-insights',
                          body: {
                            'action': 'export',
                            'startDate': _startCtrl.text.isNotEmpty ? '${_startCtrl.text}T00:00:00Z' : null,
                            'endDate': _endCtrl.text.isNotEmpty ? '${_endCtrl.text}T23:59:59Z' : null,
                          },
                        );
                        if (res.status != 200) throw Exception(res.data?.toString());
                        final count = res.data?['count'] ?? 0;
                        setState(() => _exportStatus = '✅ $count corridas exportadas com sucesso! (CSV gerado)');
                      } catch (e) {
                        setState(() => _exportStatus = '❌ Erro: $e');
                      }
                    },
                    icon: const Icon(Icons.download),
                    label: const Text('Gerar CSV'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.withOpacity(0.2),
                      foregroundColor: Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                if (_exportStatus.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(_exportStatus, style: const TextStyle(color: Colors.white70)),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          const _SectionCard(
            title: '🗑️ Deletar Conta de Usuário (delete-user-account)',
            subtitle: 'Soft-delete: limpa dados pessoais, cancela corridas ativas e marca conta como deletada.',
            color: Colors.redAccent,
            child: _DeleteUserWidget(),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool isNumber = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        filled: true,
        fillColor: Colors.black12,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.deepPurpleAccent, width: 1.5),
        ),
      ),
    );
  }
}

// Widget separado para deletar usuário com estado próprio
class _DeleteUserWidget extends StatefulWidget {
  const _DeleteUserWidget();

  @override
  State<_DeleteUserWidget> createState() => _DeleteUserWidgetState();
}

class _DeleteUserWidgetState extends State<_DeleteUserWidget> {
  final _uidCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _uidCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _uidCtrl,
          decoration: InputDecoration(
            labelText: 'ID do Usuário (UUID)',
            prefixIcon: const Icon(Icons.person_off, size: 18),
            filled: true,
            fillColor: Colors.black12,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _loading ? null : () async {
              if (_uidCtrl.text.isEmpty) return;
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  title: const Text('⚠️ Deletar Conta?'),
                  content: const Text('Isso apagará os dados pessoais do usuário e cancelará todas as corridas ativas. Ação registrada em audit log.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Deletar'),
                    ),
                  ],
                ),
              );
              if (confirm != true) return;
              setState(() => _loading = true);
              try {
                final res = await Supabase.instance.client.functions.invoke(
                  'delete-user-account',
                  body: {'uid': _uidCtrl.text.trim()},
                );
                if (res.status != 200) throw Exception(res.data?.toString());
                _uidCtrl.clear();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Conta deletada com sucesso.'), backgroundColor: Colors.green));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Erro: $e'), backgroundColor: Colors.red));
              } finally {
                if (mounted) setState(() => _loading = false);
              }
            },
            icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_forever),
            label: const Text('Deletar Conta'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.withOpacity(0.2),
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final Widget child;

  const _SectionCard({required this.title, required this.subtitle, required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 20),
          const Divider(color: Colors.white10),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
