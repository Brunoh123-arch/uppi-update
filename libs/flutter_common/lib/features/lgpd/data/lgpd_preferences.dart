import 'package:hive_flutter/hive_flutter.dart';

/// Persists LGPD consent choices using Hive (same storage as the apps).
class LgpdPreferences {
  static const _boxName = 'lgpd_prefs';
  static const _consentKey = 'lgpd_consent_given';
  static const _consentDateKey = 'lgpd_consent_date';
  static const _analyticsKey = 'lgpd_analytics';
  static const _marketingKey = 'lgpd_marketing';
  static const _locationKey = 'lgpd_location';

  static late Box _box;

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  /// Returns true if the user has accepted the required terms.
  static bool get hasGivenConsent => _box.get(_consentKey, defaultValue: false);

  /// Date when consent was given (ISO8601 string).
  static String? get consentDate => _box.get(_consentDateKey);

  /// Optional consent for analytics (e.g. Sentry, crash reports).
  static bool get analyticsConsent =>
      _box.get(_analyticsKey, defaultValue: false);

  /// Optional consent for marketing/push notifications.
  static bool get marketingConsent =>
      _box.get(_marketingKey, defaultValue: false);

  /// Explicit consent for precise location tracking.
  static bool get locationConsent =>
      _box.get(_locationKey, defaultValue: false);

  /// Records that the user accepted required LGPD terms.
  static Future<void> giveConsent({
    required bool analytics,
    required bool marketing,
    required bool location,
  }) async {
    await _box.put(_consentKey, true);
    await _box.put(_consentDateKey, DateTime.now().toIso8601String());
    await _box.put(_analyticsKey, analytics);
    await _box.put(_marketingKey, marketing);
    await _box.put(_locationKey, location);
  }

  /// Revokes all optional consents (user can do this in settings).
  /// Required terms (ToS + Privacy) stay — user must delete account to remove.
  static Future<void> revokeOptionalConsents() async {
    await _box.put(_analyticsKey, false);
    await _box.put(_marketingKey, false);
    await _box.put(_locationKey, false);
  }

  /// Fully wipes consent record — used on account deletion.
  static Future<void> clearAll() async {
    await _box.clear();
  }
}
