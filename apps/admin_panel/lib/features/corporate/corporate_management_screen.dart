import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class CorporateManagementScreen extends StatefulWidget {
  const CorporateManagementScreen({super.key});

  @override
  State<CorporateManagementScreen> createState() => _CorporateManagementScreenState();
}

class _CorporateManagementScreenState extends State<CorporateManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SupabaseClient _supabase = Supabase.instance.client;

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

  // Diálogo para criar/editar Conta Corporativa
  void _showCorporateAccountDialog({Map<String, dynamic>? account}) {
    final nameController = TextEditingController(text: account?['company_name']);
    final limitController = TextEditingController(text: account?['credit_limit']?.toString() ?? '1000.00');
    final balanceController = TextEditingController(text: account?['balance']?.toString() ?? '500.00');
    bool isActive = account?['is_active'] ?? true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                account == null ? 'Nova Conta Corporativa B2B' : 'Editar Conta Corporativa',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Nome da Empresa',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF096EFF))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: limitController,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Limite de Crédito (R\$)',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF096EFF))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: balanceController,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Saldo Inicial (R\$)',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF096EFF))),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Conta Ativa:', style: TextStyle(color: Colors.white70)),
                        Switch(
                          value: isActive,
                          activeThumbColor: const Color(0xFF096EFF),
                          onChanged: (val) => setDialogState(() => isActive = val),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) return;
                    final limit = double.tryParse(limitController.text) ?? 0.0;
                    final balance = double.tryParse(balanceController.text) ?? 0.0;

                    final data = {
                      'company_name': nameController.text.trim(),
                      'credit_limit': limit,
                      'balance': balance,
                      'is_active': isActive,
                    };

                    if (account == null) {
                      await _supabase.from('corporate_accounts').insert(data);
                    } else {
                      await _supabase.from('corporate_accounts').update(data).eq('id', account['id']);
                    }
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF096EFF)),
                  child: Text(account == null ? 'Criar' : 'Salvar', style: const TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Diálogo para criar/editar Voucher Corporativo
  void _showVoucherDialog({Map<String, dynamic>? voucher, required List<Map<String, dynamic>> corporates}) {
    if (corporates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, crie uma conta corporativa antes de gerar vouchers.')),
      );
      return;
    }

    final codeController = TextEditingController(text: voucher?['code']);
    final subsidyController = TextEditingController(text: voucher?['subsidy_flat']?.toString() ?? '10.00');
    final maxUsesController = TextEditingController(text: voucher?['max_uses_per_rider']?.toString() ?? '1');
    String selectedCorpId = voucher?['corporate_id']?.toString() ?? corporates.first['id'].toString();
    bool isActive = voucher?['is_active'] ?? true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                voucher == null ? 'Novo Voucher Subsídio B2B' : 'Editar Voucher',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedCorpId,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Parceiro Corporativo',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                      ),
                      items: corporates.map((c) {
                        return DropdownMenuItem<String>(
                          value: c['id'].toString(),
                          child: Text(c['company_name']?.toString() ?? ''),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedCorpId = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: codeController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Código do Cupom/Voucher',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF096EFF))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: subsidyController,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Valor do Subsídio Fixo (R\$)',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF096EFF))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: maxUsesController,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Máx de Usos por Passageiro',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF096EFF))),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Voucher Ativo:', style: TextStyle(color: Colors.white70)),
                        Switch(
                          value: isActive,
                          activeThumbColor: const Color(0xFF096EFF),
                          onChanged: (val) => setDialogState(() => isActive = val),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (codeController.text.trim().isEmpty) return;
                    final subsidy = double.tryParse(subsidyController.text) ?? 0.0;
                    final maxUses = int.tryParse(maxUsesController.text) ?? 1;

                    final data = {
                      'corporate_id': selectedCorpId,
                      'code': codeController.text.trim().toUpperCase(),
                      'subsidy_flat': subsidy,
                      'max_uses_per_rider': maxUses,
                      'is_active': isActive,
                    };

                    if (voucher == null) {
                      await _supabase.from('corporate_vouchers').insert(data);
                    } else {
                      await _supabase.from('corporate_vouchers').update(data).eq('id', voucher['id']);
                    }
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF096EFF)),
                  child: Text(voucher == null ? 'Criar' : 'Salvar', style: const TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Deletar Conta
  void _deleteCorporateAccount(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Excluir Conta Corporativa'),
        content: const Text('Tem certeza que deseja excluir esta conta corporativa? Todos os vouchers e transações vinculados serão deletados permanentemente.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Não', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sim, Excluir'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _supabase.from('corporate_accounts').delete().eq('id', id);
    }
  }

  // Deletar Voucher
  void _deleteVoucher(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Excluir Voucher'),
        content: const Text('Tem certeza que deseja excluir este voucher?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Não', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sim, Excluir'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _supabase.from('corporate_vouchers').delete().eq('id', id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        title: Text(
          'Gestão Corporativa B2B',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.colorScheme.primary,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Parceiros B2B'),
            Tab(text: 'Vouchers de Subsídio'),
            Tab(text: 'Histórico de Transações'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCorporateAccountsTab(),
          _buildVouchersTab(),
          _buildTransactionsTab(),
        ],
      ),
    );
  }

  // ABA 1: Parceiros B2B
  Widget _buildCorporateAccountsTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Gerencie as empresas e seus respectivos limites de subsídio para viagens corporativas split.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              ElevatedButton.icon(
                onPressed: () => _showCorporateAccountDialog(),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('Nova Conta B2B', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _supabase.from('corporate_accounts').stream(primaryKey: ['id']).order('company_name'),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Erro: ${snap.error}', style: const TextStyle(color: Colors.redAccent)));
              }
              final list = snap.data ?? [];
              if (list.isEmpty) {
                return const Center(child: Text('Nenhuma conta corporativa encontrada.', style: TextStyle(color: Colors.white38)));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final item = list[index];
                  final isActive = item['is_active'] == true;
                  final balance = (item['balance'] as num?)?.toDouble() ?? 0.0;
                  final limit = (item['credit_limit'] as num?)?.toDouble() ?? 0.0;

                  return Card(
                    color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                        backgroundColor: isActive ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                        child: Icon(Icons.business, color: isActive ? Colors.greenAccent : Colors.redAccent),
                      ),
                      title: Text(
                        item['company_name']?.toString() ?? '',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Saldo Disponível: R\$ ${balance.toStringAsFixed(2)}  •  Limite: R\$ ${limit.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blueAccent),
                            onPressed: () => _showCorporateAccountDialog(account: item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () => _deleteCorporateAccount(item['id']),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ABA 2: Vouchers de Subsídio
  Widget _buildVouchersTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supabase.from('corporate_accounts').stream(primaryKey: ['id']),
      builder: (context, corpSnap) {
        final corps = corpSnap.data ?? [];

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Crie e gerencie códigos de cupom associados a contas corporativas para subsídio automático.',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showVoucherDialog(corporates: corps),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Novo Voucher B2B', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _supabase.from('corporate_vouchers').stream(primaryKey: ['id']),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(child: Text('Erro: ${snap.error}', style: const TextStyle(color: Colors.redAccent)));
                  }
                  final list = snap.data ?? [];
                  if (list.isEmpty) {
                    return const Center(child: Text('Nenhum voucher corporativo encontrado.', style: TextStyle(color: Colors.white38)));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final item = list[index];
                      final isActive = item['is_active'] == true;
                      final subsidy = (item['subsidy_flat'] as num?)?.toDouble() ?? 0.0;
                      final maxUses = item['max_uses_per_rider'] ?? 1;

                      final corpName = corps.firstWhere(
                        (c) => c['id'].toString() == item['corporate_id']?.toString(),
                        orElse: () => {'company_name': 'Carregando...'},
                      )['company_name'];

                      return Card(
                        color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            backgroundColor: isActive ? Colors.amber.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                            child: Icon(Icons.local_offer, color: isActive ? Colors.amberAccent : Colors.redAccent),
                          ),
                          title: Row(
                            children: [
                              Text(
                                item['code']?.toString() ?? '',
                                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'R\$ ${subsidy.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              'Empresa: $corpName  •  Usos Máx/Passageiro: $maxUses',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blueAccent),
                                onPressed: () => _showVoucherDialog(voucher: item, corporates: corps),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent),
                                onPressed: () => _deleteVoucher(item['id']),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ABA 3: Histórico de Transações
  Widget _buildTransactionsTab() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
          child: const Text(
            'Auditoria em tempo real de subsídios debitados das contas corporativas.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _supabase.from('corporate_transactions').stream(primaryKey: ['id']).order('created_at', ascending: false),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Erro: ${snap.error}', style: const TextStyle(color: Colors.redAccent)));
              }
              final list = snap.data ?? [];
              if (list.isEmpty) {
                return const Center(child: Text('Nenhuma transação corporativa registrada.', style: TextStyle(color: Colors.white38)));
              }

              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: _supabase.from('corporate_accounts').stream(primaryKey: ['id']),
                builder: (context, corpSnap) {
                  final corps = corpSnap.data ?? [];

                  return ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final tx = list[index];
                      final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
                      final isDebit = amount < 0;
                      final dateStr = tx['created_at'] != null 
                          ? DateTime.parse(tx['created_at'].toString()).toLocal().toString().substring(0, 16) 
                          : '';

                      final corpName = corps.firstWhere(
                        (c) => c['id'].toString() == tx['corporate_id']?.toString(),
                        orElse: () => {'company_name': 'Empresa Desconhecida'},
                      )['company_name'];

                      return Card(
                        color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDebit ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isDebit ? Icons.arrow_downward : Icons.arrow_upward,
                              color: isDebit ? Colors.redAccent : Colors.greenAccent,
                            ),
                          ),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                corpName,
                                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                '${isDebit ? "-" : "+"} R\$ ${amount.abs().toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: isDebit ? Colors.redAccent : Colors.greenAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    tx['description']?.toString() ?? '',
                                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  dateStr,
                                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
