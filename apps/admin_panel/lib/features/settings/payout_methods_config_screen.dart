import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tela God Mode: CRUD completo dos métodos de saque disponíveis para
/// motoristas (tabela `payout_methods`). Diferente de `payout_accounts`
/// (contas bancárias dos motoristas), esta tabela define QUAIS gateways
/// estão disponíveis — ex: PIX Mercado Pago, Transferência Bradesco, etc.
/// O admin controla nome, URL de onboarding e ativação de cada gateway.
class PayoutMethodsConfigScreen extends StatelessWidget {
  const PayoutMethodsConfigScreen({super.key});

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Métodos de Saque (Motoristas)',
                    style: GoogleFonts.outfit(
                        fontSize: 28, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Configure quais gateways os motoristas podem usar para receber pagamentos',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showEditDialog(context, null),
                icon: const Icon(Icons.add),
                label: const Text('Novo Método de Saque'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ],
          ),
        ),

        // Diferença informacional
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          color: Colors.deepPurple.withOpacity(0.1),
          child: Row(
            children: [
              const Icon(Icons.info_outline,
                  color: Colors.deepPurpleAccent, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: RichText(
                  text: const TextSpan(
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                    children: [
                      TextSpan(
                          text: 'payout_methods',
                          style: TextStyle(
                              fontFamily: 'monospace',
                              color: Colors.deepPurpleAccent)),
                      TextSpan(
                          text:
                              ' = Gateways disponíveis (configuração admin)  |  '),
                      TextSpan(
                          text: 'payout_accounts',
                          style: TextStyle(
                              fontFamily: 'monospace',
                              color: Colors.orangeAccent)),
                      TextSpan(
                          text:
                              ' = Contas bancárias/PIX dos motoristas (dados pessoais)'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('payout_methods')
                .stream(primaryKey: ['id']),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.redAccent, size: 48),
                      const SizedBox(height: 16),
                      Text('Erro: ${snapshot.error}',
                          style: const TextStyle(color: Colors.redAccent)),
                      const SizedBox(height: 8),
                      const Text(
                        'Verifique se a tabela payout_methods existe no banco de dados.',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final methods = snapshot.data!;

              if (methods.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined,
                          color: Colors.white24, size: 80),
                      const SizedBox(height: 20),
                      const Text(
                        'Nenhum método de saque configurado.',
                        style: TextStyle(color: Colors.white54, fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Os motoristas não conseguem cadastrar contas de saque sem métodos disponíveis.',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _showEditDialog(context, null),
                        icon: const Icon(Icons.add),
                        label: const Text('Criar Primeiro Método'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: methods.length,
                itemBuilder: (context, index) {
                  final m = methods[index];
                  final isActive = m['is_active'] == true;
                  final name = m['name']?.toString() ?? 'Sem nome';
                  final externalUrl =
                      m['external_url']?.toString() ?? '';
                  final type = m['type']?.toString() ?? '';

                  return Card(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withAlpha(220),
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isActive
                            ? Colors.deepPurpleAccent.withOpacity(0.4)
                            : Colors.white10,
                        width: 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          // Icon
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? Colors.deepPurple.withOpacity(0.2)
                                  : Colors.white10,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _iconForType(type),
                              color: isActive
                                  ? Colors.deepPurpleAccent
                                  : Colors.white38,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 20),

                          // Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      name,
                                      style: GoogleFonts.outfit(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? Colors.green.withOpacity(0.15)
                                            : Colors.red.withOpacity(0.15),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: Border.all(
                                          color: isActive
                                              ? Colors.green.withOpacity(0.4)
                                              : Colors.red.withOpacity(0.4),
                                        ),
                                      ),
                                      child: Text(
                                        isActive ? 'Ativo' : 'Inativo',
                                        style: TextStyle(
                                          color: isActive
                                              ? Colors.greenAccent
                                              : Colors.redAccent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (type.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blueAccent
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          type.toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.blueAccent,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 6),
                                if (externalUrl.isNotEmpty)
                                  GestureDetector(
                                    onTap: () {
                                      Clipboard.setData(
                                          ClipboardData(text: externalUrl));
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                        content:
                                            Text('URL copiada para clipboard'),
                                        duration: Duration(seconds: 2),
                                      ));
                                    },
                                    child: Row(
                                      children: [
                                        const Icon(Icons.link,
                                            color: Colors.white38, size: 14),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            externalUrl,
                                            style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 12),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const Icon(Icons.copy,
                                            color: Colors.white24, size: 12),
                                      ],
                                    ),
                                  )
                                else
                                  const Text(
                                    'Sem URL de onboarding configurada',
                                    style: TextStyle(
                                        color: Colors.orange, fontSize: 12),
                                  ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 16),

                          // Actions
                          Column(
                            children: [
                              // Toggle active
                              Switch(
                                value: isActive,
                                activeThumbColor: Colors.deepPurpleAccent,
                                onChanged: (val) =>
                                    _toggleActive(context, m['id'].toString(), val),
                              ),
                              const Text('Ativo',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 10)),
                            ],
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.edit,
                                color: Colors.blueAccent),
                            tooltip: 'Editar método',
                            onPressed: () => _showEditDialog(context, m),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.redAccent),
                            tooltip: 'Excluir método',
                            onPressed: () => _deleteMethod(context, m),
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

  IconData _iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'pix':
        return Icons.qr_code;
      case 'bank_transfer':
      case 'transfer':
        return Icons.account_balance;
      case 'stripe':
        return Icons.credit_card;
      case 'paypal':
        return Icons.paypal;
      default:
        return Icons.account_balance_wallet;
    }
  }

  void _showEditDialog(BuildContext context, Map<String, dynamic>? method) {
    final nameCtrl =
        TextEditingController(text: method?['name']?.toString() ?? '');
    final typeCtrl =
        TextEditingController(text: method?['type']?.toString() ?? '');
    final urlCtrl =
        TextEditingController(text: method?['external_url']?.toString() ?? '');
    bool isActive = method?['is_active'] == true || method == null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            method == null
                ? 'Novo Método de Saque'
                : 'Editar: ${method['name']}',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome do Método',
                    hintText: 'ex: PIX Mercado Pago, Transferência Bancária',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: typeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    hintText: 'pix | bank_transfer | stripe | paypal',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'URL de Onboarding (opcional)',
                    hintText: 'https://...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Ativo (visível para motoristas)'),
                  value: isActive,
                  activeThumbColor: Colors.deepPurpleAccent,
                  onChanged: (v) => setDialogState(() => isActive = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple),
              onPressed: () async {
                final payload = {
                  'name': nameCtrl.text.trim(),
                  'type': typeCtrl.text.trim(),
                  'external_url': urlCtrl.text.trim(),
                  'is_active': isActive,
                };

                try {
                  if (method == null) {
                    await Supabase.instance.client
                        .from('payout_methods')
                        .insert(payload);
                  } else {
                    await Supabase.instance.client
                        .from('payout_methods')
                        .update(payload)
                        .eq('id', method['id']);
                  }

                  final adminId = Supabase.instance.client.auth.currentUser
                          ?.id ??
                      'UNKNOWN';
                  await Supabase.instance.client.from('admin_audit_log').insert({
                    'admin_id': adminId,
                    'action_type': method == null
                        ? 'payout_method_created'
                        : 'payout_method_updated',
                    'target_resource_id':
                        method?['id']?.toString() ?? 'new',
                    'details': payload,
                  });

                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                          content: Text('Erro: $e'),
                          backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleActive(
      BuildContext context, String id, bool isActive) async {
    try {
      await Supabase.instance.client
          .from('payout_methods')
          .update({'is_active': isActive}).eq('id', id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteMethod(
      BuildContext context, Map<String, dynamic> method) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Excluir Método de Saque?'),
        content: Text(
          'Isso removerá "${method['name']}" da lista de opções dos motoristas. '
          'Contas bancárias já cadastradas com este método não serão afetadas.',
        ),
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

    if (confirm != true || !context.mounted) return;

    try {
      await Supabase.instance.client
          .from('payout_methods')
          .delete()
          .eq('id', method['id']);

      final adminId =
          Supabase.instance.client.auth.currentUser?.id ?? 'UNKNOWN';
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': adminId,
        'action_type': 'payout_method_deleted',
        'target_resource_id': method['id'].toString(),
        'details': {'name': method['name']},
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Método excluído.'),
              backgroundColor: Colors.redAccent),
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
