import 'package:flutter/material.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/extensions/extensions.dart';
import 'package:flutter_tts/flutter_tts.dart';

class ChatItemOtherPerson extends StatelessWidget {
  final String message;
  final DateTime dateTime;

  const ChatItemOtherPerson({
    super.key,
    required this.message,
    required this.dateTime,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          constraints: BoxConstraints(maxWidth: context.width * 0.6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                decoration: const BoxDecoration(
                  color: ColorPalette.neutral90,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                    bottomLeft: Radius.circular(4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1464748B),
                      blurRadius: 8,
                      offset: Offset(2, 4),
                    ),
                  ],
                ),
                child: Text(
                  message,
                  style: context.bodyMedium?.copyWith(
                    color: context.theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                dateTime.formatTime,
                style: context.bodySmall?.copyWith(
                  color: ColorPalette.neutralVariant50,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () async {
            final tts = FlutterTts();
            await tts.setLanguage("pt-BR");
            await tts.setSpeechRate(0.55);
            await tts.setPitch(1.1);
            try {
              final dynamic raw = await tts.getVoices;
              if (raw is List) {
                final ptVoices = <Map<String, dynamic>>[];
                for (final v in raw) {
                  if (v is Map) {
                    final m = Map<String, dynamic>.from(v);
                    final locale = (m['locale'] ?? '').toString().toLowerCase();
                    if (locale.startsWith('pt')) ptVoices.add(m);
                  }
                }
                if (ptVoices.isNotEmpty) {
                  Map<String, dynamic>? chosen;
                  for (final v in ptVoices) {
                    final name = (v['name'] ?? '').toString().toLowerCase();
                    final gender = (v['gender'] ?? '').toString().toLowerCase();
                    if (gender.contains('female') ||
                        name.contains('female') ||
                        name.contains('woman') ||
                        name.contains('#female') ||
                        name.contains('-afs')) {
                      chosen = v;
                      break;
                    }
                  }
                  chosen ??= ptVoices.firstWhere(
                    (v) => (v['locale'] ?? '').toString().toLowerCase() == 'pt-br',
                    orElse: () => ptVoices.first,
                  );
                  await tts.setVoice({
                    'name': (chosen['name'] ?? '').toString(),
                    'locale': (chosen['locale'] ?? 'pt-BR').toString(),
                  });
                }
              }
            } catch (_) {}
            await tts.speak(message);
          },
          icon: const Icon(
            Icons.volume_up_rounded,
            color: ColorPalette.primary40,
            size: 20,
          ),
          tooltip: 'Ouvir mensagem por voz',
        ),
      ],
    );
  }
}
