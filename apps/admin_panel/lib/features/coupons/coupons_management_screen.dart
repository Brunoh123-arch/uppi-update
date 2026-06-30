import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class CouponsManagementScreen extends StatelessWidget {
  const CouponsManagementScreen({super.key});

  Future<void> _openCouponDialog(
    BuildContext context, {
    Map<String, dynamic>? coupon,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CouponDialog(coupon: coupon),
    );
  }

  Future<void> _openCouponUsagesDialog(BuildContext context, Map<String, dynamic> coupon) async {
    await showDialog(
      context: context,
      builder: (ctx) => _CouponUsagesDialog(coupon: coupon),
    );
  }

  Future<void> _deleteCoupon(BuildContext context, String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Cupom'),
        content: const Text('Tem certeza que deseja excluir este cupom?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await Supabase.instance.client.from('coupons').delete().eq('id', id);
      // Audit trail
      final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'coupon_deleted',
        'target_resource_id': id,
        'details': {'coupon_id': id},
      });
    }
  }

  Future<void> _toggleCoupon(String id, bool current) async {
    await Supabase.instance.client
        .from('coupons')
        .update({'is_active': !current})
        .eq('id', id);
    // Audit trail
    final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
    await Supabase.instance.client.from('admin_audit_log').insert({
      'admin_id': adminId,
      'action_type': !current ? 'coupon_activated' : 'coupon_deactivated',
      'target_resource_id': id,
      'details': {'coupon_id': id, 'new_state': !current},
    });
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cupons e Promoções',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _openCouponDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Novo Cupom'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purpleAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('coupons')
                .stream(primaryKey: ['id'])
                .order('created_at', ascending: false),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
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

              final coupons = snapshot.data ?? [];
              if (coupons.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.local_activity_outlined,
                        size: 64,
                        color: Colors.white24,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Nenhum cupom ativo.',
                        style: TextStyle(color: Colors.white54, fontSize: 18),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _openCouponDialog(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Criar Primeiro Cupom'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purpleAccent,
                          foregroundColor: Colors.white,
                        ),
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
                  childAspectRatio: 1.9,
                ),
                itemCount: coupons.length,
                itemBuilder: (context, index) {
                  final c = coupons[index];
                  final isFlat = c['discount_type'] == 'flat';
                  final isActive = c['is_active'] as bool? ?? true;
                  final expiry = c['expire_at'] as String?;

                  return Card(
                    color: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isActive
                            ? Colors.purpleAccent.withOpacity(0.3)
                            : Colors.white10,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c['code'] ?? 'CUPOM',
                                  style: GoogleFonts.outfit(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: isActive
                                        ? Colors.purpleAccent
                                        : Colors.white38,
                                  ),
                                ),
                              ),
                              Switch(
                                value: isActive,
                                onChanged: (_) =>
                                    _toggleCoupon(c['id'].toString(), isActive),
                                activeThumbColor: Colors.purpleAccent,
                              ),
                            ],
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.purpleAccent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isFlat
                                  ? 'R\$ ${c['discount']} de desconto'
                                  : '${c['discount']}% de desconto',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.purpleAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            expiry != null
                                ? 'Validade: ${expiry.split('T').first}'
                                : 'Sem data de expiração',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(
                                    Icons.history,
                                    size: 14,
                                  ),
                                  label: const Text('Usos'),
                                  onPressed: () =>
                                      _openCouponUsagesDialog(context, c),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white70,
                                    side: const BorderSide(
                                      color: Colors.white24,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 14,
                                  ),
                                  label: const Text('Editar'),
                                  onPressed: () =>
                                      _openCouponDialog(context, coupon: c),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.purpleAccent,
                                    side: const BorderSide(
                                      color: Colors.purpleAccent,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    _deleteCoupon(context, c['id'].toString()),
                                tooltip: 'Excluir',
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
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Dialog de Criação / Edição de Cupom
// ─────────────────────────────────────────────
class _CouponDialog extends StatefulWidget {
  final Map<String, dynamic>? coupon;
  const _CouponDialog({this.coupon});

  @override
  State<_CouponDialog> createState() => _CouponDialogState();
}

class _CouponDialogState extends State<_CouponDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeCtrl;
  late final TextEditingController _discountCtrl;
  late final TextEditingController _minOrderCtrl;
  late final TextEditingController _maxUsesCtrl;

  String _discountType = 'flat'; // 'flat' | 'percent'
  bool _isActive = true;
  bool _isSaving = false;
  DateTime? _expiry;

  bool get _isEditing => widget.coupon != null;

  @override
  void initState() {
    super.initState();
    final c = widget.coupon;
    _codeCtrl = TextEditingController(text: c?['code'] ?? '');
    _discountCtrl = TextEditingController(
      text: c?['discount']?.toString() ?? '',
    );
    _minOrderCtrl = TextEditingController(
      text: c?['minimum_order']?.toString() ?? '0',
    );
    _maxUsesCtrl = TextEditingController(
      text: c?['max_uses']?.toString() ?? '',
    );
    _discountType = c?['discount_type'] ?? 'flat';
    _isActive = c?['is_active'] as bool? ?? true;
    final expStr = c?['expire_at'] as String?;
    if (expStr != null) _expiry = DateTime.tryParse(expStr);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _discountCtrl.dispose();
    _minOrderCtrl.dispose();
    _maxUsesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _expiry = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final data = {
        'code': _codeCtrl.text.trim().toUpperCase(),
        'discount': double.tryParse(_discountCtrl.text) ?? 0.0,
        'discount_type': _discountType,
        'minimum_order': double.tryParse(_minOrderCtrl.text) ?? 0.0,
        'max_uses': int.tryParse(_maxUsesCtrl.text),
        'is_active': _isActive,
        'expire_at': _expiry?.toIso8601String(),
      };
      if (_isEditing) {
        await Supabase.instance.client
            .from('coupons')
            .update(data)
            .eq('id', widget.coupon!['id']);
        
        final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
        await Supabase.instance.client.from('admin_audit_log').insert({
          'admin_id': adminId,
          'action_type': 'coupon_updated',
          'target_resource_id': widget.coupon!['id'].toString(),
          'details': data,
        });
      } else {
        final res = await Supabase.instance.client.from('coupons').insert(data).select().single();
        final adminId = Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
        await Supabase.instance.client.from('admin_audit_log').insert({
          'admin_id': adminId,
          'action_type': 'coupon_created',
          'target_resource_id': res['id'].toString(),
          'details': data,
        });
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'Cupom atualizado!' : 'Cupom criado com sucesso!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(40),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.local_activity,
                      color: Colors.purpleAccent,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isEditing ? 'Editar Cupom' : 'Novo Cupom',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
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
                const SizedBox(height: 32),

                // Code field
                TextFormField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: _decor(
                    'Código do Cupom (ex: UPPI20)',
                    Icons.code,
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 20),

                // Discount type
                const Text(
                  'Tipo de Desconto',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _TypeButton(
                        label: 'Valor Fixo (R\$)',
                        icon: Icons.attach_money,
                        selected: _discountType == 'flat',
                        onTap: () => setState(() => _discountType = 'flat'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TypeButton(
                        label: 'Percentual (%)',
                        icon: Icons.percent,
                        selected: _discountType == 'percent',
                        onTap: () => setState(() => _discountType = 'percent'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Discount value + min order
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _discountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _decor(
                          _discountType == 'flat'
                              ? 'Desconto (R\$)'
                              : 'Desconto (%)',
                          Icons.discount_outlined,
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Obrigatório';
                          if (double.tryParse(v) == null) {
                            return 'Número inválido';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _minOrderCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _decor(
                          'Pedido Mínimo (R\$)',
                          Icons.shopping_cart_outlined,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Max uses + expiry
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _maxUsesCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _decor(
                          'Usos Máximos',
                          Icons.people_outline,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: _decor(
                            'Data de Expiração',
                            Icons.calendar_today,
                          ),
                          child: Text(
                            _expiry != null
                                ? '${_expiry!.day.toString().padLeft(2, '0')}/${_expiry!.month.toString().padLeft(2, '0')}/${_expiry!.year}'
                                : 'Sem Limite',
                            style: TextStyle(
                              color: _expiry != null
                                  ? Colors.white
                                  : Colors.white38,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Active switch
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.toggle_on_outlined,
                        color: Colors.white54,
                      ),
                      const SizedBox(width: 12),
                      const Text('Cupom ativo'),
                      const Spacer(),
                      Switch(
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        activeThumbColor: Colors.purpleAccent,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      _isEditing ? 'Salvar Alterações' : 'Criar Cupom',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purpleAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decor(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 18),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    filled: true,
    fillColor: Colors.white.withOpacity(0.05),
  );
}

class _TypeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TypeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? Colors.purpleAccent.withOpacity(0.2)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.purpleAccent : Colors.white10,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? Colors.purpleAccent : Colors.white38,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.purpleAccent : Colors.white54,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CouponUsagesDialog extends StatelessWidget {
  final Map<String, dynamic> coupon;
  const _CouponUsagesDialog({required this.coupon});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 600,
        height: 600,
        padding: const EdgeInsets.all(40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, color: Colors.purpleAccent, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Usos do Cupom: ${coupon['code']}',
                  style: GoogleFonts.outfit(
                    fontSize: 22,
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
            const SizedBox(height: 32),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _fetchUsages(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Erro: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));
                  }
                  final usages = snapshot.data ?? [];
                  if (usages.isEmpty) {
                    return const Center(
                      child: Text('Nenhum uso registrado para este cupom.', style: TextStyle(color: Colors.white54)),
                    );
                  }
                  return ListView.builder(
                    itemCount: usages.length,
                    itemBuilder: (context, index) {
                      final u = usages[index];
                      final date = DateTime.parse(u['created_at'].toString()).toLocal();
                      final discount = (u['discount_amount'] as num?)?.toDouble() ?? 0.0;
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.purpleAccent,
                          child: Icon(Icons.person, color: Colors.white, size: 20),
                        ),
                        title: Text('Passageiro ID: ${u['rider_id'].toString().substring(0,8)}...'),
                        subtitle: Text('Corrida ID: ${u['ride_id'].toString().substring(0,8)}... • ${date.day}/${date.month}/${date.year}'),
                        trailing: Text(
                          '- R\$ ${discount.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16),
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

  Future<List<Map<String, dynamic>>> _fetchUsages() async {
    try {
      final res = await Supabase.instance.client
          .from('coupon_usages')
          .select()
          .eq('coupon_id', coupon['id'])
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Erro ao carregar usos: $e');
      return [];
    }
  }
}
