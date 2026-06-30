import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key});

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  // ==========================================
  // COMPLAINT RESOLUTION (EXISTING LOGIC)
  // ==========================================
  Future<void> _resolveComplaint(BuildContext context, Map<String, dynamic> complaint) async {
    final responseCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Responder e Resolver Reclamação'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Assunto: ${complaint['subject']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Descrição: ${complaint['content']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                dropdownColor: Theme.of(context).colorScheme.surface,
                decoration: const InputDecoration(
                  labelText: 'Respostas Rápidas (Templates)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Selecione um template rápido...'),
                  ),
                  ...[
                    'Agradecemos o feedback, o problema foi resolvido.',
                    'Identificamos uma instabilidade no sistema e já aplicamos a correção.',
                    'O valor em questão foi estornado para a sua carteira.',
                    'O motorista parceiro foi alertado sobre a conduta.',
                    'Reclamação improcedente após análise de logs.',
                  ].map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))),
                ],
                onChanged: (val) {
                  if (val != null && val.isNotEmpty) {
                    responseCtrl.text = val;
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: responseCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Resposta ao Usuário',
                  hintText: 'Escreva a resolução que será enviada para o chat da corrida...',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'A resposta é obrigatória para resolução.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Enviar e Resolver', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final responseText = responseCtrl.text.trim();

    try {
      // 1. Atualizar o status da reclamação
      await Supabase.instance.client
          .from('complaints')
          .update({'status': 'resolved'})
          .eq('id', complaint['id']);

      // 2. Enviar a mensagem para o chat da corrida (se houver ride_id)
      final rideId = complaint['ride_id'];
      final currentAdminId = Supabase.instance.client.auth.currentUser?.id ?? 'SYSTEM';
      
      if (rideId != null) {
        await Supabase.instance.client.from('ride_messages').insert({
          'ride_id': rideId,
          'sender_id': currentAdminId,
          'content': '[Suporte Uppi] Olá! Em resposta à sua reclamação: $responseText',
          'sent_by_driver': complaint['role'] == 'driver',
        });
      }

      // 3. Registrar no log de auditoria do admin
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': currentAdminId,
        'action_type': 'complaint_resolved',
        'target_resource_id': complaint['id'].toString(),
        'details': {
          'status': 'resolved',
          'response': responseText,
          'ride_id': rideId,
        },
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reclamação resolvida e resposta enviada ao chat!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao resolver: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ==========================================
  // SUPPORT TICKETS RESOLUTION (NEW FEATURE)
  // ==========================================
  Future<void> _resolveTicket(BuildContext context, Map<String, dynamic> ticket) async {
    final responseCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Responder e Resolver Ticket'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Assunto: ${ticket['subject']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Mensagem: ${ticket['message']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                dropdownColor: Theme.of(context).colorScheme.surface,
                decoration: const InputDecoration(
                  labelText: 'Respostas Rápidas (Templates)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Selecione um template rápido...'),
                  ),
                  ...[
                    'Seu chamado foi analisado e resolvido com sucesso.',
                    'Aplicamos o ajuste financeiro correspondente na sua carteira.',
                    'Agradecemos o relato, sua conta foi reestabelecida.',
                    'Revisamos a sua contestação e a taxa foi isentada.',
                  ].map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))),
                ],
                onChanged: (val) {
                  if (val != null && val.isNotEmpty) {
                    responseCtrl.text = val;
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: responseCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Resposta de Resolução',
                  hintText: 'Escreva a resposta que o usuário receberá via notificação...',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'A resposta é obrigatória para resolução.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Enviar e Resolver', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final responseText = responseCtrl.text.trim();
    final currentAdminId = Supabase.instance.client.auth.currentUser?.id ?? 'SYSTEM';

    try {
      // 1. Atualizar o status do ticket
      await Supabase.instance.client
          .from('support_tickets')
          .update({'status': 'resolved'})
          .eq('id', ticket['id']);

      // 2. Registrar no log de auditoria
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': currentAdminId,
        'action_type': 'support_ticket_resolved',
        'target_resource_id': ticket['id'].toString(),
        'details': {
          'status': 'resolved',
          'response': responseText,
          'category': ticket['category'],
        },
      });

      // 3. Enviar notificação Push para o usuário
      if (ticket['user_id'] != null) {
        await Supabase.instance.client.functions.invoke(
          'send-notification',
          body: {
            'userId': ticket['user_id'],
            'title': 'Chamado Resolvido ✅',
            'message': 'Seu chamado "${ticket['subject']}" foi resolvido: $responseText',
            'channelId': 'tripEvents',
          },
        );
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ticket resolvido e notificação enviada com sucesso!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao resolver chamado: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ==========================================
  // CLOSED WITH DISCLAIMER (PILAR 22 REQUIREMENT)
  // ==========================================
  Future<void> _closeTicketWithDisclaimer(BuildContext context, Map<String, dynamic> ticket) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Row(
          children: [
            Icon(Icons.gavel_rounded, color: Colors.orangeAccent),
            SizedBox(width: 12),
            Text('Encerrar com Isenção'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Atenção!',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orangeAccent),
            ),
            const SizedBox(height: 8),
            Text(
              'Esta ação encerrará administrativamente o ticket #${ticket['id'].toString().substring(0, 8)} sem investigação ou assunção de responsabilidade.\n\nSerá enviada uma notificação push formal contendo o disclaimer jurídico ao usuário.',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Encerrar com Isenção'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final currentAdminId = Supabase.instance.client.auth.currentUser?.id ?? 'SYSTEM';
    final ticketShortId = ticket['id'].toString().substring(0, 8);
    final disclaimerText = 
        'A Uppi concluiu o atendimento do ticket #$ticketShortId sem atribuição de culpa ou responsabilidade direta pelo ocorrido, conforme nossos Termos de Uso. Este canal foi encerrado para fins administrativos. Obrigado por usar o Uppi!';

    try {
      // 1. Atualizar status no banco
      await Supabase.instance.client
          .from('support_tickets')
          .update({'status': 'closed_disclaimer'})
          .eq('id', ticket['id']);

      // 2. Registrar no log de auditoria
      await Supabase.instance.client.from('admin_audit_log').insert({
        'admin_id': currentAdminId,
        'action_type': 'ticket_closed_disclaimer',
        'target_resource_id': ticket['id'].toString(),
        'details': {
          'status': 'closed_disclaimer',
          'disclaimer': disclaimerText,
          'category': ticket['category'],
        },
      });

      // 3. Enviar notificação push ao usuário
      if (ticket['user_id'] != null) {
        await Supabase.instance.client.functions.invoke(
          'send-notification',
          body: {
            'userId': ticket['user_id'],
            'title': 'Atendimento Concluído 🛡️',
            'message': disclaimerText,
            'channelId': 'tripEvents',
          },
        );
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ticket encerrado com isenção jurídica e usuário notificado! 🎉'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao encerrar chamado com isenção: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ==========================================
  // TAB BUILDERS
  // ==========================================
  Widget _buildComplaintsTab(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('complaints')
          .stream(primaryKey: ['id']).order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Erro ao carregar reclamações.', style: TextStyle(color: Colors.red)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final complaints = snapshot.data!;
        if (complaints.isEmpty) {
          return const Center(
            child: Text('Nenhuma reclamação registrada.', style: TextStyle(color: Colors.white54)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: complaints.length,
          itemBuilder: (context, index) {
            final complaint = complaints[index];
            final isResolved = complaint['status'] == 'resolved';

            return Card(
              color: Theme.of(context).colorScheme.surface.withAlpha(200),
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: isResolved ? Colors.green.withAlpha(50) : Colors.orange.withAlpha(50)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isResolved ? Icons.check_circle : Icons.warning_rounded,
                              color: isResolved ? Colors.green : Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${complaint['subject']} (${complaint['role'].toString().toUpperCase()})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        Chip(
                          label: Text(isResolved ? 'Resolvido' : 'Pendente'),
                          backgroundColor: isResolved ? Colors.green.withAlpha(50) : Colors.orange.withAlpha(50),
                          side: BorderSide.none,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      complaint['content'] ?? 'Sem descrição',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Corrida ID: ${complaint['ride_id']} | Usuário: ${complaint['user_id']}',
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                        if (!isResolved)
                          ElevatedButton.icon(
                            onPressed: () => _resolveComplaint(context, complaint),
                            icon: const Icon(Icons.check),
                            label: const Text('Marcar Resolvido'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
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
  }

  Widget _buildTicketsTab(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('support_tickets')
          .stream(primaryKey: ['id']).order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Erro ao carregar tickets de suporte.', style: TextStyle(color: Colors.red)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final tickets = snapshot.data!;
        if (tickets.isEmpty) {
          return const Center(
            child: Text('Nenhum ticket de suporte enviado.', style: TextStyle(color: Colors.white54)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: tickets.length,
          itemBuilder: (context, index) {
            final ticket = tickets[index];
            final status = ticket['status'] ?? 'open';
            
            Color cardBorderColor = Colors.orange.withAlpha(50);
            Color badgeColor = Colors.orange.withAlpha(50);
            String statusText = 'Aberto';
            Color statusTextColor = Colors.orange;

            if (status == 'resolved') {
              cardBorderColor = Colors.green.withAlpha(50);
              badgeColor = Colors.green.withAlpha(50);
              statusText = 'Resolvido';
              statusTextColor = Colors.green;
            } else if (status == 'closed_disclaimer') {
              cardBorderColor = Colors.purple.withAlpha(50);
              badgeColor = Colors.purple.withAlpha(50);
              statusText = 'Isenção Jurídica';
              statusTextColor = Colors.purpleAccent;
            }

            return Card(
              color: Theme.of(context).colorScheme.surface.withAlpha(200),
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: cardBorderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                status == 'resolved' 
                                  ? Icons.check_circle_rounded 
                                  : (status == 'closed_disclaimer' ? Icons.gavel_rounded : Icons.info_outline),
                                color: statusTextColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  ticket['subject'] ?? 'Sem Assunto',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(color: statusTextColor, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Categoria: ${(ticket['category'] ?? 'Geral').toUpperCase()}',
                        style: const TextStyle(fontSize: 10, color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      ticket['message'] ?? 'Sem descrição',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ID: ${ticket['id'].toString().substring(0, 8)}... | Usuário: ${ticket['user_id']}',
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                        if (status == 'open')
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _closeTicketWithDisclaimer(context, ticket),
                                icon: const Icon(Icons.gavel_rounded, size: 16),
                                label: const Text('Encerrar com Isenção', style: TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.orangeAccent,
                                  side: const BorderSide(color: Colors.orangeAccent),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: () => _resolveTicket(context, ticket),
                                icon: const Icon(Icons.check, size: 16),
                                label: const Text('Resolver Chamado', style: TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
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
  }

  // ==========================================
  // MAIN WIDGET BUILDER
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Central de Suporte & Chamados',
                      style: GoogleFonts.outfit(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TabBar(
                  isScrollable: true,
                  indicatorColor: Theme.of(context).colorScheme.primary,
                  labelColor: Theme.of(context).colorScheme.primary,
                  unselectedLabelColor: Colors.white54,
                  tabs: const [
                    Tab(text: 'Reclamações de Corrida'),
                    Tab(text: 'Tickets de Suporte (Direct)'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildComplaintsTab(context),
                _buildTicketsTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
