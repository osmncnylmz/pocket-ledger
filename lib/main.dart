import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/database.dart';
import 'data/seed.dart';
import 'domain/money.dart';
import 'presentation/app.dart';
import 'presentation/providers.dart';
import 'presentation/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Both are cheap and local. Having them ready before the first frame means
  // no screen ever has to render a "loading your settings" state.
  final preferences = await SharedPreferences.getInstance();
  final database = AppDatabase.open();

  final currencyCode = preferences.getString('settings.currencyCode');
  await seedDefaults(
    database,
    currency: currencyCode == null
        ? Currency.usd
        : Currency.byCode(currencyCode),
  );

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        databaseProvider.overrideWithValue(database),
      ],
      child: const PocketLedgerApp(),
    ),
  );
}
