import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tela God Mode: Visualiza e gerencia TODOS os métodos de pagamento
/// dos passageiros e contas de saque (PIX/banco) dos motoristas.
/// Permite excluir métodos problemáticos e ver detalhes completos.
class UserPaymentMethodsScreen extends StatefulWidget {
  const UserPaymentMethodsScreen({super.key});

  @override
  State<UserPaymentMethodsScreen> createState() =>
      _UserPaymentMethodsScreenState();
}

class _UserPaymentMethodsScreenState extends State<UserPaymentMethodsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';

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
        // Header
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
                    'Métodos de Pagamento & Contas de Saque',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(
                    width: 300,
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Buscar por nome ou ID...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.black12,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.tealAccent,
                labelColor: Colors.tealAccent,
                unselectedLabelColor: Colors.white54,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.credit_card, size: 18),
                    text: 'Pagamentos (Passageiros)',
                  ),
                  Tab(
                    icon: Icon(Icons.account_balance, size: 18),
                    text: 'Contas de Saque (Motoristas)',
                  ),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPaymentMethodsTab(),
              _buildPayoutAccountsTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 1: Payment Methods (Passageiros)
  // ==========================================
  Widget _buildPaymentMethodsTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('payment_methods')
          .stream(primaryKey: ['id']),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Erro: ${snapshot.error}',
                style: const TextStyle(color: Colors.redAccent)),
          );
        }

        var methods = snapshot.data!;

        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          methods = methods.where((m) {
            final userId = (m['user_id'] ?? '').toString().toLowerCase();
            final type = (m['type'] ?? '').toString().toLowerCase();
            final title = (m['title'] ?? '').toString().toLowerCase();
            return userId.contains(q) ||
                type.contains(q) ||
                title.contains(q);
          }).toList();
        }

        if (methods.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.credit_card_off, color: Colors.white24, size: 64),
                SizedBox(height: 16),
                Text('Nenhum método de pagamento encontrado.',
                    style: TextStyle(color: Colors.white54)),
              ],
            ),
          );
        }

        // Group by user_id
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (var m in methods) {
          final uid = m['user_id']?.toString() ?? 'unknown';
          grouped.putIfAbsent(uid, () => []).add(m);
        }

        final userIds = grouped.keys.toList();

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: userIds.length,
          itemBuilder: (context, index) {
            final userId = userIds[index];
            final userMethods = grouped[userId]!;

            return FutureBuilder(
              future: Supabase.instance.client
                  .from('profiles')
                  .select('full_name, phone_number')
                  .eq('id', userId)
                  .maybeSingle(),
              builder: (ctx, AsyncSnapshot<Map<String, dynamic>?> snap) {
                final name = snap.data?['full_name'] ?? 'Carregando...';
                final phone = snap.data?['phone_number'] ?? '';

                return Card(
                  color: Theme.of(context).colorScheme.surface.withAlpha(200),
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.tealAccent.withOpacity(0.15),
                      child: const Icon(Icons.person, color: Colors.tealAccent),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Text(
                      '📱 $phone | ${userMethods.length} método(s)',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    children: userMethods.map((m) {
                      final type = m['type']?.toString() ?? 'unknown';
                      final title = m['title']?.toString() ??
                          m['card_brand']?.toString() ??
                          type;
                      final last4 = m['last_four']?.toString() ?? '';
                      final isDefault = m['is_default'] == true;
                      final createdAt =
                          m['created_at']?.toString().substring(0, 16) ?? '';

                      IconData typeIcon;
                      Color typeColor;
                      switch (type.toLowerCase()) {
                        case 'credit_card':
                        case 'debit_card':
                        case 'card':
                          typeIcon = Icons.credit_card;
                          typeColor = Colors.blueAccent;
                          break;
                        case 'pix':
                          typeIcon = Icons.qr_code;
                          typeColor = Colors.greenAccent;
                          break;
                        case 'cash':
                        case 'dinheiro':
                          typeIcon = Icons.money;
                          typeColor = Colors.amberAccent;
                          break;
                        default:
                          typeIcon = Icons.payment;
                          typeColor = Colors.white54;
                      }

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 4),
                        leading: Icon(typeIcon, color: typeColor),
                        title: Row(
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            if (last4.isNotEmpty)
                              Text(' •••• $last4',
                                  style:
                                      const TextStyle(color: Colors.white38)),
                            if (isDefault)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('Padrão',
                                    style: TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 10)),
                              ),
                          ],
                        ),
                        subtitle: Text('Criado: $createdAt',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent, size: 20),
                          tooltip: 'Excluir método de pagamento',
                          onPressed: () =>
                              _deletePaymentMethod(m['id'].toString(), userId),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ==========================================
  // TAB 2: Payout Accounts (Motoristas)
  // ==========================================
  Widget _buildPayoutAccountsTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('payout_accounts')
          .stream(primaryKey: ['id']),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var accounts = snapshot.data!;

        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          accounts = accounts.where((a) {
            final driverId = (a['driver_id'] ?? '').toString().toLowerCase();
            final bankName = (a['bank_name'] ?? '').toString().toLowerCase();
            final accountNumber =
                (a['account_number'] ?? '').toString().toLowerCase();
            return driverId.contains(q) ||
                bankName.contains(q) ||
                accountNumber.contains(q);
          }).toList();
        }

        if (accounts.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.account_balance_outlined,
                    color: Colors.white24, size: 64),
                SizedBox(height: 16),
                Text('Nenhuma conta de saque cadastrada.',
                    style: TextStyle(color: Colors.white54)),
              ],
            ),
          );
        }

        // Group by driver_id
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (var a in accounts) {
          final uid = a['driver_id']?.toString() ?? 'unknown';
          grouped.putIfAbsent(uid, () => []).add(a);
        }

        final driverIds = grouped.keys.toList();

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: driverIds.length,
          itemBuilder: (context, index) {
            final driverId = driverIds[index];
            final driverAccounts = grouped[driverId]!;

            return FutureBuilder(
              future: Supabase.instance.client
                  .from('profiles')
                  .select('full_name, phone_number')
                  .eq('id', driverId)
                  .maybeSingle(),
              builder: (ctx, AsyncSnapshot<Map<String, dynamic>?> snap) {
                final name = snap.data?['full_name'] ?? 'Carregando...';
                final phone = snap.data?['phone_number'] ?? '';

                return Card(
                  color: Theme.of(context).colorScheme.surface.withAlpha(200),
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orangeAccent.withOpacity(0.15),
                      child:
                          const Icon(Icons.drive_eta, color: Colors.orangeAccent),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Text(
                      '📱 $phone | ${driverAccounts.length} conta(s)',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    children: driverAccounts.map((a) {
                      final bankName =
                          a['bank_name']?.toString() ?? 'Não informado';
                      final accountNumber = a['account_number']?.toString() ??
                          a['pix_key']?.toString() ??
                          '';
                      final accountType =
                          a['account_type']?.toString() ?? 'pix';
                      final isDefault = a['is_default'] == true;
                      final isVerified = a['is_verified'] == true;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 8),
                        leading: Icon(
                          accountType.toLowerCase().contains('pix')
                              ? Icons.qr_code
                              : Icons.account_balance,
                          color: Colors.orangeAccent,
                        ),
                        title: Row(
                          children: [
                            Text(bankName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            if (isDefault)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('Padrão',
                                    style: TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 10)),
                              ),
                            if (isVerified)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('Verificada',
                                    style: TextStyle(
                                        color: Colors.blueAccent,
                                        fontSize: 10)),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          'Conta/PIX: $accountNumber | Tipo: $accountType',
                          style:
                              const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isVerified)
                              IconButton(
                                icon: const Icon(Icons.verified,
                                    color: Colors.greenAccent, size: 20),
                                tooltip: 'Marcar como verificada',
                                onPressed: () =>
                                    _verifyPayoutAccount(a['id'].toString(), driverId),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent, size: 20),
                              tooltip: 'Excluir conta de saque',
                              onPressed: () =>
                                  _deletePayoutAccount(a['id'].toString(), driverId),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ==========================================
  // Actions
  // ==========================================
  Future<void> _deletePaymentMethod(String methodId, String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Excluir Método de Pagamento?'),
        content: const Text(
            'O passageiro perderá este método de pagamento e precisará cadastrar novamente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Supabase.instance.client
          .from('payment_methods')
          .delete()
          .eq('id', methodId);

      final adminId =
          Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'payment_method_deleted',
        'target_user_id': userId,
        'target_resource_id': methodId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Método de pagamento excluído.'),
              backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _verifyPayoutAccount(String accountId, String driverId) async {
    try {
      await Supabase.instance.client
          .from('payout_accounts')
          .update({'is_verified': true}).eq('id', accountId);

      final adminId =
          Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'payout_account_verified',
        'target_user_id': driverId,
        'target_resource_id': accountId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Conta verificada com sucesso!'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deletePayoutAccount(String accountId, String driverId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Excluir Conta de Saque?'),
        content: const Text(
            'O motorista perderá esta conta e não poderá receber pagamentos nela até recadastrar.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Supabase.instance.client
          .from('payout_accounts')
          .delete()
          .eq('id', accountId);

      final adminId =
          Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'payout_account_deleted',
        'target_user_id': driverId,
        'target_resource_id': accountId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Conta de saque excluída.'),
              backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
