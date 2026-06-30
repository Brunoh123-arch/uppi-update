import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_common/core/utils/cpf_input_formatter.dart';
import 'package:flutter_common/core/utils/uppercase_input_formatter.dart';

void main() {
  group('CpfInputFormatter tests', () {
    late CpfInputFormatter formatter;

    setUp(() {
      formatter = CpfInputFormatter();
    });

    test('should format numbers into CPF format', () {
      const oldValue = TextEditingValue.empty;
      const newValue = TextEditingValue(text: '12345678900');
      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, equals('123.456.789-00'));
    });

    test('should ignore non-numeric characters', () {
      const oldValue = TextEditingValue.empty;
      const newValue = TextEditingValue(text: '123a456b789c00');
      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, equals('123.456.789-00'));
    });

    test('should truncate text longer than 11 digits', () {
      const oldValue = TextEditingValue.empty;
      const newValue = TextEditingValue(text: '123456789001234');
      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, equals('123.456.789-00'));
    });
  });

  group('UpperCaseTextFormatter tests', () {
    late UpperCaseTextFormatter formatter;

    setUp(() {
      formatter = UpperCaseTextFormatter();
    });

    test('should capitalize lowercase input', () {
      const oldValue = TextEditingValue.empty;
      const newValue = TextEditingValue(text: 'hello world');
      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, equals('HELLO WORLD'));
    });
  });
}
