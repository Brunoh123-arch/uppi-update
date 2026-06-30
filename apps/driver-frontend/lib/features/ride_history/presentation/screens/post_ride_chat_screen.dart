import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/presentation/snackbar/snackbar.dart';
import 'package:flutter_common/core/presentation/buttons/app_back_button.dart';
import 'package:flutter_common/core/presentation/buttons/app_icon_button.dart';
import 'package:flutter_common/features/chat/chat.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ionicons/ionicons.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'dart:convert';
import 'dart:async';

class PostRideChatScreen extends StatefulWidget {
  final String rideId;
  final String riderName;

  const PostRideChatScreen({
    super.key,
    required this.rideId,
    required this.riderName,
  });

  @override
  State<PostRideChatScreen> createState() => _PostRideChatScreenState();
}

class _PostRideChatScreenState extends State<PostRideChatScreen> {
  final List<ChatMessageEntity> _messages = [];
  bool _loading = true;
  String? _messageText;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _messagesSubscription;

  @override
  void initState() {
    super.initState();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _subscribeToMessages() {
    final supa = Supabase.instance.client;

    _messagesSubscription = supa
        .from('ride_messages')
        .stream(primaryKey: ['id'])
        .eq('ride_id', widget.rideId)
        .order('created_at')
        .listen((rows) {
          final loaded = rows.map((item) {
            // No app do motorista, isSender é true se a mensagem foi enviada pelo motorista (sent_by_driver == true)
            final isSender = item['sent_by_driver'] as bool? ?? false;
            return ChatMessageEntity(
              id: item['id'].toString(),
              message: item['content']?.toString() ?? '',
              isSender: isSender,
              createdAt: DateTime.parse(item['created_at'].toString()),
            );
          }).toList();

          if (mounted) {
            setState(() {
              _messages.clear();
              _messages.addAll(loaded);
              _loading = false;
            });
            _scrollToBottom();
          }
        }, onError: (e) {
          if (mounted) {
            context.showSnackBar(message: 'Erro ao carregar mensagens.');
            setState(() => _loading = false);
          }
        });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageText?.trim();
    if (text == null || text.isEmpty) return;

    _textController.clear();
    setState(() => _messageText = null);

    // Otimismo: insere mensagem na UI local antes da chamada HTTP terminar
    final tempId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final tempMsg = ChatMessageEntity(
      id: tempId,
      message: text,
      isSender: true,
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.add(tempMsg);
    });
    _scrollToBottom();

    try {
      final idToken = Supabase.instance.client.auth.currentSession?.accessToken;
      if (idToken == null) throw Exception("Sessão inválida");

      final response = await http.post(
        Uri.parse('${dotenv.env['SUPABASE_URL']}/functions/v1/chat-send-message'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'ride_id': widget.rideId,
          'content': text,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception("Erro HTTP ${response.statusCode}");
      }
    } catch (_) {
      if (mounted) {
        context.showSnackBar(message: 'Erro ao enviar mensagem.');
        // Remove a mensagem local temporária que falhou
        setState(() {
          _messages.removeWhere((m) => m.id == tempId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  AppBackButton(
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.riderName,
                          style: context.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Chat temporário pós-corrida',
                          style: context.bodySmall?.copyWith(
                            color: ColorPalette.neutralVariant50,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: ColorPalette.neutral90),

            // Mensagens
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _messages.isEmpty
                      ? Center(
                          child: Text(
                            'Nenhuma mensagem no chat.',
                            style: context.bodyMedium?.copyWith(
                              color: ColorPalette.neutral50,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final item = _messages[index];
                            if (item.isSender) {
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
                        ),
            ),

            // Input
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              decoration: const BoxDecoration(
                color: ColorPalette.neutral99,
                border: Border(
                  top: BorderSide(color: ColorPalette.neutral90, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      onChanged: (value) => setState(() => _messageText = value),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Digite uma mensagem...',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  AppIconButton(
                    icon: Ionicons.send,
                    onPressed: _messageText?.trim().isNotEmpty == true
                        ? _sendMessage
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
