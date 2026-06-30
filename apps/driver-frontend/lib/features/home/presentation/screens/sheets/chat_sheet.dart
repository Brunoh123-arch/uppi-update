import 'package:uppi_motorista/features/home/presentation/blocs/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:flutter_common/core/presentation/uppi_feedback.dart';
import 'package:ionicons/ionicons.dart';
import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/entities/order.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:flutter_common/core/presentation/buttons/app_back_button.dart';
import 'package:flutter_common/core/presentation/buttons/app_icon_button.dart';
import 'package:flutter_common/features/chat/chat.dart';

class ChatSheet extends StatefulWidget {
  final OrderEntity order;

  const ChatSheet({super.key, required this.order});

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  String? message;
  TextEditingController textEditingController = TextEditingController();
  ScrollController scrollController = ScrollController();

  // Smart Chat — respostas rápidas dinâmicas
  List<_QuickReplyItem> _quickReplies = [];
  bool _loadingReplies = true;
  bool _sendingQuickReply = false;

  @override
  void initState() {
    super.initState();
    _loadQuickReplies();
  }

  Future<void> _loadQuickReplies() async {
    final name = widget.order.riderFirstName ?? '';
    final hasRealName = name.isNotEmpty && name.toLowerCase() != 'passageiro';
    final greetingText = hasRealName ? 'Olá, $name!' : 'Olá!';

    setState(() {
      _quickReplies = [
        _QuickReplyItem(
          id: 'driver_greeting',
          text: greetingText,
          icon: '👋',
        ),
        const _QuickReplyItem(
          id: 'driver_on_way',
          text: 'Estou a caminho',
          icon: '🚗',
        ),
        const _QuickReplyItem(
          id: 'driver_arrived',
          text: 'Cheguei no local',
          icon: '📍',
        ),
        const _QuickReplyItem(
          id: 'driver_thanks',
          text: 'Ok, obrigado!',
          icon: '👍',
        ),
        const _QuickReplyItem(
          id: 'driver_waiting',
          text: 'Estou esperando',
          icon: '⏱️',
        ),
      ];
      _loadingReplies = false;
    });
  }

  Future<void> _sendQuickReply(_QuickReplyItem reply) async {
    if (_sendingQuickReply) return;
    setState(() => _sendingQuickReply = true);
    try {
      UppiFeedback.triggerLight(); // Acessibilidade: Alerta Háptico no chip de resposta rápida
      if (mounted) {
        context.read<HomeBloc>().sendChatMessage(reply.text);
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
    return BlocConsumer<HomeBloc, HomeState>(
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
            child: Column(
              children: [
                // ── Header ──
                Row(
                  children: [
                    AppBackButton(
                      onPressed: () =>
                          locator<HomeBloc>().add(const HomeEvent.onHideChat()),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        widget.order.riderFullName,
                        style: context.titleMedium,
                      ),
                    ),
                    AppIconButton(
                      icon: Ionicons.call,
                      onPressed: () async {
                        final phone = widget.order.riderPhoneNumber;
                        if (phone.isNotEmpty) {
                          final uri = Uri.parse('tel:$phone');
                          try {
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri);
                            } else {
                              throw Exception('Não pôde iniciar ligação convencional');
                            }
                          } catch (_) {
                            if (!mounted) return;
                            context.showSnackBar(
                              message: 'Não foi possível iniciar a chamada convencional.',
                            );
                          }
                        } else {
                          if (!mounted) return;
                          context.showSnackBar(
                            message: 'Número do passageiro não disponível.',
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
                      final bloc = context.read<HomeBloc>();
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
                            '${reply.icon} ${reply.text}',
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
                            horizontal: 8,
                            vertical: 2,
                          ),
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
                              context.read<HomeBloc>().sendChatMessage(message!);
                              textEditingController.clear();
                              setState(() => message = null);
                            },
                    ),
                  ],
                ),
              ],
            ),
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


