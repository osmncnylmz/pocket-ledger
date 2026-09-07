import 'package:drift/drift.dart';

import '../../domain/date_range.dart';
import '../../domain/entities.dart';
import '../../domain/enums.dart';
import '../../domain/money.dart';
import '../../domain/services/budget_evaluator.dart';
import '../database.dart';

part 'budgets_dao.g.dart';

/// Budgets and the spending measured against them.
@DriftAccessor(tables: [Budgets, Categories, Transactions, Accounts])
class BudgetsDao extends DatabaseAccessor<AppDatabase> with _$BudgetsDaoMixin {
  BudgetsDao(super.db);

  /// Every budget with the amount spent inside its current window.
  ///
  /// One query does the whole job. The three possible windows (week, month,
  /// year) are computed in Dart — so daylight saving and month lengths are
  /// handled by `DateTime` rather than by SQL date maths — and then selected
  /// per row with a `CASE` on the budget's period. The alternative, a query per
  /// budget, would be N+1.
  Stream<List<BudgetProgress>> watchProgress({
    required DateTime now,
    required Currency currency,
  }) {
    final week = DateRange.week(now);
    final month = DateRange.month(now);
    final year = DateRange.year(now);

    return customSelect(
      '''
SELECT
  b.id           AS budget_id,
  b.category_id  AS budget_category_id,
  b.period       AS budget_period,
  b.limit_minor  AS limit_minor,
  c.name         AS category_name,
  c.icon_key     AS category_icon_key,
  c.color_value  AS category_color_value,
  c.kind         AS category_kind,
  c.parent_id    AS category_parent_id,
  c.archived     AS category_archived,
  COALESCE(
    SUM(CASE WHEN a.currency_code = ? THEN -t.amount_minor END), 0
  )              AS spent_minor
FROM budgets b
JOIN categories c ON c.id = b.category_id
LEFT JOIN transactions t
       ON t.category_id = b.category_id
      AND t.type = 'expense'
      AND t.date >= CASE b.period
                      WHEN 'weekly' THEN ?
                      WHEN 'yearly' THEN ?
                      ELSE ? END
      AND t.date <  CASE b.period
                      WHEN 'weekly' THEN ?
                      WHEN 'yearly' THEN ?
                      ELSE ? END
LEFT JOIN accounts a ON a.id = t.account_id
GROUP BY b.id
ORDER BY c.name
''',
      variables: [
        Variable<String>(currency.code),
        Variable<DateTime>(week.start),
        Variable<DateTime>(year.start),
        Variable<DateTime>(month.start),
        Variable<DateTime>(week.end),
        Variable<DateTime>(year.end),
        Variable<DateTime>(month.end),
      ],
      readsFrom: {budgets, categories, transactions, accounts},
    ).watch().map((rows) {
      return rows.map((row) {
        final period = BudgetPeriod.values.byName(
          row.read<String>('budget_period'),
        );
        final categoryId = row.read<int>('budget_category_id');
        final budget = Budget(
          id: row.read<int>('budget_id'),
          categoryId: categoryId,
          period: period,
          limit: Money(row.read<int>('limit_minor'), currency),
        );
        final category = Category(
          id: categoryId,
          name: row.read<String>('category_name'),
          iconKey: row.read<String>('category_icon_key'),
          colorValue: row.read<int>('category_color_value'),
          kind: CategoryKind.values.byName(row.read<String>('category_kind')),
          parentId: row.read<int?>('category_parent_id'),
          archived: row.read<int>('category_archived') != 0,
        );

        return evaluateBudget(
          budget: budget,
          category: category,
          spent: Money(row.read<int>('spent_minor'), currency),
          window: switch (period) {
            BudgetPeriod.weekly => week,
            BudgetPeriod.monthly => month,
            BudgetPeriod.yearly => year,
          },
          now: now,
        );
      }).toList();
    });
  }

  Future<Budget?> findForCategory(
    int categoryId,
    BudgetPeriod period,
    Currency currency,
  ) async {
    final row =
        await (select(budgets)..where(
              (b) =>
                  b.categoryId.equals(categoryId) &
                  b.period.equalsValue(period),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return Budget(
      id: row.id,
      categoryId: row.categoryId,
      period: row.period,
      limit: Money(row.limitMinor, currency),
    );
  }

  /// Creates or replaces the limit for a category and period.
  ///
  /// `UNIQUE(category_id, period)` in the schema makes "one limit per category
  /// per period" a database guarantee, and this upsert leans on it instead of
  /// racing a read-then-write.
  Future<void> setLimit({
    required int categoryId,
    required BudgetPeriod period,
    required Money limit,
  }) {
    return into(budgets).insert(
      BudgetsCompanion.insert(
        categoryId: categoryId,
        limitMinor: limit.minorUnits,
        period: Value(period),
      ),
      onConflict: DoUpdate(
        (_) => BudgetsCompanion(limitMinor: Value(limit.minorUnits)),
        target: [budgets.categoryId, budgets.period],
      ),
    );
  }

  Future<void> deleteBudget(int id) =>
      (delete(budgets)..where((b) => b.id.equals(id))).go();

  Future<int> countAll() {
    final counter = budgets.id.count();
    return (selectOnly(
      budgets,
    )..addColumns([counter])).map((row) => row.read(counter) ?? 0).getSingle();
  }
}
