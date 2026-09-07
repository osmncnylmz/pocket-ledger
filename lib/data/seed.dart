import 'dart:math';

import '../domain/date_range.dart';
import '../domain/enums.dart';
import '../domain/money.dart';
import '../domain/services/transfer.dart';
import 'database.dart';

typedef _SeedCategory = ({
  String name,
  String iconKey,
  int color,
  CategoryKind kind,
});

const _defaultCategories = <_SeedCategory>[
  (
    name: 'Groceries',
    iconKey: 'groceries',
    color: 0xFF2E7D32,
    kind: CategoryKind.expense,
  ),
  (
    name: 'Rent',
    iconKey: 'home',
    color: 0xFF5E35B1,
    kind: CategoryKind.expense,
  ),
  (
    name: 'Transport',
    iconKey: 'transport',
    color: 0xFF00838F,
    kind: CategoryKind.expense,
  ),
  (
    name: 'Dining',
    iconKey: 'dining',
    color: 0xFFEF6C00,
    kind: CategoryKind.expense,
  ),
  (
    name: 'Utilities',
    iconKey: 'utilities',
    color: 0xFF00695C,
    kind: CategoryKind.expense,
  ),
  (
    name: 'Health',
    iconKey: 'health',
    color: 0xFFC2185B,
    kind: CategoryKind.expense,
  ),
  (
    name: 'Entertainment',
    iconKey: 'entertainment',
    color: 0xFF6A1B9A,
    kind: CategoryKind.expense,
  ),
  (
    name: 'Shopping',
    iconKey: 'shopping',
    color: 0xFFAD1457,
    kind: CategoryKind.expense,
  ),
  (
    name: 'Travel',
    iconKey: 'travel',
    color: 0xFF1565C0,
    kind: CategoryKind.expense,
  ),
  (
    name: 'Subscriptions',
    iconKey: 'subscriptions',
    color: 0xFF4527A0,
    kind: CategoryKind.expense,
  ),
  (
    name: 'Salary',
    iconKey: 'salary',
    color: 0xFF2E7D32,
    kind: CategoryKind.income,
  ),
  (
    name: 'Freelance',
    iconKey: 'freelance',
    color: 0xFF00796B,
    kind: CategoryKind.income,
  ),
  (
    name: 'Interest',
    iconKey: 'interest',
    color: 0xFF827717,
    kind: CategoryKind.income,
  ),
  (
    name: 'Gifts',
    iconKey: 'gift',
    color: 0xFFD84315,
    kind: CategoryKind.income,
  ),
];

/// Separate from [seedDefaults] so the sample-data loader can rebuild the
/// list after wiping the ledger.
Future<void> insertDefaultCategories(AppDatabase db) {
  return db.batch((batch) {
    batch.insertAll(db.categories, [
      for (final category in _defaultCategories)
        CategoriesCompanion.insert(
          name: category.name,
          iconKey: category.iconKey,
          colorValue: category.color,
          kind: category.kind,
        ),
    ]);
  });
}

/// Runs on every launch, and does nothing once a single category exists.
Future<void> seedDefaults(AppDatabase db, {required Currency currency}) async {
  final existing = await db.categoriesDao.allCategories(includeArchived: true);
  if (existing.isNotEmpty) return;

  await db.transaction(() async {
    await insertDefaultCategories(db);

    final accounts = await db.accountsDao.allAccounts(includeArchived: true);
    if (accounts.isEmpty) {
      await db.accountsDao.createAccount(
        name: 'Everyday',
        kind: AccountKind.checking,
        openingBalance: Money.zero(currency),
        colorValue: 0xFF3F51B5,
      );
      await db.accountsDao.createAccount(
        name: 'Cash',
        kind: AccountKind.cash,
        openingBalance: Money.zero(currency),
        colorValue: 0xFF00897B,
      );
    }
  });
}

