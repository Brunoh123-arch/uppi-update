import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:flutter_common/core/presentation/uppi_feedback.dart';
import 'package:ionicons/ionicons.dart';
import 'package:rider_flutter/config/locator/locator.dart';
import 'package:rider_flutter/core/entities/order.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/buttons/app_back_button.dart';
import 'package:flutter_common/core/presentation/buttons/app_icon_button.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../blocs/track_order.dart';
import 'package:flutter_common/features/chat/chat.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatSheet extends StatefulWidget {
  final OrderEntity order;

  const ChatSheet({
    super.key,
    required this.order,
  });

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  String? message;
  TextEditingController textEditingController = TextEditingController();
  ScrollController scrollController = ScrollController();

  // Smart Chat — respostas rápidas dinâmicas do passageiro
  List<_QuickReplyItem> _quickReplies = [];
  bool _loadingReplies = true;
  bool _sendingQuickReply = false;

  @override
  void initState() {
    super.initState();
    _loadQuickReplies();
  }

  Future<void> _loadQuickReplies() async {
    try {
      final idToken = Supabase.instance.client.auth.currentSession?.accessToken;
      if (idToken == null) throw Exception("Could not get auth token");

      final response = await http.post(
        Uri.parse('${dotenv.env['SUPABASE_URL']}/functions/v1/get-quick-replies'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'data': {'role': 'rider', 'locale': 'pt'},
        }),
      );

      if (response.statusCode != 200) {
        throw Exception("Failed to load quick replies: ${response.statusCode}");
      }

      final responseJson = jsonDecode(response.body);
      final raw = responseJson['replies'] as List<dynamic>? ?? [];
      final filtered = raw.where((q) => q['role'] == 'rider').toList();
      setState(() {
        if (filtered.isEmpty) {
          _quickReplies = [
            _QuickReplyItem(
                id: 'rider_coming_down',
                text: '🏃 Já estou descendo!',
                icon: '🏃'),
            _QuickReplyItem(
                id: 'rider_at_gate', text: '🚪 Estou no portão.', icon: '🚪'),
            _QuickReplyItem(
                id: 'rider_wait_2min',
                text: '✌️ Pode esperar 2 min?',
                icon: '✌️'),
            _QuickReplyItem(
                id: 'rider_trunk', text: '🧳 Tenho bagagem.', icon: '🧳'),
          ];
        } else {
          _quickReplies = filtered
              .map((q) => _QuickReplyItem(
                    id: (q['id'] ?? q['text_key'] ?? '') as String,
                    text: (q['text_pt'] ?? q['text_key'] ?? '') as String,
                    icon: q['icon'] as String? ?? '💬',
                  ))
              .toList();
        }
        _loadingReplies = false;
      });
    } catch (_) {
      // Fallback estático
      setState(() {
        _quickReplies = [
          _QuickReplyItem(
              id: 'rider_coming_down',
              text: '🏃 Já estou descendo!',
              icon: '🏃'),
          _QuickReplyItem(
              id: 'rider_at_gate', text: '🚪 Estou no portão.', icon: '🚪'),
          _QuickReplyItem(
              id: 'rider_wait_2min',
              text: '✌️ Pode esperar 2 min?',
              icon: '✌️'),
          _QuickReplyItem(
              id: 'rider_trunk', text: '🧳 Tenho bagagem.', icon: '🧳'),
        ];
        _loadingReplies = false;
      });
    }
  }

  Future<void> _sendQuickReply(_QuickReplyItem reply) async {
    if (_sendingQuickReply) return;
    setState(() => _sendingQuickReply = true);
    try {
      UppiFeedback.triggerLight(); // Acessibilidade: Alerta Háptico no chip de resposta rápida
      if (mounted) {
        context.read<TrackOrderBloc>().sendChatMessage(reply.text);
      }
    } finally {
      if (mounted) setState(() => _sendingQuickReply = false);
    }
  }

  @override
  void dispose() {
    textEditingController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TrackOrderBloc, TrackOrderState>(
      listener: (context, state) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          if (scrollController.hasClients) {
            scrollController.animateTo(
              scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      },
      builder: (context, state) {
        return Container(
          padding: const EdgeInsets.all(16),
          color: context.theme.scaffoldBackgroundColor,
          child: SafeArea(
            child: Column(children: [
              // ── Header ──
              Row(
                children: [
                  AppBackButton(
                    onPressed: () {
                      locator<TrackOrderBloc>().hideChat();
                    },
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      widget.order.driver?.fullName ?? '',
                      style: context.titleMedium,
                    ),
                  ),
                  AppIconButton(
                    icon: Ionicons.call,
                    onPressed: () async {
                      final mobile = widget.order.driver?.mobileNumber;
                      if (mobile != null && mobile.isNotEmpty) {
                        final telUri = Uri.parse('tel:$mobile');
                        try {
                          if (await canLaunchUrl(telUri)) {
                            await launchUrl(telUri);
                          } else {
                            throw Exception('Não pôde iniciar ligação convencional');
                          }
                        } catch (_) {
                          context.showSnackBar(
                            message: 'Não foi possível iniciar a chamada convencional.',
                          );
                        }
                      } else {
                        context.showSnackBar(
                          message: 'Número do motorista não disponível.',
                        );
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Mensagens ──
              Expanded(
                child: Builder(
                  builder: (context) {
                    final bloc = context.read<TrackOrderBloc>();
                    final allMessages = [
                      ...widget.order.chatMessages,
                      ...bloc.pendingMessages,
                    ];
                    // Ordenar mensagens cronologicamente por data de criação
                    allMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

                    return ListView.builder(
                      controller: scrollController,
                      itemCount: allMessages.length,
                      itemBuilder: (context, index) {
                        final item = allMessages[index];
                        final isPending = item.id.startsWith('local_');
                        
                        if (item.isSender) {
                          if (isPending) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                ChatItemMe(
                                  message: item.message,
                                  dateTime: item.createdAt,
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 8, bottom: 8),
                                  child: GestureDetector(
                                    onTap: () {
                                      bloc.retryMessage(item);
                                    },
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Ionicons.alert_circle,
                                          color: Colors.red,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Falhou - Toque para Reenviar',
                                          style: context.labelSmall?.copyWith(
                                            color: Colors.red,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }
                          return ChatItemMe(
                            message: item.message,
                            dateTime: item.createdAt,
                          );
                        } else {
                          return ChatItemOtherPerson(
                            message: item.message,
                            dateTime: item.createdAt,
                          );
                        }
                      },
                    );
                  }
                ),
              ),
              const SizedBox(height: 8),

              // ── Smart Chat: Respostas Rápidas ──
              if (_loadingReplies)
                const SizedBox(
                  height: 36,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_quickReplies.isNotEmpty)
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _quickReplies.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final reply = _quickReplies[i];
                      return ActionChip(
                        label: Text(
                          '${reply.icon} ${reply.text.split(' ').take(3).join(' ')}',
                          style: context.labelSmall?.copyWith(
                            color: ColorPalette.primary30,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                        ),
                        backgroundColor: ColorPalette.primary95,
                        side: const BorderSide(
                          color: ColorPalette.primary80,
                          width: 1,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        onPressed: _sendingQuickReply
                            ? null
                            : () => _sendQuickReply(reply),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),

              // ── Input de texto ──
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: textEditingController,
                      onChanged: (value) => setState(() => message = value),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: context.translate.typeAMessage,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  AppIconButton(
                    icon: Ionicons.send,
                    onPressed: message == null
                        ? null
                        : () {
                            context.read<TrackOrderBloc>().sendChatMessage(message!);
                            textEditingController.clear();
                            setState(() => message = null);
                          },
                  ),
                ],
              )
            ]),
          ),
        );
      },
    );
  }
}

/// Modelo interno de quick reply
class _QuickReplyItem {
  final String id;
  final String text;
  final String icon;

  const _QuickReplyItem({
    required this.id,
    required this.text,
    required this.icon,
  });
}

