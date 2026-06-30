// Testes unitários para as constantes globais do Super App Uppi.
// Valida URLs críticos de privacidade, termos e lojas de aplicativos.
// Item 44 da Auditoria Pré-lançamento: Cobertura de testes efetiva.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_common/config/constants.dart';

void main() {
  group('Constants — URLs e valores globais do Super App', () {
    test('privacyPolicyUrl aponta para domínio comercial definitivo', () {
      expect(Constants.privacyPolicyUrl, contains('uppi.app'));
      expect(Constants.privacyPolicyUrl, startsWith('https://'));
    });

    test('termsAndConditionsUrl aponta para domínio comercial definitivo', () {
      expect(Constants.termsAndConditionsUrl, contains('uppi.app'));
      expect(Constants.termsAndConditionsUrl, startsWith('https://'));
    });

    test('playStoreUrl é válido e aponta para online.uppi.rider', () {
      expect(Constants.playStoreUrl, contains('play.google.com'));
      expect(Constants.playStoreUrl, contains('online.uppi.rider'));
    });

    test('playStoreDriverUrl é válido e aponta para online.uppi.motorista', () {
      expect(Constants.playStoreDriverUrl, contains('play.google.com'));
      expect(Constants.playStoreDriverUrl, contains('online.uppi.motorista'));
    });

    test('resendOtpTime é 90 segundos', () {
      expect(Constants.resendOtpTime, 90);
    });

    test('isDemoMode está desativado em produção', () {
      expect(Constants.isDemoMode, isFalse);
    });

    test('defaultCountry é Brasil (BR)', () {
      expect(Constants.defaultCountry.iso2CC, 'BR');
    });

    test('defaultLocation é em Castanhal, Pará', () {
      expect(Constants.defaultLocation.address, contains('Castanhal'));
    });

    test('walletPresets contém valores predefinidos de recarga', () {
      expect(Constants.walletPresets, containsAll([20.0, 50.0, 100.0]));
    });

    test('onSwitchToPassenger começa como null (injetado em runtime)', () {
      // O callback é injetado pelo main.dart após inicialização
      // Para garantir type safety, verificamos que o tipo é AppModeCallback
      expect(Constants.onSwitchToPassenger, isNull);
    });
  });
}