/// Replaces the ledger with six months of plausible sample data, so a fresh
/// install has something to show in the charts. Deterministic: the same
/// [randomSeed] gives the same ledger, which makes it usable in tests too.
Future<void> loadSampleData(
  AppDatabase db, {
  required Currency currency,
  DateTime? now,
  int randomSeed = 20260101,
}) async {
  final today = now ?? DateTime.now();
  final random = Random(randomSeed);

  await db.transaction(() async {
    await db.delete(db.transactions).go();
    await db.delete(db.budgets).go();
    await db.delete(db.accounts).go();
    await db.delete(db.categories).go();

    await insertDefaultCategories(db);

    final everyday = await db.accountsDao.createAccount(
      name: 'Everyday',
      kind: AccountKind.checking,
      openingBalance: Money.major(1200, currency),
      colorValue: 0xFF3F51B5,
    );
    final savings = await db.accountsDao.createAccount(
      name: 'Savings',
      kind: AccountKind.savings,
      openingBalance: Money.major(6400, currency),
      colorValue: 0xFF00897B,
    );
    final card = await db.accountsDao.createAccount(
      name: 'Credit card',
      kind: AccountKind.credit,
      openingBalance: Money.major(-320, currency),
      colorValue: 0xFFD81B60,
    );

    final categories = await db.categoriesDao.allCategories();
    int categoryId(String name) =>
        categories.firstWhere((c) => c.name == name).id;

    // (category, typical amount in major units, spread, times per month)
    const recurring = <({String category, int base, int spread, int perMonth})>[
      (category: 'Groceries', base: 62, spread: 40, perMonth: 8),
      (category: 'Dining', base: 28, spread: 22, perMonth: 5),
      (category: 'Transport', base: 14, spread: 10, perMonth: 6),
      (category: 'Entertainment', base: 22, spread: 18, perMonth: 2),
      (category: 'Shopping', base: 55, spread: 60, perMonth: 2),
      (category: 'Health', base: 40, spread: 30, perMonth: 1),
      (category: 'Travel', base: 180, spread: 140, perMonth: 1),
    ];

    final months = DateRange.lastMonths(today, 6);
    for (final month in months) {
      final daysInMonth = month.days;

      // Salary on the 25th, or the last day of a shorter month.
      await db.transactionsDao.createEntry(
        accountId: everyday,
        categoryId: categoryId('Salary'),
        amount: Money(
          Money.major(3250, currency).minorUnits + random.nextInt(9000),
          currency,
        ),
        date: _dayIn(month.start, min(25, daysInMonth)),
        type: TransactionType.income,
        note: 'Monthly salary',
      );

      await db.transactionsDao.createEntry(
        accountId: everyday,
        categoryId: categoryId('Rent'),
        amount: Money.major(1150, currency),
        date: _dayIn(month.start, 1),
        type: TransactionType.expense,
        note: 'Rent',
      );

      await db.transactionsDao.createEntry(
        accountId: everyday,
        categoryId: categoryId('Utilities'),
        amount: Money(
          Money.major(70, currency).minorUnits + random.nextInt(6000),
          currency,
        ),
        date: _dayIn(month.start, min(12, daysInMonth)),
        type: TransactionType.expense,
        note: 'Electricity and water',
      );
      await db.transactionsDao.createEntry(
        accountId: card,
        categoryId: categoryId('Subscriptions'),
        amount: Money(1899, currency),
        date: _dayIn(month.start, min(8, daysInMonth)),
        type: TransactionType.expense,
        note: 'Streaming',
      );

      for (final pattern in recurring) {
        for (var i = 0; i < pattern.perMonth; i++) {
          final day = 1 + random.nextInt(daysInMonth);
          if (_dayIn(month.start, day).isAfter(today)) continue;
          final major = pattern.base + random.nextInt(pattern.spread);
          await db.transactionsDao.createEntry(
            accountId: random.nextInt(4) == 0 ? card : everyday,
            categoryId: categoryId(pattern.category),
            amount: Money(
              major * currency.minorUnitsPerMajor + random.nextInt(100),
              currency,
            ),
            date: _dayIn(month.start, day),
            type: TransactionType.expense,
          );
        }
      }

      // A standing order into savings just after payday.
      final everydayAccount = await db.accountsDao.findById(everyday);
      final savingsAccount = await db.accountsDao.findById(savings);
      if (everydayAccount != null && savingsAccount != null) {
        final transferDay = min(26, daysInMonth);
        if (!_dayIn(month.start, transferDay).isAfter(today)) {
          await db.transactionsDao.createTransfer(
            TransferDraft(
              from: everydayAccount,
              to: savingsAccount,
              amount: Money.major(400, currency),
              date: _dayIn(month.start, transferDay),
              note: 'Standing order',
            ),
          );
        }
      }
    }

    // Enough budgets that the budgets screen has something to show.
    await db.budgetsDao.setLimit(
      categoryId: categoryId('Groceries'),
      period: BudgetPeriod.monthly,
      limit: Money.major(600, currency),
    );
    await db.budgetsDao.setLimit(
      categoryId: categoryId('Dining'),
      period: BudgetPeriod.monthly,
      limit: Money.major(150, currency),
    );
    await db.budgetsDao.setLimit(
      categoryId: categoryId('Transport'),
      period: BudgetPeriod.monthly,
      limit: Money.major(120, currency),
    );
    await db.budgetsDao.setLimit(
      categoryId: categoryId('Entertainment'),
      period: BudgetPeriod.monthly,
      limit: Money.major(80, currency),
    );
  });
}

DateTime _dayIn(DateTime month, int day) =>
    DateTime(month.year, month.month, day, 9, 30);
