import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/domain/date_range.dart';
import 'package:pocket_ledger/domain/entities.dart';
import 'package:pocket_ledger/domain/enums.dart';
import 'package:pocket_ledger/domain/money.dart';
import 'package:pocket_ledger/domain/services/budget_evaluator.dart';

void main() {
  const category = Category(
    id: 1,
    name: 'Dining',
    iconKey: 'dining',
    colorValue: 0,
    kind: CategoryKind.expense,
    parentId: null,
    archived: false,
  );

  BudgetProgress evaluate({
    required int limitMinor,
    required int spentMinor,
    required DateTime now,
    DateRange? window,
  }) {
    return evaluateBudget(
      budget: Budget(
        id: 1,
        categoryId: 1,
        period: BudgetPeriod.monthly,
        limit: Money(limitMinor, Currency.usd),
      ),
      category: category,
      spent: Money(spentMinor, Currency.usd),
      window: window ?? DateRange.month(now),
      now: now,
    );
  }

  test('spending below the pace is on track', () {
    final progress = evaluate(
      limitMinor: 31000,
      spentMinor: 5000,
      now: DateTime(2026, 3, 10),
    );

    expect(progress.health, BudgetHealth.onTrack);
    expect(progress.expectedSpendAtPace, const Money(10000, Currency.usd));
    expect(progress.remaining, const Money(26000, Currency.usd));
    expect(progress.percentUsed, 16);
    expect(progress.isOverBudget, isFalse);
  });

  test('spending above the pace but under the limit is a warning', () {
    final progress = evaluate(
      limitMinor: 31000,
      spentMinor: 15000,
      now: DateTime(2026, 3, 10),
    );

    expect(progress.health, BudgetHealth.aheadOfPace);
    expect(progress.isOverBudget, isFalse);
  });

  test('reaching the limit exactly is already over budget', () {
    final progress = evaluate(
      limitMinor: 10000,
      spentMinor: 10000,
      now: DateTime(2026, 3, 10),
    );

    expect(progress.health, BudgetHealth.overBudget);
    expect(progress.remaining, const Money.zero(Currency.usd));
    expect(progress.percentUsed, 100);
  });

  test('the progress bar fraction is clamped but the percentage is not', () {
    final progress = evaluate(
      limitMinor: 10000,
      spentMinor: 25000,
      now: DateTime(2026, 3, 10),
    );

    expect(progress.fractionUsed, 1.0);
    expect(progress.percentUsed, 250);
    expect(progress.remaining, const Money(-15000, Currency.usd));
  });

  test('the pace target grows with the days of the window', () {
    for (final (day, expected) in <(int, int)>[
      (1, 1000),
      (10, 10000),
      (31, 31000),
    ]) {
      final progress = evaluate(
        limitMinor: 31000,
        spentMinor: 0,
        now: DateTime(2026, 3, day),
      );
      expect(
        progress.expectedSpendAtPace.minorUnits,
        expected,
        reason: 'day $day',
      );
    }
  });

  test('a weekly window paces over seven days', () {
    final progress = evaluate(
      limitMinor: 7000,
      spentMinor: 3000,
      now: DateTime(2026, 3, 18),
      window: DateRange.week(DateTime(2026, 3, 18)),
    );

    // Wednesday is the third day of the week.
    expect(progress.expectedSpendAtPace, const Money(3000, Currency.usd));
    expect(progress.health, BudgetHealth.onTrack);
  });

  test('a zero limit never reports over budget or divides by zero', () {
    final progress = evaluate(
      limitMinor: 0,
      spentMinor: 500,
      now: DateTime(2026, 3, 10),
    );

    expect(progress.fractionUsed, 0);
    expect(progress.percentUsed, 0);
    expect(progress.health, BudgetHealth.aheadOfPace);
  });
}
