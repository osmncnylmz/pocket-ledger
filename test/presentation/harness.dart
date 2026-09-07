import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/data/database.dart';
import 'package:pocket_ledger/presentation/providers.dart';
import 'package:pocket_ledger/presentation/settings.dart';
import 'package:pocket_ledger/presentation/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/test_database.dart';

/// A phone-sized surface, so the widget tests exercise the layout the app is
/// actually designed for rather than the 800x600 default.
const testSurface = Size(420, 900);

/// Mounts [child] with an in-memory database and mock preferences.
///
/// Returns the database so a test can keep writing to it and watch the UI
/// react through the same drift streams the real app uses.
Future<AppDatabase> pumpScreen(
  WidgetTester tester,
  Widget child, {
  AppDatabase? database,
  DateTime? now,
  Brightness brightness = Brightness.light,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  final db = database ?? newTestDatabase();

  await tester.binding.setSurfaceSize(testSurface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  if (database == null) addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        databaseProvider.overrideWithValue(db),
        if (now != null) nowProvider.overrideWithValue(now),
      ],
      child: MaterialApp(theme: buildAppTheme(brightness), home: child),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}
