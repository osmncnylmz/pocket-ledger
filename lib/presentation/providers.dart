import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup_service.dart';
import '../data/daos/transactions_dao.dart';
import '../data/database.dart';
import '../domain/date_range.dart';
import '../domain/entities.dart';
import '../domain/enums.dart';
import '../domain/money.dart';
import '../domain/money_format.dart';
import '../domain/services/budget_evaluator.dart';
import '../domain/transaction_filter.dart';
import 'settings.dart';

/// Opened once in `main` and injected through a `ProviderScope` override, so
/// tests can hand in an in-memory one. Unoverridden it throws; a test that
/// quietly opened a file on disk would be worse than one that failed.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(
    'databaseProvider must be overridden with an open AppDatabase',
  ),
);

/// "Now" as a provider, so a widget test can pin the dashboard to a fixed
/// date and not race the clock.
final nowProvider = Provider<DateTime>((ref) => DateTime.now());

final moneyFormatterProvider = Provider<MoneyFormatter>(
  (ref) => MoneyFormatter(),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(databaseProvider)),
);

final activeCurrencyProvider = Provider<Currency>(
  (ref) => ref.watch(settingsProvider).currency,
);

final accountBalancesProvider = StreamProvider<List<AccountBalance>>(
  (ref) => ref.watch(databaseProvider).accountsDao.watchBalances(),
);

final allAccountsProvider = StreamProvider<List<Account>>(
  (ref) => ref
      .watch(databaseProvider)
      .accountsDao
      .watchAccounts(includeArchived: true),
);

final totalsByCurrencyProvider = StreamProvider<Map<Currency, Money>>(
  (ref) => ref.watch(databaseProvider).accountsDao.watchTotalsByCurrency(),
);

final categoriesProvider = StreamProvider.family<List<Category>, CategoryKind?>(
  (ref, kind) =>
      ref.watch(databaseProvider).categoriesDao.watchCategories(kind: kind),
);

class SelectedMonth extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = ref.watch(nowProvider);
    return DateTime(now.year, now.month);
  }

  void previous() => state = DateTime(state.year, state.month - 1);

  void next() => state = DateTime(state.year, state.month + 1);

  void reset() {
    final now = ref.read(nowProvider);
    state = DateTime(now.year, now.month);
  }
}

final selectedMonthProvider = NotifierProvider<SelectedMonth, DateTime>(
  SelectedMonth.new,
);

final monthlySpendProvider = StreamProvider<List<CategorySpend>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  return ref
      .watch(databaseProvider)
      .transactionsDao
      .watchCategorySpend(
        DateRange.month(month),
        currency: ref.watch(activeCurrencyProvider),
      );
});

final trendProvider = StreamProvider<List<MonthlyTotals>>((ref) {
  return ref
      .watch(databaseProvider)
      .transactionsDao
      .watchMonthlyTotals(
        endingIn: ref.watch(selectedMonthProvider),
        months: 6,
        currency: ref.watch(activeCurrencyProvider),
      );
});

final budgetProgressProvider = StreamProvider<List<BudgetProgress>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  final now = ref.watch(nowProvider);
  // A past month is paced from its own end; today's date says nothing about
  // how far through March you were.
  final asOf =
      DateTime(month.year, month.month) == DateTime(now.year, now.month)
      ? now
      : DateRange.month(month).end.subtract(const Duration(seconds: 1));

  return ref
      .watch(databaseProvider)
      .budgetsDao
      .watchProgress(now: asOf, currency: ref.watch(activeCurrencyProvider));
});

/// Monthly budgets only; weekly and yearly ones would not add up against a
/// month's spending.
final monthlyBudgetProgressProvider =
    Provider<AsyncValue<List<BudgetProgress>>>(
      (ref) => ref
          .watch(budgetProgressProvider)
          .whenData(
            (all) => all
                .where((p) => p.budget.period == BudgetPeriod.monthly)
                .toList(),
          ),
    );

class TransactionFilterController extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() => TransactionFilter.empty;

  void setText(String text) => state = state.copyWith(text: text);

  void apply(TransactionFilter filter) => state = filter;

  void clear() => state = TransactionFilter.empty;
}

final transactionFilterProvider =
    NotifierProvider<TransactionFilterController, TransactionFilter>(
      TransactionFilterController.new,
    );

/// Paging widens the SQL `LIMIT` as the user reaches the end of the list.
/// Nothing accumulates in Dart, so the query stays one indexed read and an
/// edit to any visible row still arrives through the stream.
class VisibleRowCount extends Notifier<int> {
  static const pageSize = 40;

  @override
  int build() {
    // Reset paging whenever the filter changes.
    ref.watch(transactionFilterProvider);
    return pageSize;
  }

  void loadMore() => state = state + pageSize;
}

final visibleRowCountProvider = NotifierProvider<VisibleRowCount, int>(
  VisibleRowCount.new,
);

final ledgerPageProvider = StreamProvider<LedgerPage>((ref) {
  return ref
      .watch(databaseProvider)
      .transactionsDao
      .watchPage(
        filter: ref.watch(transactionFilterProvider),
        limit: ref.watch(visibleRowCountProvider),
      );
});

/// Every entry, filter ignored. Asks for a single row and reads the count that
/// rides along with it, so it costs a `COUNT(*)` and not a table read.
final ledgerCountProvider = StreamProvider<int>((ref) {
  return ref
      .watch(databaseProvider)
      .transactionsDao
      .watchPage(limit: 1)
      .map((page) => page.totalCount);
});

/// Separates "no transactions yet" from "nothing matches your filter". They
/// want different empty states.
final ledgerIsEmptyProvider = Provider<AsyncValue<bool>>(
  (ref) => ref.watch(ledgerCountProvider).whenData((count) => count == 0),
);
