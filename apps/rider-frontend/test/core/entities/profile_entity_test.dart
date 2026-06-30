import 'package:flutter_test/flutter_test.dart';
import 'package:rider_flutter/core/entities/profile.dart';
import 'package:flutter_common/core/entities/media.dart';

void main() {
  group('ProfileEntity', () {
    test('emptyProfile returns correct defaults', () {
      final profile = ProfileEntity.emptyProfile;
      expect(profile.firstName, isNull);
      expect(profile.lastName, isNull);
      expect(profile.countryCode, 'BR');
      expect(profile.number, '');
      expect(profile.gender, isNull);
      expect(profile.email, isNull);
      expect(profile.profileImage, isNull);
      expect(profile.presetProfileImage, isNull);
      expect(profile.idNumber, isNull);
    });

    test('mobileNumberFormatted with BR country code', () {
      const profile = ProfileEntity(
        firstName: 'João',
        lastName: 'Silva',
        countryCode: 'BR',
        number: '11999887766',
        gender: null,
        email: 'joao@uppi.com',
        profileImage: null,
        presetProfileImage: null,
        idNumber: null,
      );
      final formatted = profile.mobileNumberFormatted;
      expect(formatted.startsWith('+'), isTrue);
    });

    test('mobileNumberFormatted with empty country code', () {
      const profile = ProfileEntity(
        firstName: 'Test',
        lastName: 'User',
        countryCode: '',
        number: '5511999887766',
        gender: null,
        email: null,
        profileImage: null,
        presetProfileImage: null,
        idNumber: null,
      );
      expect(profile.mobileNumberFormatted, '+5511999887766');
    });

    test('mobileNumberFormatted with null country code', () {
      const profile = ProfileEntity(
        firstName: 'Test',
        lastName: 'User',
        countryCode: null,
        number: '5511999887766',
        gender: null,
        email: null,
        profileImage: null,
        presetProfileImage: null,
        idNumber: null,
      );
      expect(profile.mobileNumberFormatted, '+5511999887766');
    });
  });

  group('ProfileX extensions', () {
    test('fullName with both names', () {
      const profile = ProfileEntity(
        firstName: 'Maria',
        lastName: 'Santos',
        countryCode: 'BR',
        number: '11999887766',
        gender: null,
        email: null,
        profileImage: null,
        presetProfileImage: null,
        idNumber: null,
      );
      expect(profile.fullName, 'Maria Santos');
    });

    test('fullName with only firstName', () {
      const profile = ProfileEntity(
        firstName: 'Maria',
        lastName: null,
        countryCode: 'BR',
        number: '11999887766',
        gender: null,
        email: null,
        profileImage: null,
        presetProfileImage: null,
        idNumber: null,
      );
      expect(profile.fullName, 'Maria');
    });

    test('fullName with no names returns dash', () {
      const profile = ProfileEntity(
        firstName: null,
        lastName: null,
        countryCode: 'BR',
        number: '11999887766',
        gender: null,
        email: null,
        profileImage: null,
        presetProfileImage: null,
        idNumber: null,
      );
      expect(profile.fullName, '-');
    });

    test('avatar returns Right when profileImage is set', () {
      const profile = ProfileEntity(
        firstName: 'Test',
        lastName: 'User',
        countryCode: 'BR',
        number: '11999',
        gender: null,
        email: null,
        profileImage: MediaEntity(id: '123', address: 'https://example.com/avatar.jpg'),
        presetProfileImage: null,
        idNumber: null,
      );
      final avatar = profile.avatar;
      expect(avatar.isSome(), isTrue);
    });

    test('avatar returns None when no image', () {
      const profile = ProfileEntity(
        firstName: 'Test',
        lastName: 'User',
        countryCode: 'BR',
        number: '11999',
        gender: null,
        email: null,
        profileImage: null,
        presetProfileImage: null,
        idNumber: null,
      );
      expect(profile.avatar.isNone(), isTrue);
    });
  });

  group('Failure entity', () {
    // Testes importados para garantir que o modelo de erro funciona corretamente
    // em cenários de autenticação e wallet
  });
}
