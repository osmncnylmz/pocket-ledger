import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/enums.dart';
import '../domain/money.dart';

/// These live in `SharedPreferences`, not the database. They are per-device
/// — which theme this phone uses — so they must *not* travel inside a backup
/// that gets restored onto some other device.
class Settings {
  const Settings({required this.themeMode, required this.currency});

  final AppThemeMode themeMode;

  /// New accounts are created in this, and the dashboard aggregates over it.
  final Currency currency;

  static const defaults = Settings(
    themeMode: AppThemeMode.system,
    currency: Currency.usd,
  );

  Settings copyWith({AppThemeMode? themeMode, Currency? currency}) => Settings(
    themeMode: themeMode ?? this.themeMode,
    currency: currency ?? this.currency,
  );

  @override
  bool operator ==(Object other) =>
      other is Settings &&
      other.themeMode == themeMode &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(themeMode, currency);
}

/// Same override trick as `databaseProvider`; tests hand in a mock instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden with a loaded instance',
  ),
);

const _themeModeKey = 'settings.themeMode';
const _currencyKey = 'settings.currencyCode';

class SettingsController extends Notifier<Settings> {
  @override
  Settings build() {
    final prefs = ref.watch(sharedPreferencesProvider);

    final storedTheme = prefs.getString(_themeModeKey);
    final storedCurrency = prefs.getString(_currencyKey);

    return Settings(
      themeMode:
          AppThemeMode.values
              .where((mode) => mode.name == storedTheme)
              .firstOrNull ??
          Settings.defaults.themeMode,
      currency: storedCurrency != null && Currency.isSupported(storedCurrency)
          ? Currency.byCode(storedCurrency)
          : Settings.defaults.currency,
    );
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await ref
        .read(sharedPreferencesProvider)
        .setString(_themeModeKey, mode.name);
  }

  Future<void> setCurrency(Currency currency) async {
    state = state.copyWith(currency: currency);
    await ref
        .read(sharedPreferencesProvider)
        .setString(_currencyKey, currency.code);
  }
}

final settingsProvider = NotifierProvider<SettingsController, Settings>(
  SettingsController.new,
);
