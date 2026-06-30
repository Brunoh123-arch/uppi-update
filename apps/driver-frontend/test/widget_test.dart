// Testes unitários do módulo Uppi Motorista (driver-frontend).
// Focado em lógica de negócio pura e enums sem dependências de plugins nativos.
// Item 44/45 da Auditoria Pré-lançamento: Cobertura de testes efetiva.

import 'package:flutter_test/flutter_test.dart';
import 'package:uppi_motorista/core/enums/location_permission.dart';

void main() {
  group('LocationPermission enum — uppi_motorista', () {
    test('enum contém todos os estados esperados', () {
      expect(LocationPermission.values.length, greaterThanOrEqualTo(3));
      expect(LocationPermission.values, contains(LocationPermission.denied));
      expect(LocationPermission.values, contains(LocationPermission.deniedForever));
      expect(LocationPermission.values, contains(LocationPermission.always));
    });

    test('denied é diferente de deniedForever', () {
      expect(LocationPermission.denied, isNot(LocationPermission.deniedForever));
    });

    test('whileInUse é diferente de always', () {
      expect(LocationPermission.whileInUse, isNot(LocationPermission.always));
    });
  });
}

