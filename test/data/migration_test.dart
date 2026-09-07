import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/data/database.dart';
import 'package:pocket_ledger/domain/enums.dart';
import 'package:pocket_ledger/domain/money.dart';

import '../generated/schema/schema.dart';
import '../generated/schema/schema_v2.dart' as v2;
import 'test_database.dart';

/// Migration tests run the *real* migration against a database created from a
/// snapshot of the old schema (`drift_schemas/drift_schema_v1.json`, produced
/// by `dart run drift_dev schema dump`). They are the only way to find out
/// whether an upgrade actually works before a user's data is on the line.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('upgrading v1 -> v2 produces exactly the v2 schema', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);

    await verifier.migrateAndValidate(db, 2);

    await db.close();
  });

  test('upgrading preserves rows and backfills the new columns', () async {
    final schema = await verifier.schemaAt(1);

    // Populate the v1 database using v1-era SQL: no `categories.archived`,
    // no `budgets.period`.
    schema.rawDatabase
      ..execute(
        'INSERT INTO accounts (id, name, kind, opening_balance_minor, '
        'currency_code, color_value, archived, sort_order, created_at) '
        "VALUES (1, 'Everyday', 'checking', 25000, 'USD', 100, 0, 0, 1700000000)",
      )
      ..execute(
        'INSERT INTO categories (id, name, icon_key, color_value, kind, '
        'parent_id, created_at) '
        "VALUES (7, 'Groceries', 'groceries', 200, 'expense', NULL, 1700000000)",
      )
      ..execute(
        'INSERT INTO transactions (id, account_id, category_id, amount_minor, '
        'date, note, type, counterpart_id, created_at) '
        "VALUES (3, 1, 7, -4599, 1700000000, 'Market', 'expense', NULL, "
        '1700000000)',
      )
      ..execute(
        'INSERT INTO budgets (id, category_id, limit_minor, created_at) '
        'VALUES (2, 7, 60000, 1700000000)',
      );

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 2);
    await db.close();

    final migrated = v2.DatabaseAtV2(schema.newConnection());
    addTearDown(migrated.close);

    final account = await migrated
        .customSelect('SELECT * FROM accounts WHERE id = 1')
        .getSingle();
    expect(account.read<String>('name'), 'Everyday');
    expect(account.read<int>('opening_balance_minor'), 25000);

    final category = await migrated
        .customSelect('SELECT * FROM categories WHERE id = 7')
        .getSingle();
    expect(category.read<String>('name'), 'Groceries');
    // Added in v2, backfilled from the column default.
    expect(category.read<int>('archived'), 0);

    final entry = await migrated
        .customSelect('SELECT * FROM transactions WHERE id = 3')
        .getSingle();
    expect(entry.read<int>('amount_minor'), -4599);
    expect(entry.read<String>('note'), 'Market');

    final budget = await migrated
        .customSelect('SELECT * FROM budgets WHERE id = 2')
        .getSingle();
    expect(budget.read<int>('limit_minor'), 60000);
    // v1 budgets were monthly by convention; v2 makes that explicit.
    expect(budget.read<String>('period'), BudgetPeriod.monthly.name);
  });

  test(
    'a migrated database has the same columns and indices as a new one',
    () async {
      final schema = await verifier.schemaAt(1);
      final upgraded = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(upgraded, 2);
      final upgradedShape = await schemaShape(upgraded);
      await upgraded.close();

      final fresh = newTestDatabase();
      // Touch the database so `onCreate` runs.
      await fresh.transactionsDao.countAll();
      final freshShape = await schemaShape(fresh);
      await fresh.close();

      // Compared as sets: `ALTER TABLE ... ADD COLUMN` appends, so a migrated
      // `categories` table has `archived` last while a fresh one has it in
      // declaration order. That difference is invisible to SQL and irrelevant.
      expect(upgradedShape, freshShape);
    },
  );

  test('the app\'s real queries run against a migrated database', () async {
    final schema = await verifier.schemaAt(1);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 2);
    addTearDown(db.close);

    final accountId = await db.accountsDao.createAccount(
      name: 'Everyday',
      kind: AccountKind.checking,
      openingBalance: Money.major(500, Currency.usd),
      colorValue: 1,
    );
    final categoryId = await db.categoriesDao.createCategory(
      name: 'Dining',
      iconKey: 'dining',
      colorValue: 2,
      kind: CategoryKind.expense,
    );
    await db.transactionsDao.createEntry(
      accountId: accountId,
      categoryId: categoryId,
      amount: const Money(2500, Currency.usd),
      date: DateTime(2026, 3, 4),
      type: TransactionType.expense,
    );
    await db.budgetsDao.setLimit(
      categoryId: categoryId,
      period: BudgetPeriod.monthly,
      limit: Money.major(100, Currency.usd),
    );

    final progress = await db.budgetsDao
        .watchProgress(now: DateTime(2026, 3, 15), currency: Currency.usd)
        .first;
    expect(progress, hasLength(1));
    expect(progress.single.spent, const Money(2500, Currency.usd));

    final balances = await db.accountsDao.watchBalances().first;
    expect(balances.single.balance, const Money(47500, Currency.usd));
  });

  test('the v2 constraints survive the upgrade', () async {
    final schema = await verifier.schemaAt(1);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 2);
    addTearDown(db.close);

    await db.customStatement(
      'INSERT INTO categories (id, name, icon_key, color_value, kind, '
      'archived, created_at) '
      "VALUES (1, 'Dining', 'dining', 1, 'expense', 0, 1700000000)",
    );
    await db.customStatement(
      'INSERT INTO budgets (category_id, period, limit_minor, created_at) '
      "VALUES (1, 'monthly', 1000, 1700000000)",
    );

    // UNIQUE(category_id, period) only exists in v2, and only because the
    // migration rewrites the table rather than doing a plain ADD COLUMN.
    await expectLater(
      db.customStatement(
        'INSERT INTO budgets (category_id, period, limit_minor, created_at) '
        "VALUES (1, 'monthly', 2000, 1700000000)",
      ),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('UNIQUE'),
          'a UNIQUE constraint violation',
        ),
      ),
    );
  });
}
