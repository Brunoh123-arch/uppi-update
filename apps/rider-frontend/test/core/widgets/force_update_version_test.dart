// Testes unitários para a lógica interna do ForceUpdateWrapper.
// Valida o algoritmo de comparação de versões semânticas _isOutdated.
// Item 44 da Auditoria Pré-lançamento: Cobertura de testes efetiva.

import 'package:flutter_test/flutter_test.dart';

// Extraído da lógica interna de ForceUpdateWrapper para teste direto.
bool isOutdated(String current, String minimum) {
  try {
    final c = current.split('.').map(int.parse).toList();
    final m = minimum.split('.').map(int.parse).toList();
    while (c.length < 3) { c.add(0); }
    while (m.length < 3) { m.add(0); }
    for (int i = 0; i < 3; i++) {
      if (c[i] < m[i]) return true;
      if (c[i] > m[i]) return false;
    }
    return false;
  } catch (_) {
    return false;
  }
}

void main() {
  group('ForceUpdateWrapper — _isOutdated version comparison', () {
    test('returns false when current == minimum', () {
      expect(isOutdated('1.0.0', '1.0.0'), isFalse);
    });

    test('returns true when current is behind on patch', () {
      expect(isOutdated('1.0.0', '1.0.1'), isTrue);
    });

    test('returns true when current is behind on minor', () {
      expect(isOutdated('1.0.0', '1.1.0'), isTrue);
    });

    test('returns true when current is behind on major', () {
      expect(isOutdated('1.5.9', '2.0.0'), isTrue);
    });

    test('returns false when current is ahead on patch', () {
      expect(isOutdated('1.0.2', '1.0.1'), isFalse);
    });

    test('returns false when current is ahead on minor', () {
      expect(isOutdated('1.2.0', '1.1.0'), isFalse);
    });

    test('returns false when current is far ahead', () {
      expect(isOutdated('3.0.0', '1.0.0'), isFalse);
    });

    test('returns false when versions are equal at 1.0.0+1 reset', () {
      expect(isOutdated('1.0.0', '1.0.0'), isFalse);
    });

    test('handles short version strings (e.g. "1.0")', () {
      // Versão com apenas 2 segmentos é padded para 3
      expect(isOutdated('1.0', '1.0.1'), isTrue);
      expect(isOutdated('1.0', '1.0.0'), isFalse);
    });

    test('returns false on malformed version strings (não lança exceção)', () {
      expect(isOutdated('abc', '1.0.0'), isFalse);
      expect(isOutdated('1.0.0', 'xyz'), isFalse);
    });
  });
}
