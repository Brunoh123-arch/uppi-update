import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel/layout/menu_items.dart';

void main() {
  group('AdminMenuItem tests', () {
    test('should construct AdminMenuItem correctly', () {
      const item = AdminMenuItem(
        icon: Icons.home,
        selectedIcon: Icons.home_filled,
        label: 'Test Label',
        content: SizedBox(),
        allowedRoles: ['admin', 'superadmin'],
      );

      expect(item.label, equals('Test Label'));
      expect(item.allowedRoles, contains('admin'));
      expect(item.allowedRoles, contains('superadmin'));
      expect(item.allowedRoles.length, equals(2));
    });

    test('should allow specific roles to access item', () {
      const item = AdminMenuItem(
        icon: Icons.lock,
        selectedIcon: Icons.lock_open,
        label: 'Secret Settings',
        content: SizedBox(),
        allowedRoles: ['superadmin'],
      );

      expect(item.allowedRoles.contains('superadmin'), isTrue);
      expect(item.allowedRoles.contains('operator'), isFalse);
      expect(item.allowedRoles.contains('admin'), isFalse);
    });
  });
}
