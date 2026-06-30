import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Serviço de alerta por voz para prevenção de perdas de objetos.
/// Reproduz mensagem TTS quando o motorista chega ao destino ou finaliza a corrida.
class ArrivalReminderService {
  static final ArrivalReminderService _instance = ArrivalReminderService._();
  factory ArrivalReminderService() => _instance;
  ArrivalReminderService._();

  FlutterTts? _tts;
  bool _initialized = false;

  static const String _reminderMessage =
      'Estamos chegando ao seu destino. '
      'Por favor, verifique se não esqueceu chaves, celular, carteira ou pertences no veículo. '
      'Obrigado por viajar com a Uppi!';

  /// Inicializa o motor TTS com configurações de voz feminina em pt-BR
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      _tts = FlutterTts();
      await _tts!.setLanguage('pt-BR');
      await _tts!.setSpeechRate(0.55); // Ritmo mais rápido e natural, sem lentidão
      await _tts!.setVolume(1.0);
      await _tts!.setPitch(1.1); // Tom levemente mais alto → voz feminina
      await _applyFemaleVoice(_tts!);
      _initialized = true;
    } catch (e) {
      debugPrint('[ArrivalReminder] Falha ao inicializar TTS: $e');
    }
  }

  /// Procura e fixa uma voz feminina em português no motor TTS do aparelho.
  Future<void> _applyFemaleVoice(FlutterTts tts) async {
    try {
      final dynamic raw = await tts.getVoices;
      if (raw is! List) return;

      final ptVoices = <Map<String, dynamic>>[];
      for (final v in raw) {
        if (v is Map) {
          final m = Map<String, dynamic>.from(v);
          final locale = (m['locale'] ?? '').toString().toLowerCase();
          if (locale.startsWith('pt')) ptVoices.add(m);
        }
      }
      if (ptVoices.isEmpty) return;

      // 1ª escolha: alguma voz marcada/nomeada como feminina.
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

      // Fallback: prioriza pt-BR (sobre pt-PT) se nada vier marcado.
      chosen ??= ptVoices.firstWhere(
        (v) => (v['locale'] ?? '').toString().toLowerCase() == 'pt-br',
        orElse: () => ptVoices.first,
      );

      await tts.setVoice({
        'name': (chosen['name'] ?? '').toString(),
        'locale': (chosen['locale'] ?? 'pt-BR').toString(),
      });
    } catch (_) {
      // Mantém pt-BR padrão como fallback seguro.
    }
  }

  /// Reproduz o lembrete de objetos esquecidos via TTS.
  /// Deve ser chamado quando o motorista clica em "Chegar ao Destino" ou "Finalizar Corrida".
  Future<void> playArrivalReminder() async {
    try {
      await _ensureInitialized();
      if (_tts == null) return;

      await _tts!.speak(_reminderMessage);
      debugPrint('[ArrivalReminder] 🔊 Lembrete de objetos reproduzido com sucesso.');
    } catch (e) {
      debugPrint('[ArrivalReminder] Falha ao reproduzir lembrete: $e');
      // Não bloquear o fluxo principal — áudio é melhoria, não requisito
    }
  }

  /// Para a reprodução de áudio (caso o usuário saia da tela)
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  /// Libera recursos do TTS
  void dispose() {
    _tts?.stop();
    _initialized = false;
  }
}
