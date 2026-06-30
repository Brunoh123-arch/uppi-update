import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tela God Mode: Monitora a tabela `driver_earnings` que contém o breakdown
/// financeiro por corrida — bruto, comissão %, comissão R$, líquido e método.
class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Text('Earnings por Corrida (driver_earnings)',
                  style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w600)),
              const Spacer(),
              SizedBox(
                width: 300,
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'Buscar por motorista ou corrida...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.black12,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ],
          ),
        ),

        // StreamBuilder for real-time earnings
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('driver_earnings')
                .stream(primaryKey: ['id'])
                .order('created_at', ascending: false)
                .limit(300),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Erro: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final earnings = snapshot.data!;
              final filteredEarnings = _searchQuery.isEmpty
                  ? earnings
                  : earnings.where((e) {
                      final dId = e['driver_id']?.toString().toLowerCase() ?? '';
                      final rId = e['ride_id']?.toString().toLowerCase() ?? '';
                      final q = _searchQuery.toLowerCase();
                      return dId.contains(q) || rId.contains(q);
                    }).toList();

              // Totals
              double totalGross = 0, totalCommission = 0, totalNet = 0;
              for (final e in filteredEarnings) {
                totalGross += (e['gross_amount'] as num?)?.toDouble() ?? 0;
                totalCommission += (e['commission_amt'] as num?)?.toDouble() ?? 0;
                totalNet += (e['net_amount'] as num?)?.toDouble() ?? 0;
              }

              return Column(
                children: [
                  // Summary Cards
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    color: const Color(0xFF1E293B),
                    child: Row(
                      children: [
                        _SummaryChip(label: 'Registros', value: '${filteredEarnings.length}', icon: Icons.receipt, color: Colors.blueAccent),
                        const SizedBox(width: 16),
                        _SummaryChip(label: 'Bruto Total', value: 'R\$ ${totalGross.toStringAsFixed(2)}', icon: Icons.monetization_on, color: Colors.greenAccent),
                        const SizedBox(width: 16),
                        _SummaryChip(label: 'Comissão Total', value: 'R\$ ${totalCommission.toStringAsFixed(2)}', icon: Icons.percent, color: Colors.orangeAccent),
                        const SizedBox(width: 16),
                        _SummaryChip(label: 'Líquido Total', value: 'R\$ ${totalNet.toStringAsFixed(2)}', icon: Icons.account_balance_wallet, color: const Color(0xFF6C9F12)),
                      ],
                    ),
                  ),

                  // Table
                  Expanded(
                    child: filteredEarnings.isEmpty
                        ? const Center(child: Text('Nenhum earning encontrado.', style: TextStyle(color: Colors.white54)))
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
                                columns: const [
                                  DataColumn(label: Text('Motorista', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Corrida', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Bruto (R\$)', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                  DataColumn(label: Text('Comissão %', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                  DataColumn(label: Text('Comissão R\$', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                  DataColumn(label: Text('Líquido (R\$)', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                  DataColumn(label: Text('Método', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Data', style: TextStyle(fontWeight: FontWeight.bold))),
                                ],
                                rows: filteredEarnings.map((e) {
                                  final driverId = e['driver_id']?.toString() ?? '';
                                  final rideId = e['ride_id']?.toString() ?? '';
                                  final gross = (e['gross_amount'] as num?)?.toDouble() ?? 0;
                                  final commPct = (e['commission_pct'] as num?)?.toDouble() ?? 0;
                                  final commAmt = (e['commission_amt'] as num?)?.toDouble() ?? 0;
                                  final net = (e['net_amount'] as num?)?.toDouble() ?? 0;
                                  final method = e['payment_method']?.toString() ?? '-';
                                  final date = e['created_at'] != null ? DateTime.parse(e['created_at'].toString()).toLocal().toString().substring(0, 16) : '-';

                                  return DataRow(cells: [
                                    DataCell(_DriverNameWidget(driverId: driverId)),
                                    DataCell(
                                      Text(
                                        rideId.length > 8 ? '${rideId.substring(0, 8)}...' : rideId,
                                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                                      ),
                                    ),
                                    DataCell(Text('R\$ ${gross.toStringAsFixed(2)}', style: const TextStyle(color: Colors.greenAccent))),
                                    DataCell(Text('${commPct.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.orangeAccent))),
                                    DataCell(Text('R\$ ${commAmt.toStringAsFixed(2)}', style: const TextStyle(color: Colors.orangeAccent))),
                                    DataCell(Text('R\$ ${net.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF6C9F12), fontWeight: FontWeight.bold))),
                                    DataCell(Text(method)),
                                    DataCell(Text(date, style: const TextStyle(color: Colors.white38, fontSize: 12))),
                                  ]);
                                }).toList(),
                              ),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DriverNameWidget extends StatefulWidget {
  final String driverId;
  const _DriverNameWidget({required this.driverId});

  @override
  State<_DriverNameWidget> createState() => _DriverNameWidgetState();
}

class _DriverNameWidgetState extends State<_DriverNameWidget> {
  static final Map<String, String> _staticNameCache = {};
  String? _resolvedName;

  @override
  void initState() {
    super.initState();
    _resolveName();
  }

  @override
  void didUpdateWidget(covariant _DriverNameWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.driverId != widget.driverId) {
      _resolveName();
    }
  }

  Future<void> _resolveName() async {
    if (widget.driverId.isEmpty) return;
    if (_staticNameCache.containsKey(widget.driverId)) {
      if (mounted) {
        setState(() {
          _resolvedName = _staticNameCache[widget.driverId];
        });
      }
      return;
    }

    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', widget.driverId)
          .maybeSingle();
      final name = res?['full_name'] ?? 'Sem Nome';
      _staticNameCache[widget.driverId] = name;
      if (mounted) {
        setState(() {
          _resolvedName = name;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _resolvedName = 'Motorista (${widget.driverId.substring(0, 8)})';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _resolvedName ?? 'Carregando...',
      style: const TextStyle(color: Colors.white),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryChip({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold)),
              Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ],
      ),
    );
  }
}
