import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/data/backup_service.dart';
import 'package:pocket_ledger/data/database.dart';
import 'package:pocket_ledger/data/seed.dart';
import 'package:pocket_ledger/domain/enums.dart';
import 'package:pocket_ledger/domain/money.dart';
import 'package:pocket_ledger/domain/services/transfer.dart';

import 'fixtures.dart';
import 'test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = newTestDatabase());
  tearDown(() => db.close());

  Future<void> buildLedger() async {
    final everyday = await db.makeAccount(
      'Everyday',
      openingBalance: Money.major(1000, Currency.usd),
    );
    final savings = await db.makeAccount(
      'Savings',
      kind: AccountKind.savings,
      openingBalance: Money.major(4000, Currency.usd),
    );
    final food = await db.makeCategory('Food');
    await db.makeCategory('Groceries', parentId: food.id);
    final salary = await db.makeCategory('Salary', kind: CategoryKind.income);

    await db.spend(everyday, food, 4599, DateTime(2026, 3, 2), note: 'Market');
    await db.earn(everyday, salary, 300000, DateTime(2026, 3, 25));
    await db.transactionsDao.createTransfer(
      TransferDraft(
        from: everyday,
        to: savings,
        amount: Money.major(400, Currency.usd),
        date: DateTime(2026, 3, 26),
        note: 'Standing order',
      ),
    );
    await db.budgetsDao.setLimit(
      categoryId: food.id,
      period: BudgetPeriod.monthly,
      limit: Money.major(600, Currency.usd),
    );
  }

  test('export then import reproduces the database exactly', () async {
    await buildLedger();
    final service = BackupService(db);

    final before = await _snapshot(db);
    final json = await service.exportToJson(now: DateTime.utc(2026, 4));

    final summary = await service.importFromJson(json);
    expect(summary.accounts, 2);
    expect(summary.categories, 3);
    expect(summary.transactions, 4);
    expect(summary.budgets, 1);

    expect(await _snapshot(db), before);
  });

  test('a backup restores into an empty database', () async {
    await buildLedger();
    final json = await BackupService(db).exportToJson();
    final before = await _snapshot(db);

    final restored = newTestDatabase();
    addTearDown(restored.close);
    await BackupService(restored).importFromJson(json);

    expect(await _snapshot(restored), before);

    // And the restored ledger still balances.
    final totals = await restored.accountsDao.watchTotalsByCurrency().first;
    expect(totals[Currency.usd], const Money(795401, Currency.usd));
  });

  test('transfer links survive the round trip', () async {
    await buildLedger();
    final json = await BackupService(db).exportToJson();

    final restored = newTestDatabase();
    addTearDown(restored.close);
    await BackupService(restored).importFromJson(json);

    final legs = await (restored.select(
      restored.transactions,
    )..where((t) => t.type.equalsValue(TransactionType.transfer))).get();

    expect(legs, hasLength(2));
    expect(legs[0].counterpartId, legs[1].id);
    expect(legs[1].counterpartId, legs[0].id);
    expect(legs[0].amountMinor + legs[1].amountMinor, 0);
  });

  test('a category referencing a parent later in the file still imports', () async {
    await buildLedger();
    final document = jsonDecode(
      await BackupService(db).exportToJson(),
    ) as Map<String, Object?>;
    // Reverse the categories so children arrive before their parents. Deferred
    // foreign keys are what makes this work.
    document['categories'] = (document['categories']! as List).reversed
        .toList();

    final restored = newTestDatabase();
    addTearDown(restored.close);
    await BackupService(restored).importFromJson(jsonEncode(document));

    final categories = await restored.categoriesDao.allCategories();
    final child = categories.firstWhere((c) => c.name == 'Groceries');
    expect(child.parentId, isNotNull);
  });

  test('the export is human readable JSON with a format marker', () async {
    await buildLedger();
    final json = await BackupService(db).exportToJson();

    expect(json, contains('\n'));
    final document = jsonDecode(json) as Map<String, Object?>;
    expect(document['format'], 'pocket-ledger.backup');
    expect(document['formatVersion'], 1);
    expect(document['schemaVersion'], db.schemaVersion);
    expect(document['exportedAt'], isA<String>());
  });

  test('garbage is rejected without touching the ledger', () async {
    await buildLedger();
    final before = await _snapshot(db);
    final service = BackupService(db);

    await expectLater(
      service.importFromJson('not json at all'),
      throwsA(isA<BackupFormatException>()),
    );
    await expectLater(
      service.importFromJson('{"format": "something-else"}'),
      throwsA(isA<BackupFormatException>()),
    );
    await expectLater(
      service.importFromJson(
        '{"format": "pocket-ledger.backup", "formatVersion": 99}',
      ),
      throwsA(isA<BackupFormatException>()),
    );

    expect(await _snapshot(db), before);
  });

  test('a half-valid file leaves the existing ledger untouched', () async {
    await buildLedger();
    final before = await _snapshot(db);

    final document = jsonDecode(
      await BackupService(db).exportToJson(),
    ) as Map<String, Object?>;
    // Corrupt the last transaction only: the accounts and categories ahead of
    // it are perfectly valid and would be written by a non-transactional
    // importer.
    final transactions = document['transactions']! as List;
    (transactions.last as Map<String, Object?>)['amountMinor'] = 'lots';

    await expectLater(
      BackupService(db).importFromJson(jsonEncode(document)),
      throwsA(isA<BackupFormatException>()),
    );
    expect(await _snapshot(db), before);
  });

  test('a sample ledger survives a round trip', () async {
    await loadSampleData(
      db,
      currency: Currency.usd,
      now: DateTime(2026, 6, 15),
    );
    final before = await _snapshot(db);
    expect(await db.transactionsDao.countAll(), greaterThan(100));

    final json = await BackupService(db).exportToJson();
    final restored = newTestDatabase();
    addTearDown(restored.close);
    await BackupService(restored).importFromJson(json);

    expect(await _snapshot(restored), before);
  });
}

/// Every row of every table, as comparable strings.
Future<Map<String, List<String>>> _snapshot(AppDatabase db) async {
  Future<List<String>> dump(String table) async {
    final rows = await db
        .customSelect('SELECT * FROM $table ORDER BY id')
        .get();
    return rows.map((row) => row.data.toString()).toList();
  }

  return {
    'accounts': await dump('accounts'),
    'categories': await dump('categories'),
    'transactions': await dump('transactions'),
    'budgets': await dump('budgets'),
  };
}
