import 'package:meta/meta.dart';

import '../date_range.dart';
import '../entities.dart';
import '../money.dart';

/// Where a category sits against its limit right now.
enum BudgetHealth {
  /// Spending is below the limit and below the pace needed to reach it.
  onTrack,

  /// Still under the limit, but spending faster than the period allows.
  aheadOfPace,

  /// At or over the limit.
  overBudget,
}

@immutable
final class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.category,
    required this.spent,
    required this.window,
    required this.health,
    required this.expectedSpendAtPace,
  });

  final Budget budget;
  final Category category;

  /// Positive magnitude spent inside [window].
  final Money spent;

  /// The concrete interval the limit was measured over — the week, month or
  /// year that contained "now" when the query ran.
  final DateRange window;

  final BudgetHealth health;

  /// What an evenly paced spender would have spent by now. Drives the pace
  /// marker on the progress bar.
  final Money expectedSpendAtPace;

  Money get limit => budget.limit;

  Money get remaining => budget.limit - spent;

  /// Clamped to `0..1` for the progress bar; [percentUsed] is the honest
  /// number and can go past 100.
  double get fractionUsed {
    if (budget.limit.minorUnits <= 0) return 0;
    final ratio = spent.minorUnits / budget.limit.minorUnits;
    return ratio.clamp(0.0, 1.0);
  }

  int get percentUsed => spent.percentOf(budget.limit);

  bool get isOverBudget => health == BudgetHealth.overBudget;
}

/// A free function, not a method, so the rule — over budget means spent >=
/// limit, ahead of pace means you are outspending the calendar — is testable
/// without a database or a widget tree.
BudgetProgress evaluateBudget({
  required Budget budget,
  required Category category,
  required Money spent,
  required DateRange window,
  required DateTime now,
}) {
  final limit = budget.limit;
  final elapsed = window.elapsedDays(now);
  final totalDays = window.days;

  // limit * elapsed / totalDays, truncated. Multiply before dividing or a
  // small limit rounds to nothing early in the window.
  final expectedMinor = totalDays <= 0
      ? limit.minorUnits
      : limit.minorUnits * elapsed ~/ totalDays;
  final expected = Money(expectedMinor, limit.currency);

  final BudgetHealth health;
  if (limit.minorUnits > 0 && spent.minorUnits >= limit.minorUnits) {
    health = BudgetHealth.overBudget;
  } else if (spent.minorUnits > expectedMinor) {
    health = BudgetHealth.aheadOfPace;
  } else {
    health = BudgetHealth.onTrack;
  }

  return BudgetProgress(
    budget: budget,
    category: category,
    spent: spent,
    window: window,
    health: health,
    expectedSpendAtPace: expected,
  );
}
