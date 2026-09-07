import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/data/database.dart';
import 'package:pocket_ledger/domain/entities.dart';
import 'package:pocket_ledger/domain/enums.dart';
import 'package:pocket_ledger/domain/money.dart';
import 'package:pocket_ledger/domain/services/budget_evaluator.dart';
import 'package:pocket_ledger/domain/services/transfer.dart';

import 'fixtures.dart';
import 'test_database.dart';

void main() {
  late AppDatabase db;
  late Account everyday;
  late Category groceries;
  late Category dining;

  setUp(() async {
    db = newTestDatabase();
    everyday = await db.makeAccount('Everyday');
    groceries = await db.makeCategory('Groceries');
    dining = await db.makeCategory('Dining', iconKey: 'dining');
  });

  tearDown(() => db.close());

  Future<List<BudgetProgress>> progressAt(DateTime now) =>
      db.budgetsDao.watchProgress(now: now, currency: Currency.usd).first;

  test('a limit is one row per category and period', () async {
    await db.budgetsDao.setLimit(
      categoryId: groceries.id,
      period: BudgetPeriod.monthly,
      limit: Money.major(600, Currency.usd),
    );
    // Setting it again updates rather than duplicating.
    await db.budgetsDao.setLimit(
      categoryId: groceries.id,
      period: BudgetPeriod.monthly,
      limit: Money.major(500, Currency.usd),
    );
    // The same category can still carry a limit for a different period.
    await db.budgetsDao.setLimit(
      categoryId: groceries.id,
      period: BudgetPeriod.weekly,
      limit: Money.major(150, Currency.usd),
    );

    expect(await db.budgetsDao.countAll(), 2);
    final monthly = await db.budgetsDao.findForCategory(
      groceries.id,
      BudgetPeriod.monthly,
      Currency.usd,
    );
    expect(monthly!.limit, Money.major(500, Currency.usd));
  });

  test('progress sums only expenses inside the current month', () async {
    await db.budgetsDao.setLimit(
      categoryId: groceries.id,
      period: BudgetPeriod.monthly,
      limit: Money.major(600, Currency.usd),
    );

    await db.spend(everyday, groceries, 12000, DateTime(2026, 3, 2));
    await db.spend(everyday, groceries, 8000, DateTime(2026, 3, 17));
    // Last month: must not count.
    await db.spend(everyday, groceries, 50000, DateTime(2026, 2, 25));
    // A different category: must not count.
    await db.spend(everyday, dining, 9000, DateTime(2026, 3, 5));

    final progress = await progressAt(DateTime(2026, 3, 20));

    expect(progress, hasLength(1));
    expect(progress.single.spent, const Money(20000, Currency.usd));
    expect(progress.single.remaining, const Money(40000, Currency.usd));
    expect(progress.single.percentUsed, 33);
  });

  test('a budget with no spending still appears, at zero', () async {
    await db.budgetsDao.setLimit(
      categoryId: dining.id,
      period: BudgetPeriod.monthly,
      limit: Money.major(150, Currency.usd),
    );

    final progress = await progressAt(DateTime(2026, 3, 20));
    expect(progress.single.spent, const Money.zero(Currency.usd));
    expect(progress.single.health, BudgetHealth.onTrack);
  });

  test('weekly, monthly and yearly limits each use their own window', () async {
    await db.budgetsDao.setLimit(
      categoryId: groceries.id,
      period: BudgetPeriod.weekly,
      limit: Money.major(100, Currency.usd),
    );
    await db.budgetsDao.setLimit(
      categoryId: groceries.id,
      period: BudgetPeriod.monthly,
      limit: Money.major(600, Currency.usd),
    );
    await db.budgetsDao.setLimit(
      categoryId: groceries.id,
      period: BudgetPeriod.yearly,
      limit: Money.major(7000, Currency.usd),
    );

    // Wednesday 18 March 2026 sits in the week beginning Monday the 16th.
    await db.spend(everyday, groceries, 1500, DateTime(2026, 3, 18));
    // Earlier the same month, but the previous week.
    await db.spend(everyday, groceries, 2500, DateTime(2026, 3, 10));
    // Earlier the same year, but a previous month.
    await db.spend(everyday, groceries, 6000, DateTime(2026, 1, 8));
    // Previous year: outside every window.
    await db.spend(everyday, groceries, 90000, DateTime(2025, 12, 30));

    final progress = await progressAt(DateTime(2026, 3, 18));
    final byPeriod = {for (final p in progress) p.budget.period: p.spent};

    expect(byPeriod[BudgetPeriod.weekly], const Money(1500, Currency.usd));
    expect(byPeriod[BudgetPeriod.monthly], const Money(4000, Currency.usd));
    expect(byPeriod[BudgetPeriod.yearly], const Money(10000, Currency.usd));
  });

  test('spending past the limit reports over budget', () async {
    await db.budgetsDao.setLimit(
      categoryId: dining.id,
      period: BudgetPeriod.monthly,
      limit: Money.major(100, Currency.usd),
    );
    await db.spend(everyday, dining, 14000, DateTime(2026, 3, 4));

    final progress = await progressAt(DateTime(2026, 3, 20));
    expect(progress.single.health, BudgetHealth.overBudget);
    expect(progress.single.percentUsed, 140);
    expect(progress.single.remaining, const Money(-4000, Currency.usd));
    expect(progress.single.fractionUsed, 1.0);
  });

  test('spending faster than the calendar reports ahead of pace', () async {
    await db.budgetsDao.setLimit(
      categoryId: dining.id,
      period: BudgetPeriod.monthly,
      limit: Money.major(310, Currency.usd),
    );
    // Ten days into a 31 day month the even pace is $100.
    await db.spend(everyday, dining, 18000, DateTime(2026, 3, 4));

    final progress = await progressAt(DateTime(2026, 3, 10));
    expect(
      progress.single.expectedSpendAtPace,
      const Money(10000, Currency.usd),
    );
    expect(progress.single.health, BudgetHealth.aheadOfPace);
  });

  test('transfers and other currencies never count against a budget', () async {
    final savings = await db.makeAccount('Savings');
    final berlin = await db.makeAccount('Berlin', currency: Currency.eur);

    await db.budgetsDao.setLimit(
      categoryId: groceries.id,
      period: BudgetPeriod.monthly,
      limit: Money.major(600, Currency.usd),
    );
    await db.spend(everyday, groceries, 3000, DateTime(2026, 3, 4));
    await db.spend(berlin, groceries, 9999, DateTime(2026, 3, 5));
    await db.transactionsDao.createTransfer(
      TransferDraft(
        from: everyday,
        to: savings,
        amount: Money.major(200, Currency.usd),
        date: DateTime(2026, 3, 6),
      ),
    );

    final progress = await progressAt(DateTime(2026, 3, 20));
    expect(progress.single.spent, const Money(3000, Currency.usd));
  });

  test('deleting a category removes its budget', () async {
    await db.budgetsDao.setLimit(
      categoryId: groceries.id,
      period: BudgetPeriod.monthly,
      limit: Money.major(600, Currency.usd),
    );
    await db.categoriesDao.deleteCategory(groceries.id);
    expect(await db.budgetsDao.countAll(), 0);
  });
}
