import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class CashbackManagementScreen extends StatefulWidget {
  const CashbackManagementScreen({super.key});

  @override
  State<CashbackManagementScreen> createState() => _CashbackManagementScreenState();
}

class _CashbackManagementScreenState extends State<CashbackManagementScreen> {
  List<Map<String, dynamic>> _rules = [];
  bool isLoading = true;
  RealtimeChannel? _realtimeChannel;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadRules();
    _startRealtimeListener();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _startRealtimeListener() {
    _realtimeChannel = Supabase.instance.client
        .channel('cashback_rules_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cashback_rules',
          callback: (payload) {
            _onRealtimeChange();
          },
        )
        .subscribe();
  }

  void _onRealtimeChange() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        _loadRules(silent: true);
      }
    });
  }

  Future<void> _loadRules({bool silent = false}) async {
    if (!silent) setState(() => isLoading = true);
    try {
      final res = await Supabase.instance.client
          .from('cashback_rules')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _rules = List<Map<String, dynamic>>.from(res);
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar regras de cashback: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _toggleRule(String id, bool isActive) async {
    try {
      await Supabase.instance.client
          .from('cashback_rules')
          .update({'is_active': !isActive, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', id);
      _loadRules();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteRule(String id) async {
    try {
      await Supabase.instance.client.from('cashback_rules').delete().eq('id', id);
      _loadRules();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final percentCtrl = TextEditingController();
    final minFareCtrl = TextEditingController(text: '0');
    final maxCashbackCtrl = TextEditingController(text: '50');
    int? selectedDay;

    final dayNames = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text('Nova Regra de Cashback', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Nome da Campanha',
                    labelStyle: GoogleFonts.outfit(color: Colors.white70),
                    hintText: 'Ex: Segunda Turbinada',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.campaign, color: Colors.greenAccent),
                  ),
                  style: GoogleFonts.outfit(color: Colors.white),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: percentCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Porcentagem de Cashback (%)',
                    labelStyle: GoogleFonts.outfit(color: Colors.white70),
                    hintText: 'Ex: 5.0',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.percent, color: Colors.greenAccent),
                  ),
                  style: GoogleFonts.outfit(color: Colors.white),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: minFareCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Tarifa Mínima (R\$)',
                    labelStyle: GoogleFonts.outfit(color: Colors.white70),
                    hintText: 'Ex: 10',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.attach_money, color: Colors.orangeAccent),
                  ),
                  style: GoogleFonts.outfit(color: Colors.white),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: maxCashbackCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Cashback Máximo por Corrida (R\$)',
                    labelStyle: GoogleFonts.outfit(color: Colors.white70),
                    hintText: 'Ex: 50',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.savings, color: Colors.orangeAccent),
                  ),
                  style: GoogleFonts.outfit(color: Colors.white),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: selectedDay,
                  decoration: InputDecoration(
                    labelText: 'Dia da Semana',
                    labelStyle: GoogleFonts.outfit(color: Colors.white70),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.calendar_today, color: Colors.blueAccent),
                  ),
                  dropdownColor: Theme.of(context).colorScheme.surface,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos os dias')),
                    ...List.generate(7, (i) => DropdownMenuItem(value: i, child: Text(dayNames[i]))),
                  ],
                  onChanged: (val) => setDialogState(() => selectedDay = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar', style: GoogleFonts.outfit(color: Colors.white54)),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final percent = double.tryParse(percentCtrl.text);
                if (name.isEmpty || percent == null || percent <= 0 || percent > 50) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Preencha todos os campos corretamente (% entre 0.1 e 50)'), backgroundColor: Colors.red),
                  );
                  return;
                }

                try {
                  await Supabase.instance.client.from('cashback_rules').insert({
                    'name': name,
                    'percentage': percent,
                    'day_of_week': selectedDay,
                    'min_fare': double.tryParse(minFareCtrl.text) ?? 0,
                    'max_cashback': double.tryParse(maxCashbackCtrl.text) ?? 50,
                    'is_active': true,
                  });
                  if (mounted) Navigator.pop(ctx);
                  _loadRules();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              icon: const Icon(Icons.check),
              label: Text('Criar', style: GoogleFonts.outfit()),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _dayName(int? day) {
    const days = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];
    if (day == null || day < 0 || day > 6) return 'Todos';
    return days[day];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 80,
          padding: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Motor de Cashback Dinâmico',
                  style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w600),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showCreateDialog,
                icon: const Icon(Icons.add),
                label: Text('Nova Regra', style: GoogleFonts.outfit()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : _rules.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.savings_outlined, size: 64, color: Colors.white24),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhuma regra de cashback configurada',
                            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 18),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Crie uma regra para reter passageiros com dinheiro travado no app!',
                            style: GoogleFonts.outfit(color: Colors.white38, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(32),
                      itemCount: _rules.length,
                      itemBuilder: (context, i) {
                        final rule = _rules[i];
                        final isActive = rule['is_active'] == true;
                        return Card(
                          color: Theme.of(context).colorScheme.surface,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: isActive ? Colors.greenAccent.withOpacity(0.15) : Colors.white12,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${rule['percentage']}%',
                                      style: GoogleFonts.outfit(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: isActive ? Colors.greenAccent : Colors.white38,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        rule['name'] ?? 'Sem nome',
                                        style: GoogleFonts.outfit(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          color: isActive ? Colors.white : Colors.white54,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_dayName(rule['day_of_week'])} • Mín: R\$ ${rule['min_fare']} • Máx: R\$ ${rule['max_cashback']}',
                                        style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: isActive,
                                  activeThumbColor: Colors.greenAccent,
                                  onChanged: (_) => _toggleRule(rule['id'], isActive),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => _deleteRule(rule['id']),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
