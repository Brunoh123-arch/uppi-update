import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class PaymentGatewaysScreen extends StatefulWidget {
  const PaymentGatewaysScreen({super.key});

  @override
  State<PaymentGatewaysScreen> createState() => _PaymentGatewaysScreenState();
}

class _PaymentGatewaysScreenState extends State<PaymentGatewaysScreen> {
  void _editGateway(Map<String, dynamic>? gateway) {
    final nameCtrl = TextEditingController(text: gateway?['name'] ?? '');
    final externalUrlCtrl = TextEditingController(text: gateway?['external_url'] ?? '');
    bool isActive = gateway?['is_active'] ?? true;
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(gateway == null ? 'Adicionar Gateway' : 'Editar Gateway'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nome do Gateway (ex: Mercado Pago)'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: externalUrlCtrl,
                decoration: const InputDecoration(labelText: 'URL Externa (Checkout/API)'),
              ),
              const SizedBox(height: 16),
              StatefulBuilder(
                builder: (context, setState) {
                  return SwitchListTile(
                    title: const Text('Gateway Ativo?'),
                    value: isActive,
                    onChanged: (value) {
                      setState(() {
                        isActive = value;
                      });
                    },
                  );
                }
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (gateway == null) {
                  await Supabase.instance.client.functions.invoke(
                    'admin-actions',
                    body: {
                      'action': 'createPaymentGateway',
                      'name': nameCtrl.text,
                      'external_url': externalUrlCtrl.text,
                      'is_active': isActive,
                    },
                  );
                } else {
                  await Supabase.instance.client.functions.invoke(
                    'admin-actions',
                    body: {
                      'action': 'updatePaymentGateway',
                      'gatewayId': gateway['id'],
                      'name': nameCtrl.text,
                      'external_url': externalUrlCtrl.text,
                      'is_active': isActive,
                    },
                  );
                }

                if (mounted) Navigator.pop(context);
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Gateways de Pagamento',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _editGateway(null),
                icon: const Icon(Icons.add),
                label: const Text('Novo Gateway'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('payment_gateways')
                .stream(primaryKey: ['id']),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Erro ao carregar gateways.', style: TextStyle(color: Colors.red)),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final gateways = snapshot.data!;
              if (gateways.isEmpty) {
                return const Center(
                  child: Text('Nenhum gateway configurado.', style: TextStyle(color: Colors.white54)),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: gateways.length,
                itemBuilder: (context, index) {
                  final gateway = gateways[index];
                  
                  return Card(
                    color: Theme.of(context).colorScheme.surface.withAlpha(200),
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: const CircleAvatar(
                        backgroundColor: Colors.white10,
                        child: Icon(Icons.payment, color: Colors.white),
                      ),
                      title: Text(
                        gateway['name'] ?? gateway['title'] ?? 'Gateway',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      subtitle: Text(
                        'URL: ${gateway['external_url'] ?? 'Nenhuma'}',
                        style: const TextStyle(color: Colors.white54),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: gateway['is_active'] ?? false,
                            onChanged: (val) async {
                              await Supabase.instance.client.functions.invoke(
                                'admin-actions',
                                body: {
                                  'action': 'updatePaymentGateway',
                                  'gatewayId': gateway['id'],
                                  'is_active': val,
                                },
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blueAccent),
                            onPressed: () => _editGateway(gateway),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: Theme.of(context).colorScheme.surface,
                                  title: const Text('Excluir Gateway?'),
                                  content: const Text('Isso removerá o método de pagamento dos apps.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Excluir'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                await Supabase.instance.client.functions.invoke(
                                  'admin-actions',
                                  body: {
                                    'action': 'deletePaymentGateway',
                                    'gatewayId': gateway['id'],
                                  },
                                );
                              }
                            },
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
