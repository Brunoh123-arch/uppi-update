import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class FinancialsScreen extends StatefulWidget {
  const FinancialsScreen({super.key});

  @override
  State<FinancialsScreen> createState() => _FinancialsScreenState();
}

class _FinancialsScreenState extends State<FinancialsScreen> {
  String _searchQuery = '';
  double _totalPending = 0;
  Map<String, Map<String, dynamic>> _surgicalDriverStats = {};
  RealtimeChannel? _txChannel;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _fetchSurgicalDriverStats();
    _startRealtimeChannels();
  }

  void _startRealtimeChannels() {
    _txChannel = Supabase.instance.client.channel('financials_tx')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'wallet_transactions',
        callback: (payload) => _onDataChanged(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'rides',
        callback: (payload) => _onDataChanged(),
      )
      .subscribe();
  }

  void _onDataChanged() {
    if (_debounceTimer?.isActive ?? false) return;
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) _fetchSurgicalDriverStats();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _txChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchSurgicalDriverStats() async {
    try {
      final response = await Supabase.instance.client.rpc('get_driver_surgical_financials');
      if (response != null && response is List) {
        if (mounted) {
          setState(() {
            _surgicalDriverStats = {
              for (var row in response)
                row['driver_id'] as String: row as Map<String, dynamic>
            };
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching surgical stats: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: const Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Centro Financeiro & Payouts',
                      style: GoogleFonts.outfit(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(
                      width: 280,
                      child: TextField(
                        onChanged: (v) => setState(() => _searchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Buscar motorista...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.black12,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0),
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
                const TabBar(
                  indicatorColor: Colors.blueAccent,
                  tabs: [
                    Tab(text: 'Visão Geral (Carteiras)'),
                    Tab(text: 'Solicitações de Saque Pendentes'),
                    Tab(text: 'Histórico de Cancelamentos'),
                  ],
                ),
              ],
            ),
          ),
          // KPI summary bar
          _SurgicalAnalyticsWidget(totalPending: _totalPending),
          Expanded(
            child: TabBarView(
              children: [
                // TAB 1: Visão Geral
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: Supabase.instance.client
                .from('profiles')
                .stream(primaryKey: ['id'])
                .eq('role', 'driver')
                .order('wallet_balance', ascending: false)
                .limit(100),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Erro: ${snapshot.error}',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                );
              }

              var drivers = snapshot.data!;

              // Update summary totals
              double pend = 0;
              for (var d in drivers) {
                final b = (d['wallet_balance'] as num?)?.toDouble() ?? 0;
                if (b > 0) pend += b;
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && (_totalPending != pend)) {
                  setState(() {
                    _totalPending = pend;
                  });
                }
              });

              if (_searchQuery.isNotEmpty) {
                final q = _searchQuery.toLowerCase();
                drivers = drivers.where((d) {
                  final name = (d['full_name'] ?? '').toString().toLowerCase();
                  final phone = (d['phone_number'] ?? '').toString().toLowerCase();
                  return name.contains(q) || phone.contains(q);
                }).toList();
              }

              if (drivers.isEmpty) {
                return const Center(
                  child: Text(
                    'Nenhum motorista encontrado.',
                    style: TextStyle(color: Colors.white54),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(32),
                itemCount: drivers.length,
                itemBuilder: (context, index) {
                  final d = drivers[index];
                  final name = (d['full_name'] ?? '').toString().trim();
                  final balance =
                      (d['wallet_balance'] as num?)?.toDouble() ?? 0.0;
                  final phone = d['phone_number'] ?? 'Sem telefone';
                  final bank = d['bank_account_number'] ?? '';
                  final bankName = d['bank_name'] ?? '';

                  return Card(
                    color: Theme.of(context).colorScheme.surface,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.2),
                            backgroundImage:
                                d['avatar_url'] != null
                                ? NetworkImage(d['avatar_url'])
                                : null,
                            child: d['avatar_url'] == null
                                ? const Icon(
                                    Icons.account_balance_wallet,
                                    color: Colors.blueAccent,
                                    size: 28,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isEmpty ? 'Motorista (sem nome)' : name,
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '📱 $phone',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 13,
                                  ),
                                ),
                                if (bank.isNotEmpty)
                                  Text(
                                    '🏦 $bankName ⸺ Pix: $bank',
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 12,
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                // Surgical Data Injection
                                if (_surgicalDriverStats.containsKey(d['id'].toString()))
                                  Builder(builder: (context) {
                                    final stats = _surgicalDriverStats[d['id'].toString()]!;
                                    return Row(
                                      children: [
                                        _MiniStat(label: 'Ganho Líquido', value: 'R\$ ${(stats['net_earnings'] as num).toStringAsFixed(2)}', color: Colors.green),
                                        const SizedBox(width: 12),
                                        _MiniStat(label: 'Faturamento', value: 'R\$ ${(stats['gross_revenue'] as num).toStringAsFixed(2)}', color: Colors.blueAccent),
                                        const SizedBox(width: 12),
                                        _MiniStat(label: 'Taxa Uppi', value: 'R\$ ${(stats['uppi_fee_despesas'] as num).toStringAsFixed(2)}', color: Colors.redAccent),
                                      ],
                                    );
                                  }),
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Saldo a Repassar',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                'R\$ ${balance.toStringAsFixed(2)}',
                                style: GoogleFonts.outfit(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: balance < 0
                                      ? Colors.redAccent
                                      : balance == 0
                                      ? Colors.white38
                                      : Colors.greenAccent,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 24),
                            Column(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _showExtract(
                                    context,
                                    d['id'].toString(),
                                    name,
                                  ),
                                  icon: const Icon(
                                    Icons.list_alt_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Extrato'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white10,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: balance > 0
                                      ? () => _processPayout(
                                          context,
                                          d['id'].toString(),
                                          name,
                                          balance,
                                        )
                                      : null,
                                  icon: const Icon(
                                    Icons.payments_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Zerar & Pagar'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.shade700,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: () => _showAdminWalletAdjustment(
                                    context,
                                    d['id'].toString(),
                                    name,
                                  ),
                                  icon: const Icon(
                                    Icons.security,
                                    size: 16,
                                  ),
                                  label: const Text('Ajuste Administrativo de Saldo'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent.shade700,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
                // TAB 2: Solicitações de Saque
                _buildPayoutRequestsTab(),
                // TAB 3: Histórico de Cancelamentos
                _buildCancellationLogsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayoutRequestsTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('payout_requests')
          .stream(primaryKey: ['id'])
          .eq('status', 'pending')
          .order('created_at', ascending: true)
          .limit(100),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));

        final requests = snapshot.data!;

        if (requests.isEmpty) {
          return const Center(
            child: Text('Nenhuma solicitação pendente.', style: TextStyle(color: Colors.white54)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(32),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final req = requests[index];
            final amount = (req['amount'] as num?)?.toDouble() ?? 0.0;
            final userId = req['driver_id'] ?? '';
            final date = DateTime.parse(req['created_at'].toString()).toLocal();

            return FutureBuilder(
              future: Future.wait([
                Supabase.instance.client.from('profiles').select('full_name').eq('id', userId).single(),
                Supabase.instance.client.from('payout_accounts').select('bank_name, account_number').eq('driver_id', userId).eq('is_default', true).maybeSingle()
              ]),
              builder: (ctx, AsyncSnapshot<List<dynamic>> snap) {
                final profile = snap.data?.elementAt(0) as Map<String, dynamic>? ?? {};
                final payoutAcc = snap.data?.elementAt(1) as Map<String, dynamic>? ?? {};
                
                final name = profile['full_name'] ?? 'Motorista';
                final bank = payoutAcc['account_number'] ?? 'Nenhuma chave cadastrada';
                final bankName = payoutAcc['bank_name'] ?? 'Não informado';

                return Card(
                  color: Theme.of(context).colorScheme.surface,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: const CircleAvatar(backgroundColor: Colors.orangeAccent, child: Icon(Icons.money_off)),
                    title: Text('$name solicitou saque de R\$ ${amount.abs().toStringAsFixed(2)}', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                    subtitle: Text('Data: ${date.toString().substring(0, 16)}\nBanco: $bankName | Conta/Pix: $bank'),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _approvePayout(req['id'].toString(), userId, amount, name),
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Aprovar & Pagar'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () => _rejectPayout(req['id'].toString(), userId, amount, name),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Recusar'),
                          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildCancellationLogsTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('ride_cancellations')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .limit(100),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));

        final logs = snapshot.data!;

        if (logs.isEmpty) {
          return const Center(
            child: Text('Nenhum registro de cancelamento encontrado.', style: TextStyle(color: Colors.white54)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(32),
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index];
            final fee = (log['cancellation_fee'] as num?)?.toDouble() ?? 0.0;
            final compensated = (log['driver_compensated_amount'] as num?)?.toDouble() ?? 0.0;
            final date = DateTime.parse(log['created_at'].toString()).toLocal();
            final rideId = log['ride_id'] ?? '';
            final cancelledBy = log['cancelled_by'] ?? '';

            return FutureBuilder(
              future: Future.wait([
                Supabase.instance.client.from('profiles').select('full_name, role').eq('id', cancelledBy).maybeSingle(),
                Supabase.instance.client.from('rides').select('rider_id, driver_id').eq('id', rideId).maybeSingle(),
              ]),
              builder: (ctx, AsyncSnapshot<List<dynamic>> snap) {
                final actorProfile = snap.data?.elementAt(0) as Map<String, dynamic>? ?? {};
                final rideInfo = snap.data?.elementAt(1) as Map<String, dynamic>? ?? {};

                final actorName = actorProfile['full_name'] ?? 'Usuário';
                final actorRole = actorProfile['role'] == 'driver' ? 'Motorista' : 'Passageiro';
                final riderId = rideInfo['rider_id'] ?? '';
                final driverId = rideInfo['driver_id'] ?? '';

                return FutureBuilder(
                  future: Future.wait<dynamic>([
                    if (riderId.isNotEmpty) Supabase.instance.client.from('profiles').select('full_name').eq('id', riderId).maybeSingle() else Future.value(null),
                    if (driverId.isNotEmpty) Supabase.instance.client.from('profiles').select('full_name').eq('id', driverId).maybeSingle() else Future.value(null),
                  ]),
                  builder: (ctx2, AsyncSnapshot<List<dynamic>> snap2) {
                    final riderName = (snap2.data?.elementAt(0) as Map<String, dynamic>?)?['full_name'] ?? 'Não informado';
                    final driverName = (snap2.data?.elementAt(1) as Map<String, dynamic>?)?['full_name'] ?? 'Não informado';

                    return Card(
                      color: Theme.of(context).colorScheme.surface,
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.orangeAccent.withOpacity(0.2),
                              child: const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cancelado por: $actorName ($actorRole)',
                                    style: GoogleFonts.outfit(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Corrida ID: ${rideId.toString().length > 8 ? rideId.toString().substring(0, 8) : rideId}...\nPassageiro: $riderName\nMotorista: $driverName\nData/Hora: ${date.toString().substring(0, 16)}',
                                    style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Taxa: R\$ ${fee.toStringAsFixed(2)}',
                                  style: GoogleFonts.outfit(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: fee > 0 ? Colors.redAccent : Colors.white38,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Comp.: R\$ ${compensated.toStringAsFixed(2)}',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: compensated > 0 ? Colors.greenAccent : Colors.white38,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _approvePayout(String reqId, String driverId, double amount, String driverName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprovar Saque?'),
        content: const Text('Isso confirmará o saque de forma oficial e atômica.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('Confirmar Pagamento')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await Supabase.instance.client.from('payout_requests').update({
        'status': 'processed',
        'processed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', reqId);
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saque aprovado com sucesso.'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao aprovar saque: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _rejectPayout(String reqId, String driverId, double amount, String driverName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recusar Saque?'),
        content: const Text('Isso cancelará o pedido e o valor retido retornará atomicamente para o saldo do motorista.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Sim, Recusar')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await Supabase.instance.client.from('payout_requests').update({
        'status': 'rejected',
        'rejection_reason': 'Recusado pelo administrador'
      }).eq('id', reqId);
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saque recusado e saldo estornado.'), backgroundColor: Colors.orange));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao recusar saque: $e'), backgroundColor: Colors.red));
    }
  }

  void _showExtract(BuildContext context, String driverId, String name) {
    showDialog(
      context: context,
      builder: (_) => _ExtractDialog(driverId: driverId, driverName: name),
    );
  }

  Future<void> _processPayout(
    BuildContext context,
    String driverId,
    String name,
    double amount,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Repasse'),
        content: Text(
          'Registrar repasse de R\$ ${amount.toStringAsFixed(2)} para $name?\n\nIsso vai zerar o saldo do motorista.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Confirmar',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // 1. Chamar a Edge Function segura para debitar o saldo e registrar a transação
      await Supabase.instance.client.functions.invoke(
        'admin-recharge-wallet',
        body: {
          'userId': driverId,
          'amount': -amount,
          'currency': 'BRL',
          'description': 'Repasse Administrativo (Saque)',
        },
      );

      // 2. Audit trail
      final adminId =
          Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'payout',
        'target_user_id': driverId,
        'details': {
          'amount': amount,
          'driver_name': name,
        },
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Repasse registrado! Saldo zerado.'),
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

  void _showAdminWalletAdjustment(
      BuildContext context, String userId, String name) {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Ajuste Administrativo de Saldo: $name',
          style: const TextStyle(color: Colors.redAccent),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ATENÇÃO: Valores positivos adicionam crédito à carteira. Valores negativos realizam débito (ex: descontos, multas). Ação com efeito imediato.',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              decoration: const InputDecoration(
                labelText: 'Valor (Ex: 50.00 ou -20.50)',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Motivo (Ex: Bônus de Meta, Estorno)',
                prefixIcon: Icon(Icons.description),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            icon: const Icon(Icons.security, color: Colors.white),
            label: const Text(
              'Executar Ajuste',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            onPressed: () async {
              final amount = double.tryParse(amountController.text);
              if (amount == null || amount == 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Insira um valor valido e diferente de zero.')),
                );
                return;
              }

              // Safety: warn if debit might cause negative balance
              if (amount < 0) {
                final profile = await Supabase.instance.client
                    .from('profiles')
                    .select('wallet_balance')
                    .eq('id', userId)
                    .maybeSingle();
                final currentBalance =
                    (profile?['wallet_balance'] as num?)?.toDouble() ?? 0.0;
                if ((currentBalance + amount) < 0 && ctx.mounted) {
                  final proceed = await showDialog<bool>(
                    context: ctx,
                    builder: (c) => AlertDialog(
                      title: const Text('Saldo ficara negativo!'),
                      content: Text(
                        'Saldo atual: R\$ ${currentBalance.toStringAsFixed(2)}\n'
                        'Debito: R\$ ${amount.toStringAsFixed(2)}\n'
                        'Resultado: R\$ ${(currentBalance + amount).toStringAsFixed(2)}\n\n'
                        'Deseja continuar mesmo assim?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Cancelar'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red),
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Sim, continuar',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  if (proceed != true) return;
                }
              }

              final desc = descriptionController.text.isEmpty
                  ? 'Ajuste Administrativo'
                  : descriptionController.text;

              try {
                final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN_ADMIN';
                
                // 1. Chamar a Edge Function segura para atualizar o saldo e registrar a transação
                await Supabase.instance.client.functions.invoke(
                  'admin-recharge-wallet',
                  body: {
                    'userId': userId,
                    'amount': amount,
                    'currency': 'BRL',
                    'description': desc,
                  },
                );

                // 2. Buscar a transação recém-criada pela Edge Function para obter o ID dela para o log de auditoria
                String txId = userId;
                try {
                  final latestTx = await Supabase.instance.client
                      .from('wallet_transactions')
                      .select('id')
                      .eq('user_id', userId)
                      .order('created_at', ascending: false)
                      .limit(1)
                      .maybeSingle();
                  if (latestTx != null) {
                    txId = latestTx['id'] as String;
                  }
                } catch (e) {
                  debugPrint('Erro ao buscar ID da transacao para o audit log: $e');
                }
                
                // 3. Log into admin_audit_log (Surgical Accountability)
                await Supabase.instance.client.from('admin_audit_log').insert({
                  'admin_id': adminId,
                  'action_type': 'wallet_adjustment',
                  'target_user_id': userId,
                  'target_resource_id': txId,
                  'details': {
                    'amount': amount,
                    'description': desc,
                  }
                });

                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ajuste concluído. R\$ $amount aplicado à carteira.'),
                      backgroundColor: amount > 0 ? Colors.green : Colors.red,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro na execução: $e')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SurgicalAnalyticsWidget extends StatefulWidget {
  final double totalPending;
  const _SurgicalAnalyticsWidget({required this.totalPending});

  @override
  State<_SurgicalAnalyticsWidget> createState() =>
      _SurgicalAnalyticsWidgetState();
}

class _SurgicalAnalyticsWidgetState extends State<_SurgicalAnalyticsWidget> {
  double totalGross = 0.0;
  double totalUppiProfit = 0.0;
  double totalDriverEarnings = 0.0;
  double totalAdminAdjustments = 0.0;
  bool isLoading = true;
  RealtimeChannel? _statsChannel;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _fetchSurgicalData();
    _startRealtimeChannels();
  }

  void _startRealtimeChannels() {
    _statsChannel = Supabase.instance.client.channel('financials_analytics')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'rides',
        callback: (payload) => _onDataChanged(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'wallet_transactions',
        callback: (payload) => _onDataChanged(),
      )
      .subscribe();
  }

  void _onDataChanged() {
    if (_debounceTimer?.isActive ?? false) return;
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) _fetchSurgicalData();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _statsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchSurgicalData() async {
    try {
      final client = Supabase.instance.client;

      // 1. Faturamento Total e Lucro da Uppi (das corridas)
      final rides = await client
          .from('rides')
          .select('fare, platform_fee')
          .eq('status', 'completed');
          
      double gross = 0.0;
      double uppiProfit = 0.0;
      for (var r in rides) {
        gross += (r['fare'] as num?)?.toDouble() ?? 0.0;
        uppiProfit += (r['platform_fee'] as num?)?.toDouble() ?? 0.0;
      }

      // 2. Ajustes Administrativos (Sangrias/Bônus Manuais)
      final txs = await client
          .from('wallet_transactions')
          .select('amount')
          .eq('ref_type', 'admin_adjustment');
      double adminAdj = 0.0;
      for (var tx in txs) {
        adminAdj += (tx['amount'] as num?)?.toDouble() ?? 0.0;
      }

      if (mounted) {
        setState(() {
          totalGross = gross;
          totalUppiProfit = uppiProfit;
          totalDriverEarnings = gross - uppiProfit;
          totalAdminAdjustments = adminAdj;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      color: Colors.white.withOpacity(0.02),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Análise Financeira Cirúrgica (Raio-X)',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blueAccent,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SummaryChip(
                  label: 'Faturamento Bruto (Total de Corridas)',
                  value: 'R\$ ${totalGross.toStringAsFixed(2)}',
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _SummaryChip(
                  label: 'Lucro Retido Uppi (Taxas)',
                  value: 'R\$ ${totalUppiProfit.toStringAsFixed(2)}',
                  color: Colors.greenAccent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _SummaryChip(
                  label: 'Ganhos dos Motoristas (Líquido)',
                  value: 'R\$ ${totalDriverEarnings.toStringAsFixed(2)}',
                  color: Colors.blueAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SummaryChip(
                  label: 'Ajustes Administrativos (Custo/Bônus)',
                  value: 'R\$ ${totalAdminAdjustments.toStringAsFixed(2)}',
                  color: totalAdminAdjustments < 0 ? Colors.redAccent : Colors.orangeAccent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _SummaryChip(
                  label: 'Dívida Atual (Saldo a Pagar)',
                  value: 'R\$ ${widget.totalPending.toStringAsFixed(2)}',
                  color: Colors.redAccent,
                ),
              ),
              const Spacer(),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(color: color.withOpacity(0.8), fontSize: 13),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExtractDialog extends StatelessWidget {
  final String driverId;
  final String driverName;
  const _ExtractDialog({required this.driverId, required this.driverName});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 20, 16),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: Colors.blueAccent),
                  const SizedBox(width: 12),
                  Text(
                    'Extrato — $driverName',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: Supabase.instance.client
                    .from('wallet_transactions')
                    .stream(primaryKey: ['id'])
                    .eq('user_id', driverId)
                    .order('created_at', ascending: false),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final txs = snap.data!;
                  if (txs.isEmpty) {
                    return const Center(
                      child: Text(
                        'Nenhuma transação encontrada.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: txs.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white10),
                    itemBuilder: (context, i) {
                      final tx = txs[i];
                      final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
                      final isPos = amount > 0;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isPos
                              ? Colors.green.withOpacity(0.2)
                              : Colors.red.withOpacity(0.2),
                          child: Icon(
                            isPos ? Icons.arrow_downward : Icons.arrow_upward,
                            color: isPos
                                ? Colors.greenAccent
                                : Colors.redAccent,
                            size: 16,
                          ),
                        ),
                        title: Text(tx['description'] ?? 'Transação'),
                        subtitle: Text(
                          (tx['created_at'] as String?)?.split('T').first ?? '',
                        ),
                        trailing: Text(
                          '${isPos ? '+' : ''}R\$ ${amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: isPos
                                ? Colors.greenAccent
                                : Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }
}


