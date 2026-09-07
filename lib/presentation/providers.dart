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

/// The open database.
///
/// Opened once in `main` and injected through a `ProviderScope` override, so
/// tests can hand in an in-memory one. Reading it without an override is a
/// wiring mistake, so it says so rather than silently opening a file.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(
    'databaseProvider must be overridden with an open AppDatabase',
  ),
);

/// "Now", as a provider, so that screens are deterministic under test and the
/// dashboard can be pinned to a fixed date in a widget test.
final nowProvider = Provider<DateTime>((ref) => DateTime.now());

final moneyFormatterProvider = Provider<MoneyFormatter>(
  (ref) => MoneyFormatter(),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(databaseProvider)),
);

/// The currency every aggregate on the dashboard is denominated in.
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

/// The month the dashboard is looking at. Defaults to the current one and can
/// be stepped backwards and forwards.
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

/// Six months of income and expense, ending with the selected month.
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
  // When looking at a past month, evaluate the pace at its end rather than
  // pretending today's date applies to it.
  final asOf =
      DateTime(month.year, month.month) == DateTime(now.year, now.month)
      ? now
      : DateRange.month(month).end.subtract(const Duration(seconds: 1));

  return ref
      .watch(databaseProvider)
      .budgetsDao
      .watchProgress(now: asOf, currency: ref.watch(activeCurrencyProvider));
});

/// Only the budgets for the month, which is what the dashboard summarises.
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

/// The filter the transactions screen is applying.
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

/// How many rows the transactions list is currently asking for.
///
/// Paging is done by widening the SQL `LIMIT` as the user reaches the end of
/// the list. The query stays a single indexed read; nothing is accumulated in
/// Dart, so a change to any visible row still arrives through the stream.
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

/// Total number of entries in the ledger, ignoring the current filter.
///
/// Asks for a single row and reads the count that comes back with it, so this
/// is a `COUNT(*)` rather than a table read.
final ledgerCountProvider = StreamProvider<int>((ref) {
  return ref
      .watch(databaseProvider)
      .transactionsDao
      .watchPage(limit: 1)
      .map((page) => page.totalCount);
});

/// Drives the difference between "no transactions yet" and "nothing matches
/// your filter", which need different empty states.
final ledgerIsEmptyProvider = Provider<AsyncValue<bool>>(
  (ref) => ref.watch(ledgerCountProvider).whenData((count) => count == 0),
);
