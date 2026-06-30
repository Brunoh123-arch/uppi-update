import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class GiftCardsScreen extends StatefulWidget {
  const GiftCardsScreen({super.key});

  @override
  State<GiftCardsScreen> createState() => _GiftCardsScreenState();
}

class _GiftCardsScreenState extends State<GiftCardsScreen> {
  final _codeCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  Future<void> _openCreateDialog() async {
    _codeCtrl.clear();
    _amountCtrl.clear();
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Novo Vale-Presente (Gift Card)'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Código do Cartão',
                    hintText: 'Ex: PROMO50',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Código obrigatório';
                    if (v.trim().length < 3) return 'Mínimo 3 caracteres';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Valor (R\$)',
                    hintText: 'Ex: 50.00',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Valor obrigatório';
                    final amountStr = v.trim().replaceAll(',', '.');
                    final amount = double.tryParse(amountStr);
                    if (amount == null) return 'Valor inválido';
                    if (amount <= 0) return 'Deve ser maior que zero';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;

                      setDialogState(() => isSaving = true);
                      final code = _codeCtrl.text.trim().toUpperCase();
                      final amountStr = _amountCtrl.text.trim().replaceAll(',', '.');
                      final amount = double.parse(amountStr);

                      try {
                        // Verificação de código duplicado
                        final existing = await Supabase.instance.client
                            .from('gift_cards')
                            .select('id')
                            .eq('code', code)
                            .maybeSingle();

                        if (existing != null) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Erro: Já existe um Vale-Presente com este código!'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                          setDialogState(() => isSaving = false);
                          return;
                        }

                        await Supabase.instance.client.from('gift_cards').insert({
                          'code': code,
                          'amount': amount,
                          'currency': 'BRL',
                          'is_redeemed': false,
                        });

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Vale-presente criado com sucesso!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('Erro: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                        setDialogState(() => isSaving = false);
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Criar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteGiftCard(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Vale-Presente'),
        content: const Text('Tem certeza que deseja apagar este código? (Se já foi resgatado, talvez seja melhor não apagar para manter o histórico).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await Supabase.instance.client.from('gift_cards').delete().eq('id', id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e'), backgroundColor: Colors.red));
    }
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
              Text('Vales-Presente (Gift Cards)', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w600)),
              ElevatedButton.icon(
                onPressed: _openCreateDialog,
                icon: const Icon(Icons.card_giftcard),
                label: const Text('Criar Gift Card'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('gift_cards')
                .stream(primaryKey: ['id'])
                .order('created_at', ascending: false),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));
              
              final cards = snapshot.data!;
              if (cards.isEmpty) return const Center(child: Text('Nenhum Gift Card encontrado.', style: TextStyle(color: Colors.white54)));

              return ListView.builder(
                padding: const EdgeInsets.all(32),
                itemCount: cards.length,
                itemBuilder: (context, index) {
                  final card = cards[index];
                  final isRedeemed = card['is_redeemed'] == true;
                  final amount = (card['amount'] as num?)?.toDouble() ?? 0.0;
                  final date = card['created_at'] != null ? DateTime.parse(card['created_at'].toString()).toLocal() : DateTime.now();

                  return Card(
                    color: Theme.of(context).colorScheme.surface,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                        backgroundColor: isRedeemed ? Colors.grey : Colors.greenAccent,
                        child: Icon(Icons.card_giftcard, color: isRedeemed ? Colors.white38 : Colors.black87),
                      ),
                      title: Text(card['code'] ?? 'S/N', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: isRedeemed ? Colors.white54 : Colors.white)),
                      subtitle: Text('Valor: R\$ ${amount.toStringAsFixed(2)} | Criado: ${date.toString().substring(0,16)}\nStatus: ${isRedeemed ? 'RESGATADO por ${card['redeemed_by']}' : 'DISPONÍVEL'}',
                          style: TextStyle(color: isRedeemed ? Colors.white38 : Colors.white70)),
                      isThreeLine: true,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => _deleteGiftCard(card['id'].toString()),
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
